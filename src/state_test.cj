package yuebao

import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import stdx.encoding.json.*

@Test
class StateTests {
    @TestCase
    func favoritesAndSettingsSurviveReopen() {
        if (!exists(".local")) { Directory.create(".local", recursive: true) }
        let path = Directory.createTemp(".local").toString()
        let store = StateStore(path)
        store.addFavorite("JPY")
        store.addFavorite("JPY")
        @Expect(store.favorites.size, 6)
        store.updateSettings(JsonValue.fromStr(#"{"language":"en","font":"serif","size":"large","autoUpdate":false,"interval":6}"#).asObject())
        let restored = StateStore(path)
        @Expect(restored.favorites.size, 6)
        @Expect(restored.language, "en")
        @Expect(restored.interval, 6)
        @Expect(restored.autoUpdate, false)
    }

    @TestCase
    func lastFavoriteIsProtectedAndUnknownRejected() {
        if (!exists(".local")) { Directory.create(".local", recursive: true) }
        let store = StateStore(Directory.createTemp(".local").toString())
        for (code in ["USD", "GBP", "EUR", "HKD"]) { store.removeFavorite(code) }
        var rejected = false
        try { store.removeFavorite("CNY") } catch (_: Exception) { rejected = true }
        @Expect(rejected, true)
        @Expect(store.favorites.size, 1)
        rejected = false
        try { store.addFavorite("XYZ") } catch (_: Exception) { rejected = true }
        @Expect(rejected, true)
    }

    @TestCase
    func invalidSettingsCannotPartiallyApply() {
        if (!exists(".local")) { Directory.create(".local", recursive: true) }
        let store = StateStore(Directory.createTemp(".local").toString())
        try {
            store.updateSettings(JsonValue.fromStr(#"{"language":"en","font":"serif","size":"large","autoUpdate":true,"interval":2}"#).asObject())
        } catch (_: Exception) {}
        @Expect(store.language, "zh")
        @Expect(store.interval, 24)
    }
}
