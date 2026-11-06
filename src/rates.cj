package yuebao

import std.collection.*
import std.convert.*
import std.fs.*
import std.io.*
import std.time.*
import std.math.numeric.BigInt
import std.sort.*
import std.sync.*
import std.net.TcpSocket
import stdx.encoding.json.*
import stdx.net.http.*
import stdx.net.tls.*

// Preserve each JSON number's decimal token before the JSON library can turn it into Float64.
func preserveNumbers(raw: String): String {
    let bytes = raw.toArray()
    let result = ArrayList<UInt8>()
    var i: Int64 = 0
    var quoted = false
    var escaped = false
    while (i < bytes.size) {
        let byte = bytes[i]
        if (quoted) {
            result.add(byte)
            if (escaped) { escaped = false } else if (byte == 92) { escaped = true } else if (byte == 34) { quoted = false }
            i++
        } else if (byte == 34) {
            quoted = true; result.add(byte); i++
        } else if (byte == 45 || (byte >= 48 && byte <= 57)) {
            result.add(34)
            while (i < bytes.size) {
                let current = bytes[i]
                if ((current >= 48 && current <= 57) || current == 45 || current == 43 || current == 46 || current == 101 || current == 69) {
                    result.add(current); i++
                } else { break }
            }
            result.add(34)
        } else { result.add(byte); i++ }
    }
    return String.fromUtf8(result.toArray())
}

func plainDecimal(text: String): String {
    let parts = text.replace("E", "e").split("e")
    if (parts.size == 1) { return text }
    if (parts.size != 2) { throw IllegalArgumentException("INVALID_RATE") }
    let exponent = Int64.parse(parts[1])
    if (exponent < -30 || exponent > 30) { throw IllegalArgumentException("INVALID_RATE") }
    let mantissa = parts[0].split(".")
    var digits = parts[0].replace(".", "")
    let point = mantissa[0].size + exponent
    if (point <= 0) {
        var zeros = ""
        for (_ in 0..-point) { zeros += "0" }
        return "0." + zeros + digits
    }
    while (digits.size < point) { digits += "0" }
    return if (point == digits.size) { digits } else { digits[..point] + "." + digits[point..] }
}

func validDate(date: String): Bool {
    if (date.size != 10) { return false }
    try { return DateTime.parse(date, "yyyy-MM-dd").format("yyyy-MM-dd") == date } catch (_: Exception) { return false }
}

func parseRateRows(raw: String, base: String, allowEmpty!: Bool = false): JsonArray {
    JsonValue.fromStr(raw)
    let rows = JsonValue.fromStr(preserveNumbers(raw)).asArray()
    if (rows.size() == 0 && !allowEmpty) { throw IllegalArgumentException("NO_RATES") }
    for (item in rows.getItems()) {
        let row = item.asObject()
        let rate = plainDecimal(textField(row, "rate"))
        if (textField(row, "base") != base || textField(row, "quote").size != 3 ||
            !validDate(textField(row, "date")) || !validDecimal(rate, 40, 30)) {
            throw IllegalArgumentException("INVALID_RESPONSE")
        }
        let (number, _) = decimalParts(rate)
        if (number <= BigInt(0)) { throw IllegalArgumentException("INVALID_RATE") }
        row.put("rate", JsonString(rate))
    }
    return rows
}

func readStream(stream: InputStream, limit!: Int64 = 4000000): String {
    let output = ArrayList<UInt8>()
    let buffer = Array<UInt8>(8192, repeat: 0)
    while (true) {
        let length = stream.read(buffer)
        if (length == 0) { break }
        if (output.size + length > limit) { throw IllegalArgumentException("BODY_TOO_LARGE") }
        output.add(all: buffer[..length])
    }
    return String.fromUtf8(output.toArray())
}

func remoteGet(url: String): String {
    let sockets = ArrayList<TcpSocket>()
    let socketsMutex = Mutex()
    let client = ClientBuilder().tlsConfig(TlsClientConfig()).readTimeout(Duration.second * 20).writeTimeout(Duration.second * 20)
        .connector({address =>
            let socket = TcpSocket(address)
            synchronized(socketsMutex) { sockets.add(socket) }
            socket.connect(timeout: Duration.second * 10)
            socket
        }).build()
    let task = spawn {
        let response = client.get(url)
        try {
            if (response.status != 200) { throw Exception("HTTP_ERROR") }
            readStream(response.body)
        } finally { response.close() }
    }
    try {
        return task.get(Duration.second * 35)
    } finally {
        task.cancel()
        synchronized(socketsMutex) { for (socket in sockets) { socket.close() } }
        client.close()
    }
}

