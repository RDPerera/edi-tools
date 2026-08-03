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

// Reads EDIFACT schemas from a locally downloaded UNECE UNTDID directory.
//
// `service.unece.org` is behind a bot challenge and no longer serves the
// directory pages to non-browser clients, so the directory has to be supplied
// as a local input. UNECE publishes each release as one archive per version
// (https://unece.org/trade/uncefact/unedifact/download) containing the
// fixed-format batch files this module reads:
//
//   EDMD/<TYPE>_D.<REL>  one file per message type, holding the segment table
//   EDSD/EDSD.<REL>      standard segments directory, with composite components
//                        listed inline under their field
//
// The segment table in `EDMD` uses the same layout as the HTML pages, so the
// schema built here is identical to the one produced by the fetching path.

import ballerina/file;
import ballerina/io;
import ballerina/lang.regexp;
import ballerina/log;

// A message-table row: `0010   UNH Message header                            M   1     `
// or a segment group opener embedded in the same table.
final regexp:RegExp untdidTableRowReg = re `(\d{4})\s+([A-Z]{3})\s+(.+?)\s+([CM])\s+(\d+)([ \-\+\|]*)|Segment group (\d+)\s+------------------\s+([CM])\s+(\d+)(-+\+*\|*)`;

// An EDSD segment header: `       NAD  NAME AND ADDRESS`
final regexp:RegExp edsdSegmentHeaderReg = re `\s+([A-Z]{3})\s\s+([A-Z0-9].*?)\s*`;

// An EDSD field row: `010    3035 PARTY FUNCTION CODE QUALIFIER              M    1 an..3`
// The trailing representation is empty when the field is a composite.
final regexp:RegExp edsdFieldReg = re `(\d{3})\s+([A-Z0-9]{4})\s+(.+?)\s+([CM])\s+(\d+)\s*(.*?)\s*`;

// An EDSD component row, listed under its composite field:
// `       3039  Party identifier                          M      an..35`
final regexp:RegExp edsdComponentReg = re `\s+([A-Z0-9]{4})\s\s+(.+?)\s+([CM])\s+([an]+\.?\.?\d*)\s*`;

// Start-of-row markers, used to fold names that wrap onto a second line.
final regexp:RegExp edsdFieldStartReg = re `\d{3}\s+[A-Z0-9]{4}\s.*`;
final regexp:RegExp edsdComponentStartReg = re `\s{5,}[A-Z0-9]{4}\s\s.*`;

// Block separator used throughout the UNTDID batch files.
final regexp:RegExp untdidSeparatorReg = re `-{20,}`;

// Resolved paths of the batch files needed for one conversion.
type UntdidDirectory record {|
    // Absolute path of the EDSD standard segments directory file
    string segmentDirectoryPath;
    // Message type code to the absolute path of its EDMD file
    map<string> messageFiles;
|};

// Converts message types from a locally downloaded UNTDID directory.
function convertLocalEdifactToEdi(string version, string dir, string? messageType, string inputPath)
        returns error? {
    UntdidDirectory directory = check locateUntdidFiles(version, inputPath, messageType);
    map<string> segmentBlocks = check readSegmentDirectory(directory.segmentDirectoryPath);

    SegmentDefintions allSegmentDefinitions = {};
    foreach [string, string] [code, messageFile] in directory.messageFiles.entries() {
        check genEdiSchemaFromFile(messageFile, code, dir, allSegmentDefinitions, segmentBlocks);
    }
}

function genEdiSchemaFromFile(string messageFile, string code, string dir,
        SegmentDefintions allSegmentDefinitions, map<string> segmentBlocks) returns error? {
    log:printInfo("Generating EDI schema for " + code);
    string messageSpec = check io:fileReadString(messageFile);
    EDISchema ediSchema = check genMsgTypeEdiSchema(messageSpec, allSegmentDefinitions, code,
            untdidTableRowReg, scanUntdidTableRow, localSegmentDefResolver(segmentBlocks));
    string dirPath = dir;
    if dir[dir.length() - 1] != "/" {
        dirPath = dir + "/";
    }
    check io:fileWriteJson(check file:joinPath(dirPath, code + ".json"), ediSchema);
}

