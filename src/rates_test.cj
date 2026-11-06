package yuebao

import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import stdx.encoding.json.*
import std.sync.*
import std.time.*

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

    @TestCase
    func partialAndOlderResponsesKeepExistingQuotes() {
        if (!exists(".local")) { Directory.create(".local") }
        let state = StateStore(Directory.createTemp(".local").toString())
        RateStore(state, {_ => sampleRates}).latest("CNY", true)
        let older = #"[{"date":"2026-10-25","base":"CNY","quote":"USD","rate":0.1}]"#
        let retained = RateStore(state, {_ => older}).latest("CNY", true)
        @Expect(retained["rows"].asArray().size(), 2)
        for (item in retained["rows"].asArray().getItems()) {
            if (textField(item.asObject(), "quote") == "USD") {
                @Expect(textField(item.asObject(), "rate"), "0.125")
                @Expect(textField(item.asObject(), "date"), "2026-10-26")
            }
        }
    }

    @TestCase
    func malformedJsonNumbersStayInvalid() {
        var rejected = false
        try { parseRateRows(sampleRates.replace("0.125", "01"), "CNY") } catch (_: Exception) { rejected = true }
        @Expect(rejected, true)
    }

    @TestCase
    func unverifiedQuoteIdentitiesAreNotExposed() {
        if (!exists(".local")) { Directory.create(".local") }
        let state = StateStore(Directory.createTemp(".local").toString())
        let snapshot = RateStore(state, {_ => sampleRates.replace("JPY", "GAU")}).latest("CNY", true)
        @Expect(snapshot["rows"].asArray().size(), 1)
        @Expect(textField(snapshot["rows"].asArray()[0].asObject(), "quote"), "USD")
    }

    @TestCase
    func concurrentRefreshesShareOneRequestWhileCacheReadsStayAvailable() {
        if (!exists(".local")) { Directory.create(".local") }
        let state = StateStore(Directory.createTemp(".local").toString())
        RateStore(state, {_ => sampleRates}).latest("CNY", true)
        let counter = JsonObject(); counter.put("count", JsonInt(0))
        let counterMutex = Mutex()
        let repository = RateStore(state, {_ =>
            synchronized(counterMutex) { counter.put("count", JsonInt(integerField(counter, "count") + 1)) }
            sleep(Duration.millisecond * 400)
            sampleRates
        })
        let first = spawn { repository.latest("CNY", true) }
        let second = spawn { repository.latest("CNY", true) }
        sleep(Duration.millisecond * 40)
        let before = DateTime.nowUTC()
        let cached = repository.latest("CNY", false)
        @Expect(DateTime.nowUTC() - before < Duration.millisecond * 200, true)
        @Expect(cached["rows"].asArray().size(), 2)
        first.get(); second.get()
        @Expect(integerField(counter, "count"), 1)
    }
}
