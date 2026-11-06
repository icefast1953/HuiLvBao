package yuebao

import std.collection.*
import stdx.encoding.json.*

func localRequestAllowed(host: String, origin: String): Bool {
    return (host == "127.0.0.1:18627" || host == "localhost:18627") &&
        (origin.isEmpty() || origin == "http://127.0.0.1:18627" || origin == "http://localhost:18627")
}

func conversionResult(state: StateStore, snapshot: JsonObject, base: String, amount: String, all: Bool): JsonObject {
    state.currency(base)
    let quotes = HashMap<String, JsonObject>()
    for (item in snapshot["rows"].asArray().getItems()) {
        let code = textField(item.asObject(), "quote")
        if (state.verified.contains(code)) { quotes[code] = item.asObject() }
    }
    let result = JsonObject()
    let rows = JsonArray()
    for (item in state.catalog.getItems()) {
        let currency = item.asObject()
        let code = textField(currency, "code")
        if (!all && !state.favorites.contains(code)) { continue }
        let row = JsonObject()
        row.put("code", JsonString(code)); row.put("zh_name", currency["zh_name"]); row.put("en_name", currency["en_name"])
        row.put("amount", JsonNull()); row.put("rate", JsonNull()); row.put("date", JsonString("")); row.put("fetchedAt", JsonString(""))
        if (code == base) {
            row.put("rate", JsonString("1"))
            if (validAmount(amount)) { row.put("amount", JsonString(convertAmount(amount, "1", integerField(currency, "minor_units")))) }
        } else if (let Some(rate) <- quotes.get(code)) {
            row.put("rate", rate["rate"]); row.put("date", rate["date"])
            row.put("fetchedAt", rate.get("fetchedAt") ?? snapshot["fetchedAt"])
            if (validAmount(amount)) { row.put("amount", JsonString(convertAmount(amount, textField(rate, "rate"), integerField(currency, "minor_units")))) }
        }
        rows.add(row)
    }
    if (!all) {
        let ordered = JsonArray()
        for (code in state.favorites) {
            for (row in rows.getItems()) { if (textField(row.asObject(), "code") == code) { ordered.add(row) } }
        }
        result.put("rows", ordered)
    } else { result.put("rows", rows) }
    result.put("source", JsonString(base)); result.put("amount", JsonString(amount))
    result.put("cached", snapshot["cached"]); result.put("error", snapshot["error"]); result.put("fetchedAt", snapshot["fetchedAt"])
    result.put("inputError", JsonBool(!amount.isEmpty() && amount != "." && !validAmount(amount)))
    return result
}
