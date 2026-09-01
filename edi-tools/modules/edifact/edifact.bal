import ballerina/http;
import ballerina/lang.regexp;
import ballerina/log;
import ballerina/io;

type Segement record {|
    string ref;
    string tag;
    int minOccurances?;
    int maxOccurances;
|};

type SegmentGroup record {|
    string tag;
    int minOccurances?;
    int maxOccurances;
    (Segement|SegmentGroup)[] segments;
|};

type SegmentDef record {|
    string code;
    string tag;
    FieldDef[] fields;
|};

type FieldDef record {|
    string tag;
    string dataType?;
    boolean required = false;
    boolean repeat = false;
    ComponentDef[] components?;
|};

type ComponentDef record {|
    string tag;
    boolean required = false;
    string dataType?;
|};

type Delimiters record {|
    string segment = "'";
    string 'field = "+";
    string component = ":";
    string repetition = "^";
    string decimalSeparator = ",";
|};

type SegmentDefintions map<SegmentDef>;

// One row of a message segment table, extracted from either the HTML pages or
// the UNTDID batch files. Keeps the segment group nesting logic independent of
// the input format.
type TableRow record {|
    // Group number when the row opens a segment group, nil for a segment row
    string? groupNumber = ();
    // Segment code, nil for a segment group row
    string? ref = ();
    // Segment name as it appears in the table
    string name = "";
    // Location of the segment page, relative to the directory root (HTML input only)
    string? href = ();
    // "M" for mandatory, "C" for conditional
    string status = "C";
    // Maximum repeat count declared in the table
    int maxOccurances = 0;
    // Trailing group nesting characters, from which the nesting depth is derived
    string rest = "";
|};

// Extracts a table row from a regex match of the segment table.
type TableRowScanner function (regexp:Groups row) returns TableRow|error;

// Resolves the definition of a segment referenced by the segment table.
// Returns nil when the input has no definition for the segment.
type SegmentDefResolver function (TableRow row, string code, string tag) returns SegmentDef?|error;

type EnvelopeLevel record {|
    (Segement|SegmentGroup)[] header;
    (Segement|SegmentGroup)[] trailer;
|};

type EnvelopeSchema record {|
    EnvelopeLevel interchange;
    EnvelopeLevel group?;
    EnvelopeLevel 'transaction;
|};

type EDISchema record {|
    string name;
    string[] ignoreSegments;
    Delimiters delimiters;
    EnvelopeSchema envelope?;
    (Segement|SegmentGroup)[] segments;
    SegmentDefintions segmentDefinitions;
|};

final http:Client edifactClient = check new ("https://service.unece.org/");
readonly & string edifactApi = "";

final string:RegExp msgTypeReg = re `<A HREF = "([^"]+)">([^<]+)</A>`;

final regexp:RegExp segementTableReg = re `\d+\.\d+\.\d+  Segment table([\s\S]+)`;

final regexp:RegExp segmentGroupReg = re `Segment group (\d+)\s+------------------\s+([CM])\s+(\d+)(-+\+*\|*)`;
final regexp:RegExp segmentGroupOrSegmentReg = re `<A HREF = "\.\./([^"]+)">([^<]+)</A>\s+(.*)\s+([CM])\s+(\d+)([\s-]+\+*\|*)|Segment group (\d+)\s+------------------\s+([CM])\s+(\d+)(-+\+*\|*)`;

final regexp:RegExp fieldAndComponentReg = re `(\d+)\s+<A HREF = "\.\./([^"]+)">([^<]+)</A>\s+(.*)\s+([CM])\s+(\d+.*)|       <A HREF = "\.\./([^"]+)">([^<]+)</A>\s+([A-Za-z-\n\s]*)\s+([CM])`;
final regexp:RegExp fieldReg = re `(\d+)\s+<A HREF = "\.\./([^"]+)">([^<]+)</A>\s+(.*)\s+([CM])\s+(\d+.*)`;

final regexp:RegExp componentNameReg = re `<H3>[|*]?\s+(\d+)\s+([^<]+)\s+\[[A-Za-z]+\]?\s*</H3>`;
final regexp:RegExp componentTypeReg = re `Repr:(.*)`;