class PendingRequest {
    let id: Int64
    let future: Future<JsonObject>
    init(id: Int64, future: Future<JsonObject>) { this.id = id; this.future = future }
}

class RateStore {
    let state: StateStore
    let fetch: (String) -> String
    let verified: HashSet<String>
    let jobsMutex = Mutex()
    let jobs = HashMap<String, PendingRequest>()
    var nextJob: Int64 = 0

    init(state: StateStore, fetch: (String) -> String) {
        this.state = state; this.fetch = fetch
        verified = state.verified
    }

    func singleFlight(key: String, work: () -> JsonObject): JsonObject {
        let pending = synchronized(jobsMutex) {
            if (let Some(existing) <- jobs.get(key)) { existing }
            else {
                nextJob++
                let created = PendingRequest(nextJob, spawn { work() })
                jobs[key] = created
                created
            }
        }
        try { return JsonValue.fromStr(pending.future.get().toJsonString()).asObject() }
        finally {
            synchronized(jobsMutex) {
                if (let Some(current) <- jobs.get(key)) { if (current.id == pending.id) { jobs.remove(key) } }
            }
        }
    }

    func latest(base: String, refresh: Bool): JsonObject {
        state.currency(base)
        if (!verified.contains(base)) { throw IllegalArgumentException("UNVERIFIED_CURRENCY") }
        let path = state.root + "/latest-" + base + ".json"
        var snapshot = JsonObject()
        if (exists(path)) { snapshot = readJson(path).asObject() }
        if (snapshot.containsKey("rows")) {
            let valid = JsonArray()
            for (item in snapshot["rows"].asArray().getItems()) {
                if (verified.contains(textField(item.asObject(), "quote"))) { valid.add(item) }
            }
            snapshot.put("rows", valid)
        }
        snapshot.put("cached", JsonBool(true)); snapshot.put("error", JsonString(""))
        if (!refresh && snapshot.containsKey("rows")) { return snapshot }
        let cached = snapshot
        return singleFlight("latest-" + base, { => fetchLatest(base, path, cached) })
    }

    func fetchLatest(base: String, path: String, snapshot: JsonObject): JsonObject {
        try {
            let rows = parseRateRows(fetch("https://api.frankfurter.dev/v2/rates?base=" + base), base)
            let seen = HashSet<String>()
            let merged = HashMap<String, JsonValue>()
            if (snapshot.containsKey("rows")) {
                for (item in snapshot["rows"].asArray().getItems()) { merged[textField(item.asObject(), "quote")] = item }
            }
            let fetchedAt = DateTime.nowUTC().toString()
            for (item in rows.getItems()) {
                let row = item.asObject()
                let code = textField(row, "quote")
                if (!seen.add(code)) { throw IllegalArgumentException("DUPLICATE_RATE") }
                if (!verified.contains(code)) { continue }
                if (let Some(previous) <- merged.get(code)) {
                    if (textField(previous.asObject(), "date") > textField(row, "date")) { continue }
                }
                row.put("fetchedAt", JsonString(fetchedAt)); merged[code] = row
            }
            let retained = ArrayList<JsonValue>()
            for ((_, row) in merged) { retained.add(row) }
            sort(retained, key: {row => textField(row.asObject(), "quote")})
            let fresh = JsonObject()
            fresh.put("base", JsonString(base)); fresh.put("rows", JsonArray(retained))
            fresh.put("fetchedAt", JsonString(fetchedAt))
            fresh.put("cached", JsonBool(false)); fresh.put("error", JsonString(""))
            saveJson(path, fresh)
            return fresh
        } catch (_: Exception) {
            snapshot.put("base", JsonString(base)); snapshot.put("error", JsonString("REFRESH_FAILED"))
            if (!snapshot.containsKey("rows")) { snapshot.put("rows", JsonArray()); snapshot.put("fetchedAt", JsonString("")) }
            return snapshot
        }
    }
}
