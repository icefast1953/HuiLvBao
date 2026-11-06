package yuebao

import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import stdx.encoding.json.*

let sampleRates = #"[{"date":"2026-10-26","base":"CNY","quote":"USD","rate":0.125},{"date":"2026-10-26","base":"CNY","quote":"JPY","rate":1.505e2}]"#

@Test
class RateTests {
    @TestCase
    func preservesNumericTokensAndDirection() {
        let rows = parseRateRows(sampleRates, "CNY")
        @Expect(textField(rows[0].asObject(), "rate"), "0.125")
        @Expect(textField(rows[1].asObject(), "rate"), "150.5")
        let precise = parseRateRows(#"[{"date":"2026-10-26","base":"CNY","quote":"USD","rate":0.1234567890123456789}]"#, "CNY")
        @Expect(textField(precise[0].asObject(), "rate"), "0.1234567890123456789")
    }

    @TestCase
    func rejectsWrongDirectionDateAndNonpositive() {
        for (raw in [sampleRates.replace("CNY", "USD"), sampleRates.replace("0.125", "0"),
            sampleRates.replace("2026-10-26", "2026-02-30"), sampleRates.replace("0.125", "-1"), "{}", "[]"]) {
            var rejected = false
            try { parseRateRows(raw, "CNY") } catch (_: Exception) { rejected = true }
            @Expect(rejected, true)
        }
    }

    @TestCase
    func failedRefreshKeepsExactCacheAndTimes() {
        if (!exists(".local")) { Directory.create(".local") }
        let state = StateStore(Directory.createTemp(".local").toString())
        let repository = RateStore(state, {_ => sampleRates})
        let first = repository.latest("CNY", true)
        let second = RateStore(state, {_ => "INVALID"}).latest("CNY", true)
        @Expect(second["rows"].toJsonString(), first["rows"].toJsonString())
        @Expect(textField(second, "fetchedAt"), textField(first, "fetchedAt"))
        @Expect(second["cached"].asBool().getValue(), true)
        @Expect(textField(second, "error").isEmpty(), false)
    }
}
