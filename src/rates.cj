package yuebao

import std.collection.*
import std.convert.*
import std.fs.*
import std.io.*
import std.time.*
import std.math.numeric.BigInt
import stdx.encoding.json.*
import stdx.net.http.*

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
    let client = ClientBuilder().readTimeout(Duration.second * 20).writeTimeout(Duration.second * 20).build()
    try {
        let response = client.get(url)
        try {
            if (response.status != 200) { throw Exception("HTTP_ERROR") }
            return readStream(response.body)
        } finally { response.close() }
    } finally { client.close() }
}

class RateStore {
    let state: StateStore
    let fetch: (String) -> String
    let verified = HashSet<String>()

    init(state: StateStore, fetch: (String) -> String) {
        this.state = state; this.fetch = fetch
        for (code in readJson("assets/identity-bindings.json").asObject()["codes"].asArray().getItems()) {
            verified.add(code.asString().getValue())
        }
    }

    func latest(base: String, refresh: Bool): JsonObject {
        state.currency(base)
        if (!verified.contains(base)) { throw IllegalArgumentException("UNVERIFIED_CURRENCY") }
        let path = state.root + "/latest-" + base + ".json"
        var snapshot = JsonObject()
        if (exists(path)) { snapshot = readJson(path).asObject() }
        snapshot.put("cached", JsonBool(true)); snapshot.put("error", JsonString(""))
        if (!refresh && snapshot.containsKey("rows")) { return snapshot }
        try {
            let rows = parseRateRows(fetch("https://api.frankfurter.dev/v2/rates?base=" + base), base)
            let seen = HashSet<String>()
            for (item in rows.getItems()) {
                let code = textField(item.asObject(), "quote")
                if (!seen.add(code)) { throw IllegalArgumentException("DUPLICATE_RATE") }
            }
            let fresh = JsonObject()
            fresh.put("base", JsonString(base)); fresh.put("rows", rows)
            fresh.put("fetchedAt", JsonString(DateTime.nowUTC().toString()))
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
