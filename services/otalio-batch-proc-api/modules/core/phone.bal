import ballerina/jballerina.java;

// Phone numbers are split into country code and national number with the same library the old
// application used (libphonenumber), following its helper class step by step.

# A phone number split into its parts.
#
# + valid - true when the number could be read and is a possible number
# + countryCode - Country calling code without "+", "" when not valid
# + number - National number, "" when not valid
public type PhoneParts record {|
    boolean valid;
    string countryCode = "";
    string number = "";
|};

# Splits a phone number the way the old helper did.
#
# Only numbers written with a leading "+" and country code can be read (no default country is
# given). The national number is taken from the digits as typed, so a leading 0 is kept.
#
# + phone - The number as stored, () for none
# + return - The parts; not valid when it cannot be read
public isolated function splitPhone(string? phone) returns PhoneParts {
    if phone is () {
        return {valid: false};
    }
    PhoneParts|error parts = trap parsed(phone);
    return parts is error ? {valid: false} : parts;
}

isolated function parsed(string phone) returns PhoneParts|error {
    handle util = phoneUtil();
    handle parsedNumber = check parseNumber(util, java:fromString(phone), java:createNull());
    if !possibleNumber(util, parsedNumber) {
        return {valid: false};
    }
    string code = countryCodeOf(parsedNumber).toString();
    string number = nationalNumberOf(parsedNumber).toString();
    if phone.startsWith("+") {
        string digits = re `\D`.replaceAll(phone, "");
        if digits.startsWith(code) {
            number = digits.substring(code.length());
        }
    }
    return {valid: true, countryCode: code, number};
}

isolated function phoneUtil() returns handle = @java:Method {
    name: "getInstance",
    'class: "com.google.i18n.phonenumbers.PhoneNumberUtil"
} external;

isolated function parseNumber(handle util, handle phone, handle region) returns handle|error = @java:Method {
    name: "parse",
    'class: "com.google.i18n.phonenumbers.PhoneNumberUtil",
    paramTypes: ["java.lang.CharSequence", "java.lang.String"]
} external;

isolated function possibleNumber(handle util, handle parsedNumber) returns boolean = @java:Method {
    name: "isPossibleNumber",
    'class: "com.google.i18n.phonenumbers.PhoneNumberUtil",
    paramTypes: ["com.google.i18n.phonenumbers.Phonenumber$PhoneNumber"]
} external;

isolated function countryCodeOf(handle parsedNumber) returns int = @java:Method {
    name: "getCountryCode",
    'class: "com.google.i18n.phonenumbers.Phonenumber$PhoneNumber"
} external;

isolated function nationalNumberOf(handle parsedNumber) returns int = @java:Method {
    name: "getNationalNumber",
    'class: "com.google.i18n.phonenumbers.Phonenumber$PhoneNumber"
} external;
