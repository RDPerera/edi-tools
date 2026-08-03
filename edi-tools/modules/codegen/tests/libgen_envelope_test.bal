// Copyright (c) 2026 WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/file;
import ballerina/io;
import ballerina/os;
import ballerina/test;

// A schema without an `envelope`, so the generated library mixes enveloped and
// plain EDI types — the plain one must stay out of the envelope dispatch maps.
final readonly & json plainSchemaJson = {
    "name": "Simple",
    "tag": "Simple",
    "delimiters": {
        "segment": "'",
        "field": "+",
        "component": ":",
        "subcomponent": "NOT_USED",
        "repetition": "NOT_USED"
    },
    "segments": [
        {
            "code": "BGM",
            "tag": "BeginningOfMessage",
            "minOccurances": 1,
            "maxOccurances": 1,
            "fields": [
                {"tag": "code"},
                {"tag": "documentNumber"}
            ]
        }
    ]
};

// Generates a library from ORDERS (enveloped) + SIMPLE (plain) and returns the
// library root. Both schemas are written to a temp folder so `generateLibrary`
// walks them the same way the CLI does.
function generateMixedLibrary(string libName) returns [string, string]|error {
    string tmp = check file:createTempDir();
    string schemaPath = check file:joinPath(tmp, "schemas");
    check file:createDir(schemaPath, file:RECURSIVE);
    check io:fileWriteJson(check file:joinPath(schemaPath, "ORDERS.json"), envelopeSchemaJson);
    check io:fileWriteJson(check file:joinPath(schemaPath, "SIMPLE.json"), plainSchemaJson);

    string outputPath = check file:joinPath(tmp, "out");
    check file:createDir(outputPath, file:RECURSIVE);

    LibData libdata = {
        orgName: "wso2test",
        libName: libName,
        outputPath: outputPath,
        schemaPath: schemaPath,
        versioned: false
    };
    check generateLibrary(libdata);
    return [tmp, check file:joinPath(outputPath, libName)];
}

@test:Config {}
function testLibgenDefaultModuleEnvelopeFns() returns error? {
    [string, string] [tmp, libPath] = check generateMixedLibrary("mixedlib");
    string mainModule = check io:fileReadString(check file:joinPath(libPath, "mixedlib.bal"));

    // The envelope-aware counterparts of the plain name-dispatched facade.
    test:assertTrue(mainModule.includes(
                    "public isolated function headersFromEdiString(string ediText, EDI_NAME ediName)"),
            "Default module should dispatch headersFromEdiString by EDI name");
    test:assertTrue(mainModule.includes(
                    "public isolated function interchangeFromEdiString(string ediText, EDI_NAME ediName)"),
            "Default module should dispatch interchangeFromEdiString by EDI name");
    test:assertTrue(mainModule.includes(
                    "public isolated function interchangeToEdiString(any msg, EDI_NAME ediName)"),
            "Default module should dispatch interchangeToEdiString by EDI name");
    test:assertTrue(mainModule.includes("public isolated function hasEnvelope(EDI_NAME ediName)"),
            "Default module should expose hasEnvelope so callers can test before dispatching");

    // Only the enveloped schema is registered — SIMPLE has no envelope functions
    // to point at, so registering it would not compile.
    test:assertTrue(mainModule.includes("\"ORDERS\": mORDERS:transformInterchangeFromEdiString"),
            "ORDERS declares an envelope and must be registered");
    test:assertFalse(mainModule.includes("mSIMPLE:transformInterchangeFromEdiString"),
            "SIMPLE has no envelope and must not be registered");
    test:assertFalse(mainModule.includes("mSIMPLE:transformHeadersFromEdiString"),
            "SIMPLE has no envelope and must not be registered");

    // The transformer of an enveloped module exports the envelope entry points;
    // the plain one does not.
    string ordersTransformer = check io:fileReadString(
            check file:joinPath(libPath, "modules", "mORDERS", "transformer.bal"));
    test:assertTrue(ordersTransformer.includes("public isolated function transformInterchangeFromEdiString"),
            "Enveloped module transformer should export transformInterchangeFromEdiString");
    string simpleTransformer = check io:fileReadString(
            check file:joinPath(libPath, "modules", "mSIMPLE", "transformer.bal"));
    test:assertFalse(simpleTransformer.includes("transformInterchangeFromEdiString"),
            "Plain module transformer must not export envelope functions");

    check file:remove(tmp, file:RECURSIVE);
}

