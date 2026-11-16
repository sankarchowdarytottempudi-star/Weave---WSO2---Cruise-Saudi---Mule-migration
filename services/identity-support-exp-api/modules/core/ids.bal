// Guest id and loyalty id generation (Mule: get:\getGuestId, get:\generateGuestId,
// get:\getLoyaltId, get:\generateLoyaltId in identity-support-exp-api-interface.xml).

const string CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

# A 26-character ULID: 10 characters for the time in milliseconds, 16 random characters.
#
# + epochMillis - Time of creation, milliseconds since 1970
# + randomParts - 16 random numbers, each 0..31
# + return - The ULID
public isolated function ulidOf(int epochMillis, int[] randomParts) returns string {
    string out = "";
    int i = 9;
    while i >= 0 {
        int index = (epochMillis >> (5 * i)) & 31;
        out += CROCKFORD.substring(index, index + 1);
        i -= 1;
    }
    foreach int n in 0 ..< 16 {
        int index = n < randomParts.length() ? randomParts[n] & 31 : 0;
        out += CROCKFORD.substring(index, index + 1);
    }
    return out;
}

# The check digit of a loyalty number. Mule: the digits are reversed, every digit at an odd place
# of the reversed list is doubled (minus 9 when above 9), and the digit that brings the sum to a
# multiple of ten is the check digit.
#
# + digits - The number without its check digit
# + return - The check digit, 0..9
public isolated function checkDigitOf(string digits) returns int {
    int sum = 0;
    int length = digits.length();
    foreach int place in 0 ..< length {
        int|error digit = int:fromString(digits.substring(length - 1 - place, length - place));
        int value = digit is int ? digit : 0;
        if place % 2 == 1 {
            value = value * 2;
            if value > 9 {
                value -= 9;
            }
        }
        sum += value;
    }
    return (10 - (sum % 10)) % 10;
}

# A 10-digit loyalty id: "12", seven digits, check digit.
#
# + serial - The seven-digit part as a number, 0..9999999
# + return - The loyalty id
public isolated function loyaltyIdOf(int serial) returns string {
    string base = "12" + (serial % 10000000).toString().padZero(7);
    return base + checkDigitOf(base).toString();
}
