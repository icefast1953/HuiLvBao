package yuebao

import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import stdx.encoding.json.*

@Test
class ServiceTests {
    @TestCase
    func localOriginOnly() {
        @Expect(localRequestAllowed("127.0.0.1:18627", "http://127.0.0.1:18627"), true)
        @Expect(localRequestAllowed("127.0.0.1:18627", "http://evil.example"), false)
        @Expect(localRequestAllowed("evil.example:18627", ""), false)
        @Expect(localRequestAllowed("127.0.0.1:18627", "null"), false)
    }

    @TestCase
    func convertsDirectQuotesAndNeverInventsMissingRates() {
        if (!exists(".local")) { Directory.create(".local") }
        let state = StateStore(Directory.createTemp(".local").toString())
        let snapshot = JsonObject()
        snapshot.put("rows", parseRateRows(sampleRates, "CNY"))
        snapshot.put("fetchedAt", JsonString("test")); snapshot.put("cached", JsonBool(true)); snapshot.put("error", JsonString(""))
        let result = conversionResult(state, snapshot, "CNY", "100", false)
        let rows = result["rows"].asArray()
        @Expect(textField(rows[1].asObject(), "amount"), "12.50")
        @Expect(rows[2].asObject()["amount"].toJsonString(), "null")
        @Expect(textField(conversionResult(state, snapshot, "CNY", "1", false)["rows"].asArray()[1].asObject(), "amount"), "0.13")
    }
}
