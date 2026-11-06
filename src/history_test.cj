package yuebao

import std.unittest.*
import std.unittest.testmacro.*

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
}
