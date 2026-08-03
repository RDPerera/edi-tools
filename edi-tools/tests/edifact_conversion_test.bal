import ballerina/file;
import ballerina/test;
import editools.edifact;
import ballerina/io;
import ballerina/log;

// Path to a locally downloaded UNECE D03A directory (the archive from
// https://unece.org/trade/uncefact/unedifact/download, extracted). The
// directory files are not checked in, so the D03A tests below run only when a
// path is supplied:
//   bal test -- -Cd03aDirectoryPath=<path>
configurable string d03aDirectoryPath = "";

const string LOCAL_DIRECTORY = "tests/resources/edifact/local/directory";

@test:Config {
    dataProvider: filesProvider,
    after: afterFunc
}
function testEdifactConversion(string msgType, string expected, string actual) returns error? {
    if d03aDirectoryPath == "" {
        log:printWarn("Skipping D03A conversion test: no directory path supplied. " +
                "Pass -Cd03aDirectoryPath=<path to an extracted D03A directory> to run it.");
        return;
    }
    check edifact:convertEdifactToEdi("d03a", "tests/resources/edifact/d03a", msgType, d03aDirectoryPath);

    json expectedJson = check io:fileReadJson(expected);
    json actualJson = check io:fileReadJson(actual);
    test:assertEquals(actualJson, expectedJson, "Edifact conversion failed");
}

function afterFunc() returns error? {
    if d03aDirectoryPath == "" {
        return;
    }
    // check file:remove("tests/resources/edifact/d03a/INVOIC.json");
    check file:remove("tests/resources/edifact/d03a/ORDERS.json");
}

function filesProvider() returns string[][] {
    return [
        // This is disble until the int and float are identified seperately.
        // ["INVOIC", "tests/resources/edifact/d03a/INVOIC_expected.json", "tests/resources/edifact/d03a/INVOIC.json"],
        ["ORDERS", "tests/resources/edifact/d03a/ORDERS_expected.json", "tests/resources/edifact/d03a/ORDERS.json"]
    ];
}

// Converts from a directory laid out like a UNECE release: a message
// specification in `EDMD` and the segment directory in `EDSD`. The fixture is a
// hand written sample, so this runs without any download.
@test:Config {}
function testEdifactConversionFromLocalDirectory() returns error? {
    check edifact:convertEdifactToEdi("d03a", "tests/resources/edifact/local", "TESTMSG", LOCAL_DIRECTORY);

    json expectedJson = check io:fileReadJson("tests/resources/edifact/local/TESTMSG_expected.json");
    json actualJson = check io:fileReadJson("tests/resources/edifact/local/TESTMSG.json");
    test:assertEquals(actualJson, expectedJson, "Edifact conversion from a local directory failed");
    check file:remove("tests/resources/edifact/local/TESTMSG.json");
}

// A field whose name wraps onto a second line in the source specification must
// still appear in the segment definition.
@test:Config {}
function testFieldWithWrappedName() returns error? {
    check edifact:convertEdifactToEdi("d03a", "tests/resources/edifact/local", "TESTMSG", LOCAL_DIRECTORY);

    json schema = check io:fileReadJson("tests/resources/edifact/local/TESTMSG.json");
    json tax = check schema.segmentDefinitions.TAX;
    json[] fields = <json[]>check tax.fields;
    boolean found = false;
    foreach json 'field in fields {
        if (check 'field.tag) == "DUTY_OR_TAX_OR_FEE_ASSESSMENT_BASIS_QUANTITY" {
            found = true;
        }
    }
    test:assertTrue(found,
            "Field with a name wrapped across two lines is missing from the segment definition");
    check file:remove("tests/resources/edifact/local/TESTMSG.json");
}

// Message types that are not in the given directory must be reported, rather
// than silently producing nothing.
@test:Config {}
function testMissingMessageTypeInLocalDirectory() returns error? {
    error? result = edifact:convertEdifactToEdi("d03a", "tests/resources/edifact/local", "ABSENT", LOCAL_DIRECTORY);
    test:assertTrue(result is error, "Expected an error for a message type absent from the directory");
    if result is error {
        test:assertTrue(result.message().includes("ABSENT_D.03A"), "Unexpected error: " + result.message());
    }
}