final regexp:RegExp tagSeparatorReg = re `[ /\-&]`;
final regexp:RegExp illegalTagCharReg = re `[^A-Za-z0-9_]`;
final regexp:RegExp leadingDigitReg = re `[0-9].*`;

// Separates words in a generated tag, and disambiguates repeated fields,
// components and sibling segments.
const string UNDERSCORE = "_";

public function convertEdifactToEdi(string version, string dir, string? messageType = (),
        string? inputPath = ()) returns error? {
    if inputPath is string {
        return convertLocalEdifactToEdi(version, dir, messageType, inputPath);
    }
    edifactApi = "trade/untdid/" + version + "/";
    string msgTypesUrl = edifactApi + "trmd/";
    http:Response msgTypesRes = check edifactClient->get(msgTypesUrl + "trmdi1.htm");
    if msgTypesRes.statusCode == 404 {
        return error("Invalid version " + version + " is given");
    }
    if msgTypesRes.statusCode != 200 {
        return error(directoryUnreachableMessage(version, messageType, msgTypesRes.statusCode));
    }
    string msgTypes = check msgTypesRes.getTextPayload();

    SegmentDefintions allSegmentDefinitions = {};
    regexp:Groups[] msgGroups = msgTypeReg.findAllGroups(msgTypes);    
    foreach regexp:Groups msgGroup in msgGroups {
        regexp:Span? urlMatch = msgGroup[1];
        regexp:Span? codeMatch = msgGroup[2];
        if urlMatch is () || codeMatch is () {
            return error("Invalid message type is found");
        }
        string code = codeMatch.substring();
        if messageType is () {
            check genEdiSchema(msgTypesUrl + urlMatch.substring(), code, dir, allSegmentDefinitions);
        } else {
            if code == messageType {
                check genEdiSchema(msgTypesUrl + urlMatch.substring(), code, dir, allSegmentDefinitions);
                return;
            }
        }
    }
    if messageType !is () {
        return error("Invalid message type " + messageType + " is given");
    }
}

// Reports that the directory pages cannot be fetched and how to supply them
// locally instead. `service.unece.org` is behind a bot challenge that requires a
// browser, so no request the tool can make will get through.
function directoryUnreachableMessage(string version, string? messageType, int statusCode) returns string {
    string 'type = messageType ?: "<message type>";
    string[] lines = [
        string `The UNECE directory service is not reachable (HTTP ${statusCode}). It now requires a browser, ` +
            "so the tool cannot download the EDIFACT directory.",
        string `Download the ${version.toUpperAscii()} release archive from ` +
            "https://unece.org/trade/uncefact/unedifact/download and convert from it:",
        string `    bal edi convertEdifactSchema -v ${version} -t ${'type} -i <downloaded archive> -o <output directory>`
    ];
    return "\n".'join(...lines);
}

function genEdiSchema(string url, string code, string dir, SegmentDefintions allSegmentDefinitions) returns error? {
    log:printInfo("Generating EDI schema for " + code);
    http:Response msgTypeRes = check edifactClient->get(url);
    EDISchema ediSchema = check genMsgTypeEdiSchema(check msgTypeRes.getTextPayload(), allSegmentDefinitions, code,
            segmentGroupOrSegmentReg, scanHtmlTableRow, htmlSegmentDefResolver);
    string dirPath = dir;
    if dir[dir.length() - 1] != "/" {
        dirPath = dir + "/";
    }
    check io:fileWriteJson(dirPath + code + ".json", ediSchema);
}