// Reads one row of an EDMD segment table. Group rows carry no segment code, so
// the compacted match groups start at the group number.
function scanUntdidTableRow(regexp:Groups row) returns TableRow|error {
    if segmentGroupReg.isFullMatch(row[0].substring()) {
        return scanGroupRow(row);
    }
    regexp:Span? codeMatch = row[2];
    regexp:Span? nameMatch = row[3];
    regexp:Span? statusMatch = row[4];
    regexp:Span? occuranceMatch = row[5];
    regexp:Span? restMatch = row[6];
    if codeMatch is () || nameMatch is () || statusMatch is () || occuranceMatch is () || restMatch is () {
        return error("Invalid segment found in the message segment table");
    }
    return {
        ref: codeMatch.substring(),
        name: nameMatch.substring().trim(),
        status: statusMatch.substring(),
        maxOccurances: check int:fromString(occuranceMatch.substring()),
        rest: restMatch.substring()
    };
}

// Builds segment definitions from the EDSD blocks instead of fetching a page
// per segment. Predefined service segments keep taking precedence, as in the
// fetching path.
function localSegmentDefResolver(map<string> segmentBlocks) returns SegmentDefResolver {
    return function(TableRow row, string code, string tag) returns SegmentDef?|error {
        string? block = segmentBlocks[code];
        if block is () {
            log:printDebug("Segment " + code + " not found in the segment directory");
            return ();
        }
        return getSegmentDefFromBlock(block, code, tag);
    };
}

// Splits the EDSD file into one text block per segment, keyed by segment code.
function readSegmentDirectory(string path) returns map<string>|error {
    string content = check io:fileReadString(path);
    map<string> blocks = {};
    foreach string block in untdidSeparatorReg.split(content) {
        string[] lines = splitLines(block);
        foreach string line in lines {
            if line.trim() == "" {
                continue;
            }
            if !edsdSegmentHeaderReg.isFullMatch(line) {
                // Text before the first segment header (change indicators, notes).
                break;
            }
            regexp:Groups? header = edsdSegmentHeaderReg.fullMatchGroups(line);
            if header is () {
                break;
            }
            regexp:Span? codeMatch = header[1];
            if codeMatch is () {
                break;
            }
            blocks[codeMatch.substring()] = block;
            break;
        }
    }
    if blocks.length() == 0 {
        return error("No segment definitions found in " + path +
                ". Expected the EDSD standard segments directory file.");
    }
    return blocks;
}

// Builds a segment definition from its EDSD block. Composite components are
// listed inline under their field, so no further lookup is needed.
function getSegmentDefFromBlock(string block, string code, string tag) returns SegmentDef|error {
    FieldDef[] fields = [{tag: "code", required: true}];
    string[] fieldNames = [];
    string[] componentNames = [];
    foreach string row in foldSegmentRows(block) {
        if edsdFieldReg.isFullMatch(row) {
            regexp:Groups? groups = edsdFieldReg.fullMatchGroups(row);
            if groups is () {
                return error("Invalid field found in segment " + code);
            }
            fields.push(check getFieldFromRow(groups, fieldNames));
            componentNames = [];
        } else if edsdComponentReg.isFullMatch(row) {
            regexp:Groups? groups = edsdComponentReg.fullMatchGroups(row);
            if groups is () {
                return error("Invalid component found in segment " + code);
            }
            if fields.length() == 1 {
                return error("Component found before any field in segment " + code);
            }
            FieldDef lastField = fields[fields.length() - 1];
            ComponentDef[] components = lastField.components ?: [];
            components.push(check getComponentFromRow(groups, componentNames));
            lastField.components = components;
        }
    }
    return {code, tag, fields};
}

function getFieldFromRow(regexp:Groups groups, string[] fieldNames) returns FieldDef|error {
    regexp:Span? nameMatch = groups[3];
    regexp:Span? occuranceMatch = groups[5];
    regexp:Span? reprMatch = groups[6];
    if nameMatch is () || occuranceMatch is () {
        return error("Invalid field found in the segment directory");
    }
    int occurance = check int:fromString(occuranceMatch.substring());
    string repr = reprMatch is () ? "" : reprMatch.substring().trim();
    return {
        tag: getFieldNames(fieldNames, getTag(nameMatch.substring().trim())),
        // A field with no representation is a composite; its components follow.
        dataType: repr == "" ? "composite" : getType(repr),
        repeat: occurance > 1,
        components: []
    };
}

