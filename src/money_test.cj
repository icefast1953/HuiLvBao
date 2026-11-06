package yuebao

import std.unittest.*
import std.unittest.testmacro.*

@Test
class MoneyTests {
    @TestCase
    func cnySample() {
        @Expect(convertAmount("100", "0.125", 2), "12.50")
        @Expect(convertAmount("100", "0.1", 2), "10.00")
        @Expect(convertAmount("100", "0.1125", 2), "11.25")
        @Expect(convertAmount("100", "0.975", 2), "97.50")
    }

    @TestCase
    func displayHalfUpAndZeroDecimals() {
        @Expect(convertAmount("1", "1.005", 2), "1.01")
        @Expect(convertAmount("1", "150.5", 0), "151")
        @Expect(convertAmount("0", "100", 2), "0.00")
    }

    @TestCase
    func maximumInputStaysExact() {
        @Expect(convertAmount("999999999999999999.999999", "1", 6), "999999999999999999.999999")
        @Expect(convertAmount("0.000001", "0.5", 6), "0.000001")
        @Expect(convertAmount(".5", "2", 2), "1.00")
        @Expect(convertAmount("1.", "2", 2), "2.00")
    }

    @TestCase
    func editableAndInvalidInputs() {
        @Expect(validAmount(""), false)
        @Expect(validAmount("."), false)
        @Expect(validAmount("1."), true)
        @Expect(validAmount(".5"), true)
        for (text in ["-1", "1e2", "1,2", "1.2.3", "1000000000000000000", "0.1234567", " 1", "NaN"]) {
            @Expect(validAmount(text), false)
        }
    }
}