function genMsgTypeEdiSchema(string msgType, SegmentDefintions segmentDefinitions, string name,
        regexp:RegExp tableRowReg, TableRowScanner scanRow, SegmentDefResolver resolveSegmentDef)
        returns EDISchema|error {
    EDISchema ediSchema = {
        name,
        // The ballerina/edi runtime (>= 1.6.0) strips and validates a leading
        // UNA service string advice itself in all schema-driven envelope paths
        // (fromEdiString, headersFromEdiString, interchangeFromEdiString).
        // "UNA" is additionally listed here as belt-and-braces for any
        // non-envelope path (e.g. a user who strips the `envelope` field from
        // the generated schema): the segment reader then skips UNA via the
        // ignore list instead of failing with "Mandatory unit is missing".
        ignoreSegments: ["UNA"],
        delimiters: {
            segment: "'",
            'field: "+",
            component: ":",
            repetition: "*",
            decimalSeparator: ","
        },
        segments: [],
        segmentDefinitions: {}
    };

    regexp:Groups[] segmentTableGroups = segementTableReg.findAllGroups(msgType);
    if segmentTableGroups.length() != 1 {
        return error("Cannot find a match for single segment table");
    }
    regexp:Groups segmentTableGroup = segmentTableGroups[0];
    if segmentTableGroup.length() != 2 {
        return error("Segment table not found");
    }
    regexp:Span? segmentTableMatch = segmentTableGroup[1];
    if segmentTableMatch is () {
        return error("Segment table not found");
    }

    string segmentTable = segmentTableMatch.substring();
    TableRow[] rows = [];
    foreach regexp:Groups row in tableRowReg.findAllGroups(segmentTable) {
        rows.push(check scanRow(row));
    }

    check genSegmentsSchema(rows, segmentDefinitions, ediSchema.segments, ediSchema.segmentDefinitions,
            resolveSegmentDef);

    // EDIFACT envelope: interchange = UNB / UNZ, transaction = UNH / UNT.
    // No group level. Lift UNH / UNT out of `segments` and add UNB / UNZ
    // definitions so the runtime can parse the full interchange.
    check populateEdifactEnvelope(ediSchema);
    return ediSchema;
}

// Builds the structured envelope for an EDIFACT schema. UNH and UNT are
// extracted from `segments` (where the message-table conversion places them)
// into `envelope.transaction`; UNB and UNZ are added as new envelope refs and
// their definitions inserted into `segmentDefinitions`. Returns an error if
// the source message spec does not declare UNH / UNT — generating a closed
// envelope wrapper without transaction header/trailer segments would produce
// a schema that can never parse a conformant interchange.
function populateEdifactEnvelope(EDISchema schema) returns error? {
    (Segement|SegmentGroup)[] body = [];
    (Segement|SegmentGroup)[] txnHeader = [];
    (Segement|SegmentGroup)[] txnTrailer = [];

    foreach Segement|SegmentGroup seg in schema.segments {
        if seg is Segement && seg.ref == UNH.code {
            txnHeader.push(seg);
        } else if seg is Segement && seg.ref == UNT.code {
            txnTrailer.push(seg);
        } else {
            body.push(seg);
        }
    }

    if txnHeader.length() == 0 || txnTrailer.length() == 0 {
        return error(string `Cannot generate envelope for message type ${schema.name}: ` +
                "the source specification does not declare " +
                (txnHeader.length() == 0 ? UNH.code : UNT.code) +
                " in its segment table. An envelope without transaction " +
                "header/trailer segments cannot parse a conformant interchange.");
    }

    if !schema.segmentDefinitions.hasKey(UNB.code) {
        schema.segmentDefinitions[UNB.code] = UNB;
    }
    if !schema.segmentDefinitions.hasKey(UNZ.code) {
        schema.segmentDefinitions[UNZ.code] = UNZ;
    }

    schema.segments = body;
    schema.envelope = {
        interchange: {
            header: [{ref: UNB.code, tag: "interchange_header", minOccurances: 1, maxOccurances: 1}],
            trailer: [{ref: UNZ.code, tag: "interchange_trailer", minOccurances: 1, maxOccurances: 1}]
        },
        'transaction: {
            header: forceMandatory(txnHeader),
            trailer: forceMandatory(txnTrailer)
        }
    };
}

// UNH and UNT are lifted out of `segments` as-is and therefore inherit whatever
// `minOccurances` the message-table extractor chose (typically 0 because the
// table emits all segments as conditional). At the envelope level they are
// mandatory by definition, so promote them.
function forceMandatory((Segement|SegmentGroup)[] units) returns (Segement|SegmentGroup)[] {
    (Segement|SegmentGroup)[] result = [];
    foreach Segement|SegmentGroup u in units {
        if u is Segement {
            Segement promoted = u.clone();
            promoted.minOccurances = 1;
            result.push(promoted);
        } else {
            SegmentGroup promoted = u.clone();
            promoted.minOccurances = 1;
            result.push(promoted);
        }
    }
    return result;
}