function getComponentFromRow(regexp:Groups groups, string[] componentNames) returns ComponentDef|error {
    regexp:Span? nameMatch = groups[2];
    regexp:Span? statusMatch = groups[3];
    regexp:Span? reprMatch = groups[4];
    if nameMatch is () || statusMatch is () || reprMatch is () {
        return error("Invalid component found in the segment directory");
    }
    return {
        tag: getComponentName(componentNames, getTag(nameMatch.substring().trim())),
        required: statusMatch.substring() == "M",
        dataType: getType(reprMatch.substring().trim())
    };
}

// Element names wrap onto a following line when they are too long for the
// column. Joins each row back into a single line and drops the surrounding
// prose (function descriptions, notes).
function foldSegmentRows(string block) returns string[] {
    string[] rows = [];
    foreach string line in splitLines(block) {
        if line.trim() == "" {
            continue;
        }
        boolean startsRow = edsdFieldStartReg.isFullMatch(line) || edsdComponentStartReg.isFullMatch(line);
        if startsRow {
            rows.push(line);
            continue;
        }
        if rows.length() == 0 {
            continue;
        }
        string current = rows[rows.length() - 1];
        // Only fold into a row that is still incomplete, so trailing notes are
        // not appended to a row that already parsed.
        if edsdFieldReg.isFullMatch(current) || edsdComponentReg.isFullMatch(current) {
            continue;
        }
        rows[rows.length() - 1] = current + " " + line.trim();
    }
    return rows;
}

// Finds the EDSD file and the requested message files inside a directory
// extracted from a UNECE release archive. The layout is not fixed, so files are
// matched by name anywhere under the given path.
function locateUntdidFiles(string version, string inputPath, string? messageType)
        returns UntdidDirectory|error {
    if !check file:test(inputPath, file:IS_DIR) {
        return error("The EDIFACT directory input '" + inputPath + "' is not a directory.");
    }
    // `d03a` names files as `ORDERS_D.03A` and `EDSD.03A`.
    regexp:RegExp versionReg = re `[a-zA-Z]\d{2}[a-zA-Z]`;
    if !versionReg.isFullMatch(version) {
        return error("Invalid EDIFACT version '" + version + "'. Expected a value such as 'd03a'.");
    }
    string release = version.substring(1).toUpperAscii();
    string prefix = version.substring(0, 1).toUpperAscii();
    string segmentFileName = "EDSD." + release;
    string messageSuffix = "_" + prefix + "." + release;

    string? segmentDirectoryPath = ();
    map<string> messageFiles = {};
    foreach string path in check listFilesRecursively(inputPath) {
        string name = check file:basename(path);
        if name.toUpperAscii() == segmentFileName {
            segmentDirectoryPath = path;
            continue;
        }
        if !name.toUpperAscii().endsWith(messageSuffix) {
            continue;
        }
        string code = name.substring(0, name.length() - messageSuffix.length()).toUpperAscii();
        if messageType is () || code == messageType {
            messageFiles[code] = path;
        }
    }

    if segmentDirectoryPath is () {
        return error("Could not find '" + segmentFileName + "' under '" + inputPath +
                "'. Extract the release archive (including the EDSD and EDMD archives inside it) " +
                "and point --input at the extracted directory.");
    }
    if messageFiles.length() == 0 {
        return messageType is ()
            ? error("Could not find any message specification files ('*" + messageSuffix + "') under '" +
                    inputPath + "'.")
            : error("Could not find the message specification file '" + messageType + messageSuffix +
                    "' under '" + inputPath + "'.");
    }
    return {segmentDirectoryPath, messageFiles};
}

function listFilesRecursively(string path) returns string[]|error {
    string[] files = [];
    foreach file:MetaData entry in check file:readDir(path) {
        if entry.dir {
            files.push(...check listFilesRecursively(entry.absPath));
        } else {
            files.push(entry.absPath);
        }
    }
    return files;
}

function splitLines(string content) returns string[] {
    string[] lines = [];
    foreach string line in re `\n`.split(content) {
        lines.push(line.endsWith("\r") ? line.substring(0, line.length() - 1) : line);
    }
    return lines;
}