@test:Config {}
function testLibgenWithoutEnvelopeOmitsEnvelopeFns() returns error? {
    string tmp = check file:createTempDir();
    string schemaPath = check file:joinPath(tmp, "schemas");
    check file:createDir(schemaPath, file:RECURSIVE);
    check io:fileWriteJson(check file:joinPath(schemaPath, "SIMPLE.json"), plainSchemaJson);
    string outputPath = check file:joinPath(tmp, "out");
    check file:createDir(outputPath, file:RECURSIVE);

    LibData libdata = {
        orgName: "wso2test",
        libName: "plainlib",
        outputPath: outputPath,
        schemaPath: schemaPath,
        versioned: false
    };
    check generateLibrary(libdata);

    string mainModule = check io:fileReadString(
            check file:joinPath(outputPath, "plainlib", "plainlib.bal"));
    test:assertFalse(mainModule.includes("interchangeFromEdiString"),
            "A library with no enveloped schema should not emit envelope dispatchers");
    test:assertFalse(mainModule.includes("EdiInterchangeDeserialize"),
            "A library with no enveloped schema should not emit envelope function types");
    // The plain facade is untouched.
    test:assertTrue(mainModule.includes("public isolated function fromEdiString(string ediText, EDI_NAME ediName)"),
            "The plain facade must still be generated");

    check file:remove(tmp, file:RECURSIVE);
}

// Compiles the generated library and round-trips an interchange through the
// default module's name-dispatched envelope functions. This is the only check
// that exercises `transformInterchangeToEdiString`'s `ensureType` narrowing,
// which no amount of source inspection can confirm.
@test:Config {}
function testLibgenEnvelopeFacadeRoundTrip() returns error? {
    [string, string] [tmp, libPath] = check generateMixedLibrary("rtlib");

    // The REST connector opens an http:Listener at module init, which would bind
    // a port for the duration of `bal test`. It is unrelated to the facade under
    // test, so drop it.
    check file:remove(check file:joinPath(libPath, "rest_connector.bal"));

    string testDir = check file:joinPath(libPath, "tests");
    check file:createDir(testDir, file:RECURSIVE);
    check io:fileWriteString(check file:joinPath(testDir, "facade_test.bal"), string `
import ballerina/test;
import rtlib.mORDERS;

final string ediText = "UNB+REF001'UNH+MSG001'BGM+ORDER123'UNT+MSG001'UNZ+REF001'";

@test:Config {}
function testEnvelopeDispatch() returns error? {
    test:assertTrue(hasEnvelope(EDI_ORDERS), "ORDERS declares an envelope");
    test:assertFalse(hasEnvelope(EDI_SIMPLE), "SIMPLE declares no envelope");

    // Headers come back as the submodule's typed record, boxed as anydata.
    anydata rawHeaders = check headersFromEdiString(ediText, EDI_ORDERS);
    mORDERS:EDI_ORDERS_OrdersHeaders headers = check rawHeaders.ensureType();
    test:assertEquals(headers.interchange?.interchange_header?.controlReference, "REF001");
    test:assertEquals(headers.'transaction?.message_header?.messageReferenceNumber, "MSG001");

    // Full interchange, then write it straight back out through the facade.
    any rawInterchange = check interchangeFromEdiString(ediText, EDI_ORDERS);
    mORDERS:EDI_ORDERS_OrdersInterchange interchange = check rawInterchange.ensureType();
    test:assertEquals(interchange.transactions.length(), 1);
    test:assertEquals(interchange.interchangeHeader?.interchange_header?.controlReference, "REF001");
    mORDERS:EDI_ORDERS_Orders body = check interchange.transactions[0].body;
    test:assertEquals(body.BeginningOfMessage?.documentNumber, "ORDER123");

    // Write the interchange back out and re-read it. Comparing against the input
    // text would not work — the runtime recomputes the envelope trailer counts
    // and separates segments with newlines — so the check is structural.
    string ediOut = check interchangeToEdiString(rawInterchange, EDI_ORDERS);
    mORDERS:EDI_ORDERS_OrdersInterchange reparsed =
        check (check interchangeFromEdiString(ediOut, EDI_ORDERS)).ensureType();
    test:assertEquals(reparsed.interchangeHeader?.interchange_header?.controlReference, "REF001");
    mORDERS:EDI_ORDERS_Orders reparsedBody = check reparsed.transactions[0].body;
    test:assertEquals(reparsedBody.BeginningOfMessage?.documentNumber, "ORDER123");

    // A type without an envelope is rejected rather than silently mishandled.
    any|error noEnvelope = interchangeFromEdiString(ediText, EDI_SIMPLE);
    test:assertTrue(noEnvelope is error, "SIMPLE must not resolve an envelope deserializer");
}
`);

    string balCommand = "bal";
    string distBin = os:getEnv("BALLERINA_DIST_BIN");
    if distBin != "" {
        balCommand = check file:joinPath(distBin, "bal");
    }
    os:Process proc = check os:exec({value: balCommand, arguments: ["test", libPath]});
    int exitCode = check proc.waitForExit();

    // Ballerina has no try/finally and test:assertFail aborts the function, so
    // the failure message is captured first and the temp dir cleaned up before
    // the assertion runs.
    string? failure = ();
    if exitCode != 0 {
        string stdoutText = check string:fromBytes(check proc.output(io:stdout));
        string stderrText = check string:fromBytes(check proc.output(io:stderr));
        failure = string `Generated library facade test failed (bal test exit ${exitCode}).
stdout:
${stdoutText}
stderr:
${stderrText}`;
    }

    check file:remove(tmp, file:RECURSIVE);

    if failure is string {
        test:assertFail(failure);
    }
}
