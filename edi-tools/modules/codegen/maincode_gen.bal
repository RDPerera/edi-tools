// Copyright (c) 2023 WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 Inc. licenses this file to you under the Apache License,
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

function generateMainCode(LibData libdata) returns string {
    return string `
${libdata.importsBlock}

type EdiSerialize isolated function (anydata) returns string|error;
type EdiDeserialize isolated function (string) returns anydata|error;

public enum EDI_NAME {
    ${libdata.enumBlock}
}

public isolated function getEDINames() returns string[] {
    return ${libdata.ediNames.toString()};
}

# Convert EDI string to Ballerina record.
#
# + ediText - EDI string to be converted
# + ediName - EDI type name
# + return - Ballerina record or error
public isolated function fromEdiString(string ediText, EDI_NAME ediName) returns anydata|error {
    EdiDeserialize? ediDeserialize = ediDeserializers[ediName];
    if ediDeserialize is () {
        return error("EDI deserializer is not initialized for EDI type: " + ediName);
    }
    return ediDeserialize(ediText);
}

# Convert Ballerina record to EDI string.
#
# + data - Ballerina record to be converted
# + ediName - EDI type name
# + return - EDI string or error
public isolated function toEdiString(anydata data, EDI_NAME ediName) returns string|error {
    EdiSerialize? ediSerialize = ediSerializers[ediName];
    if ediSerialize is () {
        return error("EDI serializer is not initialized for EDI type: " + ediName);
    }
    return ediSerialize(data);
}
${generateEnvelopeMainCode(libdata)}
final readonly & map<EdiDeserialize> ediDeserializers = {
    ${libdata.ediDeserializers}
};

final readonly & map<EdiSerialize> ediSerializers = {
    ${libdata.ediSerializers}
};
    `;

}

# Renders the envelope-aware half of the default module: name-dispatched
# counterparts of the `headersFromEdiString` / `interchangeFromEdiString` /
# `interchangeToEdiString` functions that `generateCodeForSchema` emits into each
# EDI module. Only the EDI types whose schema declares an envelope are
# registered, so a library mixing enveloped and plain schemas gets a dispatcher
# that errors for the plain ones rather than a module that does not compile.
#
# The interchange functions are typed `any` rather than `anydata` because
# `<Name>Transaction.body` is `<Name>|error` (fail-safe parsing) and a value
# holding an error is not `anydata`.
#
# + libdata - Library data holding the per-EDI-type envelope dispatch entries
# + return - Ballerina code for the envelope functions, or "" if no schema has an envelope
function generateEnvelopeMainCode(LibData libdata) returns string {
    if !libdata.hasEnvelope {
        return "";
    }
    return string `
type EdiHeadersDeserialize isolated function (string) returns anydata|error;
type EdiInterchangeDeserialize isolated function (string) returns any|error;
type EdiInterchangeSerialize isolated function (any) returns string|error;

# Check whether the given EDI type defines an envelope.
#
# + ediName - EDI type name
# + return - true if the EDI type supports the envelope functions
public isolated function hasEnvelope(EDI_NAME ediName) returns boolean {
    return envelopeHeadersDeserializers.hasKey(ediName);
}

# Parse only the envelope header segments of the given EDI string.
#
# + ediText - EDI string to be parsed
# + ediName - EDI type name
# + return - Envelope headers record, or error
public isolated function headersFromEdiString(string ediText, EDI_NAME ediName) returns anydata|error {
    EdiHeadersDeserialize? headersDeserialize = envelopeHeadersDeserializers[ediName];
    if headersDeserialize is () {
        return error("EDI type does not define an envelope: " + ediName);
    }
    return headersDeserialize(ediText);
}

# Parse the full envelope hierarchy of the given EDI string.
# A malformed transaction body becomes an error in that transaction's body field.
#
# + ediText - EDI string to be parsed
# + ediName - EDI type name
# + return - Interchange record, or error
public isolated function interchangeFromEdiString(string ediText, EDI_NAME ediName) returns any|error {
    EdiInterchangeDeserialize? interchangeDeserialize = envelopeInterchangeDeserializers[ediName];
    if interchangeDeserialize is () {
        return error("EDI type does not define an envelope: " + ediName);
    }
    return interchangeDeserialize(ediText);
}

# Serialize an interchange record into EDI text.
#
# + msg - Interchange record to be converted
# + ediName - EDI type name
# + return - EDI string or error
public isolated function interchangeToEdiString(any msg, EDI_NAME ediName) returns string|error {
    EdiInterchangeSerialize? interchangeSerialize = envelopeInterchangeSerializers[ediName];
    if interchangeSerialize is () {
        return error("EDI type does not define an envelope: " + ediName);
    }
    return interchangeSerialize(msg);
}

final readonly & map<EdiHeadersDeserialize> envelopeHeadersDeserializers = {
    ${libdata.envelopeHeadersDeserializers}
};

final readonly & map<EdiInterchangeDeserialize> envelopeInterchangeDeserializers = {
    ${libdata.envelopeInterchangeDeserializers}
};

final readonly & map<EdiInterchangeSerialize> envelopeInterchangeSerializers = {
    ${libdata.envelopeInterchangeSerializers}
};
`;
}
