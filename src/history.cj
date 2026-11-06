package yuebao

import std.collection.*
import std.fs.*
import std.sort.*
import std.time.*
import stdx.encoding.json.*

func normalizeHistory(raw: String, base: String, target: String, from: String, to: String): JsonArray {
    if (!validDate(from) || !validDate(to) || from > to) { throw IllegalArgumentException("INVALID_RANGE") }
    let rows = parseRateRows(raw, base, allowEmpty: true)
    let byDate = HashMap<String, JsonValue>()
    for (item in rows.getItems()) {
        let row = item.asObject()
        let date = textField(row, "date")
        if (textField(row, "quote") != target || date < from || date > to) { throw IllegalArgumentException("INVALID_HISTORY") }
        if (let Some(previous) <- byDate.get(date)) {
            if (textField(previous.asObject(), "rate") != textField(row, "rate")) { throw IllegalArgumentException("CONFLICTING_HISTORY") }
        } else { byDate[date] = row }
    }
    let points = ArrayList<JsonValue>()
    for ((_, row) in byDate) { points.add(row) }
    sort(points, key: {row => textField(row.asObject(), "date")})
    return JsonArray(points)
}

extend RateStore {
    func history(base: String, target: String, days: Int64, refresh: Bool): JsonObject {
        state.currency(base); state.currency(target)
        if (!verified.contains(base) || !verified.contains(target)) { throw IllegalArgumentException("UNVERIFIED_CURRENCY") }
        if (base == target || (days != 7 && days != 30 && days != 90)) { throw IllegalArgumentException("INVALID_RANGE") }
        let today = DateTime.nowUTC()
        let to = today.format("yyyy-MM-dd")
        let from = (today - Duration.day * (days - 1)).format("yyyy-MM-dd")
        let path = state.root + "/history-" + base + "-" + target + "-" + from + "-" + to + ".json"
        var snapshot = JsonObject()
        if (exists(path)) { snapshot = readJson(path).asObject() }
        snapshot.put("cached", JsonBool(true)); snapshot.put("error", JsonString(""))
        if (!refresh && snapshot.containsKey("rows")) { return snapshot }
        try {
            let rows = normalizeHistory(fetch("https://api.frankfurter.dev/v2/rates?base=" + base + "&quotes=" + target + "&from=" + from + "&to=" + to), base, target, from, to)
            let fresh = JsonObject()
            fresh.put("base", JsonString(base)); fresh.put("target", JsonString(target))
            fresh.put("from", JsonString(from)); fresh.put("to", JsonString(to)); fresh.put("rows", rows)
            fresh.put("fetchedAt", JsonString(DateTime.nowUTC().toString()))
            fresh.put("cached", JsonBool(false)); fresh.put("error", JsonString(""))
            saveJson(path, fresh)
            return fresh
        } catch (_: Exception) {
            snapshot.put("base", JsonString(base)); snapshot.put("target", JsonString(target))
            snapshot.put("from", JsonString(from)); snapshot.put("to", JsonString(to))
            snapshot.put("error", JsonString("REFRESH_FAILED"))
            if (!snapshot.containsKey("rows")) { snapshot.put("rows", JsonArray()); snapshot.put("fetchedAt", JsonString("")) }
            return snapshot
        }
    }
}