function genSegmentsSchema(TableRow[] rows, map<SegmentDef> allSegmentDefinitions, (Segement|SegmentGroup)[] segments, SegmentDefintions segmentDefintions, SegmentDefResolver resolveSegmentDef) returns error? {
    int currentDepth = 0;
    SegmentGroup[] segmentGroupsSeq = [];
    SegmentGroup? currentGroup = ();
    foreach TableRow row in rows {
        if row.groupNumber !is () {
            [SegmentGroup, int] [segmentGroup, depth] = check genSegmentGroupSchema(row);
            if depth == 0 {
                segmentGroupsSeq = [segmentGroup];
                segments.push(segmentGroup);
                currentDepth = 0;
            } else if currentDepth == depth {
                _ = segmentGroupsSeq.pop();
                segmentGroupsSeq[segmentGroupsSeq.length() - 1].segments.push(segmentGroup);
                segmentGroupsSeq.push(segmentGroup);
            } else if currentDepth < depth {
                segmentGroupsSeq[segmentGroupsSeq.length() - 1].segments.push(segmentGroup);
                segmentGroupsSeq.push(segmentGroup);
                currentDepth = depth;
            } else {
                int depthDiff = currentDepth - depth;
                foreach int i in 0 ..< depthDiff {
                    _ = segmentGroupsSeq.pop();
                    currentDepth = currentDepth - 1;
                }
                _ = segmentGroupsSeq.pop();
                segmentGroupsSeq[segmentGroupsSeq.length() - 1].segments.push(segmentGroup);
                segmentGroupsSeq.push(segmentGroup);
            }
        } else {
            if segmentGroupsSeq.length() > 0 {
                currentGroup = segmentGroupsSeq[segmentGroupsSeq.length() - 1];
                if row.rest.trim() == "" {
                    currentGroup = ();
                }
            }
            check genSementSchema(row, allSegmentDefinitions, currentGroup, segments, segmentDefintions,
                    resolveSegmentDef);
        }
    }
}

// Reads a segment group opener. Group rows carry the group number in the first
// match group of either input format.
function scanGroupRow(regexp:Groups groupMatch) returns TableRow|error {
    regexp:Span? groupNumber = groupMatch[1];
    regexp:Span? status = groupMatch[2];
    regexp:Span? occurance = groupMatch[3];
    regexp:Span? depthMatch = groupMatch[4];
    if groupNumber is () || status is () || occurance is () || depthMatch is () {
        return error("Invalid segment group found");
    }
    return {
        groupNumber: groupNumber.substring(),
        status: status.substring(),
        maxOccurances: check int:fromString(occurance.substring()),
        rest: depthMatch.substring()
    };
}

function genSegmentGroupSchema(TableRow row) returns [SegmentGroup, int]|error {
    string? groupNumber = row.groupNumber;
    if groupNumber is () {
        return error("Invalid segment group found");
    }
    int depth = getDepth(row.rest);
    string groupName = "group_" + groupNumber;
    SegmentGroup group = {
        "tag": groupName,
        "minOccurances": getMinOccurances(row.status),
        "maxOccurances": row.maxOccurances,
        segments: []
    };
    return [group, depth];
}

function genSementSchema(TableRow row, map<SegmentDef> allSegmentDefinitions, SegmentGroup? currentGroup, (Segement|SegmentGroup)[] segments, SegmentDefintions segmentDefintions, SegmentDefResolver resolveSegmentDef) returns error? {
    string? ref = row.ref;
    if ref is () {
        return error("Invalid segment found");
    }

    string code = ref;
    (Segement|SegmentGroup)[] siblings = currentGroup is () ? segments : currentGroup.segments;
    string tag = uniqueSiblingTag(siblings, getTag(row.name));
    Segement segment = {
        "ref": code,
        tag,
        "minOccurances": getMinOccurances(row.status),
        "maxOccurances": row.maxOccurances
    };
    siblings.push(segment);
    if !segmentDefintions.hasKey(code) {
        SegmentDef? seg = allSegmentDefinitions[code];
        if seg is () {
            SegmentDef? predefined = predefinedSegmentDef(code);
            if predefined !is () {
                allSegmentDefinitions[code] = predefined;
                segmentDefintions[code] = predefined;
            } else {
                SegmentDef? currentSegmentDef = check resolveSegmentDef(row, code, tag);
                if currentSegmentDef !is () {
                    allSegmentDefinitions[code] = currentSegmentDef;
                    segmentDefintions[code] = currentSegmentDef;
                }
            }
        } else {
            segmentDefintions[code] = seg;
        }
    }
}

