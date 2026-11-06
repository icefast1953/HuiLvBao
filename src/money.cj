package yuebao

import std.math.numeric.BigInt

func validDecimal(text: String, maxWhole: Int64, maxFraction: Int64): Bool {
    if (text.isEmpty()) { return false }
    var whole: Int64 = 0
    var fraction: Int64 = 0
    var dot = false
    for (byte in text.toArray()) {
        if (byte == 46 && !dot) {
            dot = true
        } else if (byte >= 48 && byte <= 57) {
            if (dot) { fraction++ } else { whole++ }
        } else { return false }
    }
    return whole + fraction > 0 && whole <= maxWhole && fraction <= maxFraction
}

func validAmount(text: String): Bool { validDecimal(text, 18, 6) }

func decimalParts(text: String): (BigInt, Int64) {
    let parts = text.split(".")
    let digits = text.replace(".", "")
    let scale = if (parts.size == 2) { parts[1].size } else { 0 }
    return (BigInt.parse(digits), scale)
}

func convertAmount(amount: String, rate: String, digits: Int64): String {
    if (!validAmount(amount) || !validDecimal(rate, 40, 30) || digits < 0 || digits > 6) {
        throw IllegalArgumentException("INVALID_AMOUNT_OR_RATE")
    }
    let (input, inputScale) = decimalParts(amount)
    let (quoteValue, quoteScale) = decimalParts(rate)
    if (quoteValue <= BigInt(0)) { throw IllegalArgumentException("INVALID_RATE") }
    var value = input * quoteValue
    let scale = inputScale + quoteScale
    if (scale > digits) {
        let divisor = BigInt(10) ** UInt64(scale - digits)
        let remainder = value % divisor
        value = value / divisor
        if (remainder * BigInt(2) >= divisor) { value = value + BigInt(1) }
    } else {
        value = value * (BigInt(10) ** UInt64(digits - scale))
    }
    var output = value.toString()
    if (digits == 0) { return output }
    while (output.size <= digits) { output = "0" + output }
    return output[..output.size - digits] + "." + output[output.size - digits..]
}
