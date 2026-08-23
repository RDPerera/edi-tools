## Overview

Electronic Data Interchange (EDI) is how businesses exchange documents such as purchase orders, invoices, and shipping notices with their trading partners. Most EDI traffic follows one of two standards:

- **EDIFACT** — the international UN standard, with message types such as `ORDERS`, `INVOIC`, and `DESADV`.
- **X12** — the ANSI ASC X12 standard used across North America, with transaction sets such as `850` (purchase order), `810` (invoice), and `856` (ship notice).

The `bal edi` tool generates Ballerina record types and parser functions from an EDI standard's specification, so EDI documents can be processed as typed Ballerina records rather than parsed by hand.

The tool can:

- **Generate code from an EDIFACT or X12 spec** — the most common case.
- **Bundle several schemas into a reusable library package**, optionally exposed as a REST service.
- **Generate code from a custom schema** — for proprietary or non-standard formats.

The generated code uses the [`ballerina/edi`](https://github.com/ballerina-platform/module-ballerina-edi) module at runtime.

## Installation

Pull the EDI tool from [Ballerina Central](https://central.ballerina.io/):

```
bal tool pull edi
```

## Generate from an EDIFACT spec

EDIFACT is the international EDI standard. The tool includes the EDIFACT message specifications, so the schema is generated from the version and message type — no schema needs to be written by hand.

**Step 1 — Convert the spec into a Ballerina EDI schema.** Download the release archive for the required version from the [UN/EDIFACT directory downloads](https://unece.org/trade/uncefact/unedifact/download) and pass it with `-i`. Use `-v` for the EDIFACT version (e.g. `d03a`) and `-t` for the message type (e.g. `ORDERS`, `INVOIC`); omit `-t` to convert every message type in the directory. `-o` is an output directory; the schema is written there as `<message-type>.json` (here, `resources/ORDERS.json`):

```
bal edi convertEdifactSchema -v d03a -t ORDERS -i d03a.zip -o resources
```

`-i` accepts the downloaded archive directly, or a directory it was extracted to.

**Step 2 — Generate Ballerina records and parser functions:**

```
bal edi codegen -i resources/ORDERS.json -o orders.bal
```

The default module now contains typed records plus `fromEdiString` / `toEdiString`. Because EDIFACT documents carry an envelope, the tool also emits `interchangeFromEdiString` / `interchangeToEdiString`. See [Using the generated code](#using-the-generated-code).

> **Tip:** For common EDIFACT D03A message types, prebuilt packages are published under the `ballerinax` organization (e.g. `ballerinax/edifact.d03a.supplychain`) and can be imported directly without generating any code. See the [`ballerina/edi` module](https://github.com/ballerina-platform/module-ballerina-edi#working-with-standard-edi-formats).

## Generate from an X12 schema

X12 is the EDI standard used across North America. X12 specifications are licensed from ASC X12, so the workflow starts from a licensed X12 schema (XSD) and converts it into a Ballerina EDI schema.

**Step 1 — Convert the X12 schema into a Ballerina EDI schema:**

```
bal edi convertX12Schema -i input/850.xsd -o resources/850-schema.json
```

**Step 2 — Generate Ballerina code:**

```
bal edi codegen -i resources/850-schema.json -o po.bal
```

The result matches the EDIFACT flow: typed records and parser functions ready for use.

## Using the generated code

Create a project and generate the code into its default module:

```
bal new sample
cd sample
bal edi codegen -i resources/ORDERS.json -o orders.bal
```

The generated code exposes typed records named after the schema, plus parser functions, in the default module. For an `ORDERS` schema, the body record is `ORDERS` and the interchange wrapper is `ORDERSInterchange`. For larger projects, the generated EDI code can live in its own package within a Ballerina workspace alongside your integration.

### Reading EDI files

`fromEdiString` reads EDI text into a typed record. Any value in the EDI can then be accessed through the record's fields:

```ballerina
import ballerina/io;

public function main() returns error? {
    string ediText = check io:fileReadString("resources/order.edi");
    ORDERS document = check fromEdiString(ediText);
    io:println(document);
}
```

### Writing EDI files

`toEdiString` serializes a typed record back into EDI text:

```ballerina
import ballerina/io;

public function main() returns error? {
    ORDERS document = { /* populate the record */ };
    string ediText = check toEdiString(document);
    io:println(ediText);
}
```

### Reading and writing EDI envelopes

An EDI interchange is wrapped in an **envelope** — interchange and (for X12) functional-group headers and trailers around one or more transactions. When the schema comes from an X12 or EDIFACT spec, `codegen` also emits typed envelope wrappers and envelope-aware functions:

- `<Name>Interchange`, `<Name>FunctionalGroup` (X12), and `<Name>Transaction` records that mirror the envelope hierarchy. Each `<Name>Transaction.body` is `<Name>|error`, so a malformed transaction body is captured rather than aborting the whole parse (fail-safe).
- `headersFromEdiString` — extracts just the envelope headers (useful for routing).
- `interchangeFromEdiString` — parses the full interchange into a typed `<Name>Interchange`.
- `interchangeToEdiString` — the inverse, serializing a `<Name>Interchange` back to EDI text.

```ballerina
import ballerina/io;

public function main() returns error? {
    string ediText = check io:fileReadString("resources/order.edi");

    // Parse the full envelope hierarchy into typed records.
    ORDERSInterchange interchange = check interchangeFromEdiString(ediText);
    foreach var txn in interchange.transactions {
        ORDERS|error body = txn.body;
        if body is error {
            io:println("Quarantined: ", body.message());
            continue;
        }
        io:println(body);
    }

    // Serialize a (filtered/transformed) interchange back to EDI text.
    string ediOut = check interchangeToEdiString(interchange);
    io:println(ediOut);
}
```

> The envelope wrappers require `ballerina/edi >= 1.6.0`. For envelope-aware schemas, `libgen` pins this floor via a `[[dependency]]` block in the generated package's `Ballerina.toml` and prints a notice.

## Generating a library package

Organizations usually work with several EDI formats at once. Instead of running `codegen` per schema and tracking the outputs by hand, `libgen` bundles a directory of schemas into a single importable Ballerina package:

```
bal edi libgen -p <organization-name/package-name> -i <input schema folder> -o <output folder>
```

For example, an organization "CityMart" that handles X12 `850`, `810`, `820`, and `855` can drop those schemas into a folder and run:

```
bal edi libgen -p citymart/porder -i CityMart/schemas -o CityMart/lib
```

Each schema is generated into its own module (`m850`, `m810`, …) to avoid conflicts, alongside a `Ballerina.toml`, shared utilities, and a REST connector. Build and publish the package with `bal pack` and `bal push`, then import it like any other library:

```ballerina
import ballerina/io;
import citymart/porder.m850;
import citymart/porder.m855;

public function main() returns error? {
    string orderText = check io:fileReadString("orders/order10.edi");
    m850:EDI_850_Purchase_Order purchaseOrder = check m850:fromEdiString(orderText);
    // ...
    m855:EDI_855_Purchase_Order_Acknowledgement orderAck = { /* ... */ };
    string ackText = check m855:toEdiString(orderAck);
    check io:fileWriteString("acks/ack10.edi", ackText);
}
```

The package's default module additionally offers a name-dispatched facade over every schema in the package — `fromEdiString(ediText, ediName)` and `toEdiString(data, ediName)` — which is useful when the EDI type is only known at runtime. When at least one schema declares an envelope, the facade also covers the envelope functions:

```ballerina
import ballerina/io;
import citymart/porder;
import citymart/porder.m850;

public function main() returns error? {
    string orderText = check io:fileReadString("orders/order10.edi");

    // Route on the envelope headers without parsing the transaction bodies.
    anydata headers = check porder:headersFromEdiString(orderText, porder:EDI_850);

    any interchange = check porder:interchangeFromEdiString(orderText, porder:EDI_850);
    m850:EDI_850_Purchase_OrderInterchange typed = check interchange.ensureType();
    io:println(typed.groups.length());
}
```

Because the facade is keyed by name, it hands back the module's typed record boxed in `anydata` (headers) or `any` (interchanges); narrow it with `ensureType` as above. Interchanges are `any` rather than `anydata` because `<Name>Transaction.body` is `<Name>|error`, and a value holding an error is not `anydata`. Call `hasEnvelope(ediName)` to test whether a given EDI type supports these functions — for a schema without an envelope they return an error.

Because trading partners often use variations of a standard format, a partner-specific package can be generated from partner-specific schemas.

### Running a generated package as a REST service

A generated package also includes a REST connector, so it can be built (`bal build`) and run (`bal run`) as a standalone service that converts EDI over HTTP — useful when EDI processing is deployed as a separate microservice. Each schema gets an EDI-to-JSON and a JSON-to-EDI endpoint. For example, converting an X12 850 to JSON:

```
curl --location 'http://localhost:9090/porderParser/edis/850' \
--header 'Content-Type: text/plain' \
--data-raw 'GS*PO*SENDERID*RECEIVERID*20240802*1705*1*X*004010~
ST*850*0001~
BEG*00*NE*4500012345**20240802~
PO1*1*10*EA*15.00**BP*123456789012~
CTT*1~
SE*5*0001~
GE*1*1~
IEA*1*000000001~'
```

The matching `objects/850` endpoint performs the reverse (JSON to X12 850 text).

## Custom EDI schemas

For a proprietary or non-standard format that is neither X12 nor EDIFACT, the structure can be described directly in the Ballerina EDI schema format (JSON) and passed to `codegen` without a conversion step. A minimal schema for a simple order looks like:

```json
{
    "name": "SimpleOrder",
    "delimiters": {"segment": "~", "field": "*", "component": ":", "repetition": "^"},
    "segments": [
        {
            "code": "HDR",
            "tag": "header",
            "minOccurances": 1,
            "fields": [{"tag": "code"}, {"tag": "orderId"}, {"tag": "organization"}, {"tag": "date"}]
        },
        {
            "code": "ITM",
            "tag": "items",
            "maxOccurances": -1,
            "fields": [{"tag": "code"}, {"tag": "item"}, {"tag": "quantity", "dataType": "int"}]
        }
    ]
}
```

This parses EDI documents with one `HDR` segment (mapped to `header`) and any number of `ITM` segments (mapped to `items`), for example:

```
HDR*ORDER_1201*ABC_Store*2008-01-01~
ITM*A-250*12~
ITM*A-45*100~
```

Generate code from it the same way:

```
bal edi codegen -i schema.json -o orders.bal
```

For the full schema grammar — delimiters, segment groups, fields, components, sub-components, the `envelope` declaration, and additional configuration — see the [Ballerina EDI specification](https://github.com/ballerina-platform/module-ballerina-edi/blob/main/docs/spec/spec.md#7-schema-definition).

### ESL schemas

ESL (EDI Schema Language) is a schema-definition format that describes an EDI message's structure in YAML, alongside a base segment-definitions file. Convert an ESL schema into a Ballerina EDI schema with `convertESL`:

```
bal edi convertESL -b segment_definitions.yaml -i esl_schema.esl -o resources/schema.json
```