// Service segments whose definitions ship with the tool rather than being read
// from the directory.
function predefinedSegmentDef(string code) returns SegmentDef? {
    match code {
        "UNH" => {
            return UNH;
        }
        "UNT" => {
            return UNT;
        }
        "UNS" => {
            return UNS;
        }
        "DTM" => {
            return DTM;
        }
        "UGH" => {
            return UGH;
        }
        "UGT" => {
            return UGT;
        }
    }
    return ();
}

// Reads one row of an HTML segment table, where the first match group is the
// link to the segment page.
function scanHtmlTableRow(regexp:Groups row) returns TableRow|error {
    if segmentGroupReg.isFullMatch(row[0].substring()) {
        return scanGroupRow(row);
    }
    regexp:Span? href = row[1];
    regexp:Span? codeMatch = row[2];
    regexp:Span? descriptionMatch = row[3];
    regexp:Span? status = row[4];
    regexp:Span? occurance = row[5];
    regexp:Span? rest = row[6];
    if href is () || codeMatch is () || descriptionMatch is () || status is () || occurance is () || rest is () {
        return error("Invalid segment found");
    }
    return {
        ref: codeMatch.substring(),
        name: descriptionMatch.substring().trim(),
        href: href.substring(),
        status: status.substring(),
        maxOccurances: check int:fromString(occurance.substring()),
        rest: rest.substring()
    };
}

// Fetches and parses the segment page linked from the segment table.
function htmlSegmentDefResolver(TableRow row, string code, string tag) returns SegmentDef?|error {
    string? href = row.href;
    if href is () {
        return error("Invalid segment found");
    }
    http:Response segementPage = check edifactClient->get(edifactApi + href);
    if segementPage.statusCode == 200 {
        return getSegmentDef(check segementPage.getTextPayload(), code, tag);
    }
    if segementPage.statusCode == 404 {
        log:printDebug("Segment " + code + " not found");
        return ();
    }
    return error(string `Failed to fetch the definition of segment ${code} (HTTP ${segementPage.statusCode})`);
}

function getSegmentDef(string segmentPage, string code, string tag) returns SegmentDef|error {
    regexp:Groups[] fieldGroups = fieldAndComponentReg.findAllGroups(segmentPage);
    FieldDef[] fields = [{tag: "code", required: true}];
    check addFields(fields, fieldGroups);
    return {code, tag, fields};
}

function addFields(FieldDef[] fields, regexp:Groups[] fieldGroups) returns error? {
    FieldDef currentField = {...fields[0]};
    string[] componentNames = [];
    string[] fieldNames = [];
    foreach regexp:Groups fieldGroup in fieldGroups {
        if fieldReg.isFullMatch(fieldGroup[0].substring()) {
            currentField = check getField(fieldGroup, fieldNames);
            currentField.components = [];
            fields.push(currentField);
            componentNames = [];
        } else {
            (<ComponentDef[]>currentField.components).push(check getComponent(fieldGroup, componentNames));
        }
    }
}

function getComponent(regexp:Groups fieldGroup, string[] componentNames) returns ComponentDef|error {
    regexp:Span? urlMatch = fieldGroup[1];
    regexp:Span? tagMatch = fieldGroup[3];
    regexp:Span? statusMatch = fieldGroup[4];
    if urlMatch is () || statusMatch is () || tagMatch is () {
        return error("Invalid component found");
    }
    http:Response componentPageRes = check edifactClient->get(edifactApi + urlMatch.substring().trim());
    if componentPageRes.statusCode != 200 {
        return error("Invalid component found");
    }
    // TODO: if 400, use matches to parse data.
    string componentPage = check componentPageRes.getTextPayload();
    regexp:Groups typeGroups = componentTypeReg.findAllGroups(componentPage)[0];
    regexp:Span? typeMatch = typeGroups[1];
    if typeMatch is () {
        return error("Invalid component found");
    }
    regexp:Groups componentNameGroups = componentNameReg.findAllGroups(componentPage)[0];
    regexp:Span? componentNameMatch = componentNameGroups[2];
    if componentNameMatch is () {
        return error("Invalid component found");
    }

    return {
        tag: getComponentName(componentNames, getTag(componentNameMatch.substring().trim())),
        required: statusMatch.substring() == "M" ? true : false,
        dataType: getType(typeMatch.substring().trim())
    };
}

