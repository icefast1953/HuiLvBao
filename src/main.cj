package yuebao

import std.convert.*
import std.fs.*
import std.sync.*
import std.time.*
import stdx.encoding.json.*
import stdx.encoding.url.*
import stdx.net.http.*
import stdx.log.*

class Application {
    let state: StateStore
    let rates: RateStore
    let mutex = Mutex()
    let demo: Bool
    var activeBase = "CNY"

    init(demo: Bool) {
        this.demo = demo
        state = StateStore(if (demo) { ".local/demo" } else { ".local/live" })
        rates = RateStore(state, if (demo) { demoGet } else { remoteGet })
    }

    func handle(ctx: HttpContext): Unit {
        ctx.responseBuilder.header("X-Content-Type-Options", "nosniff").header("Cache-Control", "no-store")
            .header("Content-Security-Policy", "default-src 'self'; style-src 'self'; script-src 'self'; connect-src 'self'; img-src 'self' data:; frame-ancestors 'none'")
        if (!localRequestAllowed(ctx.request.headers.getFirst("Host") ?? "", ctx.request.headers.getFirst("Origin") ?? "")) {
            ctx.responseBuilder.status(403).body("Forbidden"); return
        }
        let path = ctx.request.url.path
        if (path == "/" || path == "/app.js" || path == "/model.mjs" || path == "/app.css") {
            if (ctx.request.method != "GET") { ctx.responseBuilder.status(405); return }
            let file = if (path == "/") { "web/index.html" } else { "web" + path }
            let mime = if (path == "/") { "text/html" } else if (path == "/app.js" || path == "/model.mjs") { "text/javascript" } else { "text/css" }
            ctx.responseBuilder.header("Content-Type", mime + "; charset=utf-8").body(File.readFrom(file)); return
        }
        ctx.responseBuilder.header("Content-Type", "application/json; charset=utf-8")
        try {
            let query = ctx.request.url.queryForm
            var result = JsonObject()
            if (path == "/api/state" && ctx.request.method == "GET") {
                synchronized(mutex) {
                    result = state.snapshot(); result.put("catalog", state.catalog)
                    result.put("demo", JsonBool(demo)); result.put("engine", JsonString("Cangjie"))
                }
            } else if (path == "/api/favorites" && ctx.request.method == "POST") {
                let body = JsonValue.fromStr(readStream(ctx.request.body, limit: 4096)).asObject()
                synchronized(mutex) {
                    let code = textField(body, "code")
                    if (textField(body, "action") == "add") { state.addFavorite(code) }
                    else if (textField(body, "action") == "remove") { state.removeFavorite(code) }
                    else { throw IllegalArgumentException("INVALID_ACTION") }
                    result = state.snapshot()
                }
            } else if (path == "/api/settings" && ctx.request.method == "POST") {
                let body = JsonValue.fromStr(readStream(ctx.request.body, limit: 4096)).asObject()
                synchronized(mutex) {
                    state.updateSettings(body)
                    result = state.snapshot()
                }
            } else if (path == "/api/convert" && ctx.request.method == "POST") {
                let body = JsonValue.fromStr(readStream(ctx.request.body, limit: 4096)).asObject()
                let base = textField(body, "source")
                synchronized(mutex) { activeBase = base }
                let snapshot = rates.latest(base, false)
                synchronized(mutex) { result = conversionResult(state, snapshot, base, textField(body, "amount"), false) }
            } else if (path == "/api/latest" && ctx.request.method == "GET") {
                let base = query.get("base") ?? "CNY"
                synchronized(mutex) { activeBase = base }
                let snapshot = rates.latest(base, (query.get("refresh") ?? "0") == "1")
                synchronized(mutex) { result = conversionResult(state, snapshot, base, "1", true) }
            } else if (path == "/api/history" && ctx.request.method == "GET") {
                result = rates.history(query.get("base") ?? "CNY", query.get("target") ?? "USD",
                    Int64.parse(query.get("days") ?? "30"), (query.get("refresh") ?? "0") == "1")
            } else { throw IllegalArgumentException("INVALID_REQUEST") }
            result.put("demo", JsonBool(demo))
            ctx.responseBuilder.body(result.toJsonString())
        } catch (error: Exception) {
            let result = JsonObject(); result.put("error", JsonString(error.message))
            ctx.responseBuilder.status(400).body(result.toJsonString())
        }
    }

    func autoRefresh(): Unit {
        while (true) {
            sleep(Duration.minute)
            let (enabled, base, interval) = synchronized(mutex) { (state.autoUpdate, activeBase, state.interval) }
            try {
                if (enabled && rates.verified.contains(base)) {
                    let snapshot = rates.latest(base, false)
                    let fetched = textField(snapshot, "fetchedAt")
                    if (!fetched.isEmpty() && DateTime.nowUTC() - DateTime.parse(fetched) >= Duration.hour * interval) {
                        rates.latest(base, true)
                    }
                }
            } catch (_: Exception) {}
        }
    }
}

func demoGet(url: String): String {
    let query = URL.parse(url).queryForm
    let base = query.get("base") ?? "CNY"
    let tables = readJson("assets/demo-rates.json").asObject()
    if (!tables.containsKey(base)) { throw Exception("NO_DEMO_RATE") }
    let result = JsonArray()
    let today = DateTime.nowUTC()
    if (query.get("from").isSome()) {
        let target = query.get("quotes") ?? "USD"
        if (!tables[base].asObject().containsKey(target)) { throw Exception("NO_DEMO_RATE") }
        for (offset in [Int64(6), 3, 0]) {
            let row = JsonObject()
            row.put("base", JsonString(base)); row.put("quote", JsonString(target))
            row.put("date", JsonString((today - Duration.day * offset).format("yyyy-MM-dd")))
            row.put("rate", tables[base].asObject()[target]); result.add(row)
        }
    } else {
        for ((code, rate) in tables[base].asObject().getFields()) {
            let row = JsonObject()
            row.put("base", JsonString(base)); row.put("quote", JsonString(code))
            row.put("date", JsonString(today.format("yyyy-MM-dd"))); row.put("rate", rate); result.add(row)
        }
    }
    return result.toJsonString()
}

main(args: Array<String>): Int64 {
    let demo = args.contains("--demo")
    let app = Application(demo)
    if (args.contains("--probe")) {
        if (!demo) {
            try { println("HTTPS_BODY_BYTES=${remoteGet("https://api.frankfurter.dev/v2/rates?base=CNY").size}") }
            catch (error: Exception) { println("HTTPS_PROBE_ERROR=${error.message}"); return 1 }
        }
        let latest = app.rates.latest("CNY", true)
        let history = app.rates.history("CNY", "USD", 30, true)
        println(latest.toJsonString()); println(history.toJsonString())
        return if (textField(latest, "error").isEmpty() && textField(history, "error").isEmpty()) { 0 } else { 1 }
    }
    let server = ServerBuilder().addr("127.0.0.1").port(18627).readTimeout(Duration.second * 30).build()
    for (path in ["/", "/app.js", "/model.mjs", "/app.css", "/api/state", "/api/favorites", "/api/settings", "/api/convert", "/api/latest", "/api/history"]) {
        server.distributor.register(path, {ctx => app.handle(ctx)})
    }
    server.logger.level = LogLevel.OFF
    spawn { app.autoRefresh() }
    println(if (demo) { "DEMO DATA - http://127.0.0.1:18627" } else { "Huilvbao - http://127.0.0.1:18627" })
    server.serve()
    return 0
}
