package yuebao

import std.unittest.*
import std.unittest.testmacro.*
import std.fs.*
import stdx.encoding.json.*

@Test
class HistoryTests {
    @TestCase
    func sortsDeduplicatesAndPreservesGaps() {
        let raw = #"[{"date":"2026-10-26","base":"CNY","quote":"USD","rate":0.125},{"date":"2026-10-23","base":"CNY","quote":"USD","rate":0.124},{"date":"2026-10-26","base":"CNY","quote":"USD","rate":0.125}]"#
        let points = normalizeHistory(raw, "CNY", "USD", "2026-10-20", "2026-10-27")
        @Expect(points.size(), 2)
        @Expect(textField(points[0].asObject(), "date"), "2026-10-23")
        @Expect(textField(points[1].asObject(), "date"), "2026-10-26")
    }

    @TestCase
    func emptyAndSingleAreNotInvented() {
        @Expect(normalizeHistory("[]", "CNY", "USD", "2026-10-20", "2026-10-27").size(), 0)
        let raw = #"[{"date":"2026-10-26","base":"CNY","quote":"USD","rate":0.125}]"#
        @Expect(normalizeHistory(raw, "CNY", "USD", "2026-10-20", "2026-10-27").size(), 1)
    }

    @TestCase
    func rejectsWrongPairRangeAndConflictingDates() {
        let raw = #"[{"date":"2026-10-26","base":"CNY","quote":"USD","rate":0.125}]"#
        for (body in [raw.replace("USD", "EUR"), raw.replace("2026-10-26", "2026-09-01"),
            raw.replace("}]", "},{\"date\":\"2026-10-26\",\"base\":\"CNY\",\"quote\":\"USD\",\"rate\":0.2}]")]) {
            var rejected = false
            try { normalizeHistory(body, "CNY", "USD", "2026-10-20", "2026-10-27") } catch (_: Exception) { rejected = true }
            @Expect(rejected, true)
        }
    }

    @TestCase
    func nextDayOfflineUsesOnlyOverlappingObservedPoints() {
        if (!exists(".local")) { Directory.create(".local") }
        let state = StateStore(Directory.createTemp(".local").toString())
        let raw = #"[{"date":"2026-10-26","base":"CNY","quote":"USD","rate":0.125}]"#
        RateStore(state, {_ => raw}).historyRange("CNY", "USD", "2026-10-20", "2026-10-26", true)
        let restored = RateStore(state, {_ => throw Exception("OFFLINE")}).historyRange("CNY", "USD", "2026-10-21", "2026-10-27", true)
        @Expect(restored["rows"].asArray().size(), 1)
        @Expect(textField(restored["rows"].asArray()[0].asObject(), "date"), "2026-10-26")
        @Expect(restored["cached"].asBool().getValue(), true)
        @Expect(restored["complete"].asBool().getValue(), false)
        @Expect(textField(restored, "error").isEmpty(), false)
    }

    @TestCase
    func overlappingCachesPreferTheMostRecentlyFetchedObservation() {
        if (!exists(".local")) { Directory.create(".local") }
        let state = StateStore(Directory.createTemp(".local").toString())
        let old = #"[{"date":"2026-10-26","base":"CNY","quote":"USD","rate":0.125}]"#
        RateStore(state, {_ => old}).historyRange("CNY", "USD", "2026-10-20", "2026-10-26", true)
        RateStore(state, {_ => old.replace("0.125", "0.126")}).historyRange("CNY", "USD", "2026-10-21", "2026-10-26", true)
        let result = RateStore(state, {_ => throw Exception("OFFLINE")}).historyRange("CNY", "USD", "2026-10-22", "2026-10-27", true)
        @Expect(result["rows"].asArray().size(), 1)
        @Expect(textField(result["rows"].asArray()[0].asObject(), "rate"), "0.126")
    }
}