function getField(regexp:Groups fieldGroup, string[] fieldNames) returns FieldDef|error {
    regexp:Span? tagMatch = fieldGroup[4];
    regexp:Span? statusMatch = fieldGroup[5];
    regexp:Span? occuranceAndTypeMatch = fieldGroup[6];
    if tagMatch is () || statusMatch is () || occuranceAndTypeMatch is () {
        return error("Invalid field found");
    }
    string occuranceAndType = occuranceAndTypeMatch.substring().trim();
    regexp:RegExp occuranceAndTypeReg = re `(\d+)\s*(.*)`;
    regexp:Groups occuranceAndTypeGroups = occuranceAndTypeReg.findAllGroups(occuranceAndType)[0];
    regexp:Span? occuranceMatch = occuranceAndTypeGroups[1];
    if occuranceMatch is () {
        return error("Invalid field found");
    }
    int occurance = check int:fromString(occuranceMatch.substring());
    regexp:Span? typeMatch = occuranceAndTypeGroups[2];
    if typeMatch is () {
        return error("Invalid field type found");
    }
    string? 'type = ();
    string typeString = typeMatch.substring().trim();
    if typeString == "" {
        'type = "composite";
    } else {
        'type = getType(typeString);
    }
    return {tag: getFieldNames(fieldNames, getTag(tagMatch.substring().trim())), dataType: 'type, repeat: occurance > 1 ? true : false};
}

// Element names become record field names in the generated code, so a tag has
// to be a legal Ballerina identifier. Separators become underscores, and any
// other character that is not legal in an identifier is dropped: an element
// named "United Nations Dangerous Goods (UNDG) identifier" would otherwise
// produce `..._(UNDG)_...` and the generated module would not compile.
function getTag(string description) returns string {
    string tag = illegalTagCharReg.replaceAll(
            tagSeparatorReg.replaceAll(description, UNDERSCORE), "");
    // An identifier cannot start with a digit.
    return leadingDigitReg.isFullMatch(tag) ? UNDERSCORE + tag : tag;
}

function getMinOccurances(string occurance) returns int? {
    return occurance == "M" ? 1 : ();
}

function getType(string t) returns string? {
    if t.includes("an..") {
        return "string";
    } else if t.includes("n..") {
        return "int";
    }
    // TODO: Support for float
    return ();
}

function getDepth(string s) returns int {
    int depth = 0;
    foreach string c in s {
        if c == "|" {
            depth = depth + 1;
        }
    }
    return depth;
}

function isSingleSegment(string s) returns boolean {
    return !s.includes("|");
}

// In original spec, there are some components with same name. This function will add a number to the end of the name
// Otherwise, it will generate Ballerina fields with same name.
function getComponentName(string[] componentNames, string tag) returns string {
    int length = componentNames.length();
    foreach string name in componentNames {
        if name == tag {
            string newName = tag + UNDERSCORE + length.toString();
            componentNames.push(newName);
            return newName;
        }
    }
    componentNames.push(tag);
    return tag;
}

// A message can list the same segment at two positions of one segment group.
// Both rows carry the same name, so without a suffix codegen emits two record
// fields with that name and the generated module does not compile. Uses the
// same "_1", "_2" convention as repeated fields and components.
function uniqueSiblingTag((Segement|SegmentGroup)[] siblings, string tag) returns string {
    string[] taken = from Segement|SegmentGroup sibling in siblings
        select sibling.tag;
    if taken.indexOf(tag) is () {
        return tag;
    }
    int suffix = 1;
    while taken.indexOf(tag + UNDERSCORE + suffix.toString()) !is () {
        suffix += 1;
    }
    return tag + UNDERSCORE + suffix.toString();
}

function getFieldNames(string[] fieldNames, string tag) returns string {
    int length = fieldNames.length();
    foreach string name in fieldNames {
        if name == tag {
            string newName = tag + UNDERSCORE + length.toString();
            fieldNames.push(newName);
            return newName;
        }
    }
    fieldNames.push(tag);
    return tag;
}
