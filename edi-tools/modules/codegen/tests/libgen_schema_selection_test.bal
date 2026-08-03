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
import ballerina/test;

// Sets up a schema folder and an output folder under a fresh temp directory.
function prepareLibgenDirs() returns [string, string]|error {
    string tmp = check file:createTempDir();
    string schemaPath = check file:joinPath(tmp, "schemas");
    check file:createDir(schemaPath, file:RECURSIVE);
    string outputPath = check file:joinPath(tmp, "out");
    check file:createDir(outputPath, file:RECURSIVE);
    return [schemaPath, outputPath];
}

function runLibgen(string schemaPath, string outputPath, string libName) returns error? {
    LibData libdata = {
        orgName: "testorg",
        libName: libName,
        schemaPath: schemaPath,
        outputPath: outputPath,
        versioned: false
    };
    return generateLibrary(libdata);
}

@test:Config {}
function testNonJsonFilesAreSkipped() returns error? {
    [string, string] [schemaPath, outputPath] = check prepareLibgenDirs();
    check io:fileWriteJson(check file:joinPath(schemaPath, "SIMPLE.json"), plainSchemaJson);
    // The kind of stray file a Windows download leaves behind next to the schemas.
    check io:fileWriteString(check file:joinPath(schemaPath, "SIMPLE.json:Zone.Identifier"),
            "[ZoneTransfer]\nZoneId=3\n");
    check io:fileWriteString(check file:joinPath(schemaPath, "notes.txt"), "not a schema");
    check file:createDir(check file:joinPath(schemaPath, "nested"), file:RECURSIVE);

    check runLibgen(schemaPath, outputPath, "skiplib");

    string libPath = check file:joinPath(outputPath, "skiplib");
    test:assertTrue(check file:test(check file:joinPath(libPath, "Ballerina.toml"), file:EXISTS),
            "A stray file must not stop the package from being generated");
    test:assertTrue(check file:test(check file:joinPath(libPath, "modules", "mSIMPLE"), file:EXISTS),
            "The valid schema should still produce its module");
}

@test:Config {}
function testUnparseableJsonSchemaFailsAndRemovesPackage() returns error? {
    [string, string] [schemaPath, outputPath] = check prepareLibgenDirs();
    check io:fileWriteJson(check file:joinPath(schemaPath, "SIMPLE.json"), plainSchemaJson);
    // A '.json' file is an intended schema, so a broken one must fail the run.
    check io:fileWriteString(check file:joinPath(schemaPath, "BROKEN.json"), "[ZoneTransfer]\nZoneId=3\n");

    error? result = runLibgen(schemaPath, outputPath, "brokenlib");
    test:assertTrue(result is error, "An unparseable '.json' schema must fail the run");
    if result is error {
        test:assertTrue(result.message().includes("BROKEN.json"),
                "The failure should name the offending schema: " + result.message());
    }
    test:assertFalse(check file:test(check file:joinPath(outputPath, "brokenlib"), file:EXISTS),
            "The incomplete package must be removed");
}

@test:Config {}
function testNoSchemasFailsAndRemovesPackage() returns error? {
    [string, string] [schemaPath, outputPath] = check prepareLibgenDirs();
    check io:fileWriteString(check file:joinPath(schemaPath, "readme.md"), "no schemas here");

    error? result = runLibgen(schemaPath, outputPath, "emptylib");
    test:assertTrue(result is error, "A folder with no '.json' schemas must fail the run");
    if result is error {
        test:assertTrue(result.message().includes("No EDI schemas were found"),
                "Unexpected failure message: " + result.message());
    }
    test:assertFalse(check file:test(check file:joinPath(outputPath, "emptylib"), file:EXISTS),
            "No package directory should be left behind");
}

@test:Config {}
function testOutputDirectoryIsNotRemovedOnFailure() returns error? {
    [string, string] [schemaPath, outputPath] = check prepareLibgenDirs();
    // Cleanup must remove only the generated package, never the output folder around it.
    string sibling = check file:joinPath(outputPath, "keep.txt");
    check io:fileWriteString(sibling, "unrelated content");

    error? result = runLibgen(schemaPath, outputPath, "gonelib");
    test:assertTrue(result is error, "An empty schema folder must fail the run");
    test:assertTrue(check file:test(outputPath, file:EXISTS), "The output directory must survive");
    test:assertTrue(check file:test(sibling, file:EXISTS), "Unrelated output content must survive");
}
