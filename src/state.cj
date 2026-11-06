package yuebao

import std.collection.*
import std.fs.*
import stdx.encoding.json.*

func textField(value: JsonObject, key: String): String { value[key].asString().getValue() }
func integerField(value: JsonObject, key: String): Int64 { value[key].asInt().getValue() }
func readJson(path: String): JsonValue { JsonValue.fromStr(String.fromUtf8(File.readFrom(path))) }
func saveJson(path: String, value: JsonValue): Unit {
    File.writeTo(path + ".tmp", value.toJsonString().toArray())
    rename(path + ".tmp", to: path, overwrite: true)
}

class StateStore {
    let root: String
    let catalog: JsonArray
    let verified = HashSet<String>()
    var favorites = ArrayList<String>(["CNY", "USD", "GBP", "EUR", "HKD"])
    var language = "zh"
    var font = "system"
    var size = "normal"
    var autoUpdate = true
    var interval: Int64 = 24

    init(root: String) {
        this.root = root
        if (!exists(root)) { Directory.create(root, recursive: true) }
        catalog = readJson("assets/currencies.json").asArray()
        for (code in readJson("assets/identity-bindings.json").asObject()["codes"].asArray().getItems()) {
            verified.add(code.asString().getValue())
        }
        if (exists(root + "/preferences.json")) {
            let saved = readJson(root + "/preferences.json").asObject()
            let restored = ArrayList<String>()
            for (item in saved["favorites"].asArray().getItems()) {
                let code = item.asString().getValue()
                currency(code)
                if (!restored.contains(code)) { restored.add(code) }
            }
            if (restored.isEmpty()) { throw IllegalArgumentException("LAST_FAVORITE") }
            favorites = restored
            updateSettings(saved["settings"].asObject())
        }
    }

    func currency(code: String): JsonObject {
        for (item in catalog.getItems()) {
            let value = item.asObject()
            if (textField(value, "code") == code) { return value }
        }
        throw IllegalArgumentException("UNKNOWN_CURRENCY")
    }

    func addFavorite(code: String): Unit {
        currency(code)
        if (!favorites.contains(code)) { favorites.add(code); save() }
    }

    func removeFavorite(code: String): Unit {
        if (favorites.size == 1 && favorites[0] == code) { throw IllegalArgumentException("LAST_FAVORITE") }
        for (i in 0..favorites.size) {
            if (favorites[i] == code) { favorites.remove(at: i); save(); return }
        }
    }

    func updateSettings(value: JsonObject): Unit {
        let newLanguage = textField(value, "language")
        let newFont = textField(value, "font")
        let newSize = textField(value, "size")
        let newAuto = value["autoUpdate"].asBool().getValue()
        let newInterval = integerField(value, "interval")
        if ((newLanguage != "zh" && newLanguage != "en" && newLanguage != "system") ||
            (newFont != "system" && newFont != "sans" && newFont != "serif") ||
            (newSize != "small" && newSize != "normal" && newSize != "large") ||
            (newInterval != 1 && newInterval != 6 && newInterval != 12 && newInterval != 24)) {
            throw IllegalArgumentException("INVALID_SETTINGS")
        }
        language = newLanguage; font = newFont; size = newSize
        autoUpdate = newAuto; interval = newInterval
        save()
    }

    func settingsJson(): JsonObject {
        let value = JsonObject()
        value.put("language", JsonString(language)); value.put("font", JsonString(font))
        value.put("size", JsonString(size)); value.put("autoUpdate", JsonBool(autoUpdate))
        value.put("interval", JsonInt(interval))
        return value
    }

    func snapshot(): JsonObject {
        let value = JsonObject()
        let items = JsonArray()
        for (code in favorites) { items.add(JsonString(code)) }
        value.put("favorites", items); value.put("settings", settingsJson())
        return value
    }

    func save(): Unit { saveJson(root + "/preferences.json", snapshot()) }
}
