# Changelog
This file contains all the notable changes done to the Ballerina EDI Module through the releases.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

### Fixed

## [2.2.0] - 2026-08-03

### Added
- [Generate envelope-aware EDI schemas and typed envelope wrappers (BEP-1441)](https://github.com/ballerina-platform/ballerina-spec/issues/1441)
- [Populate the schema envelope in X12 headers mode so `convertX12Schema -H` output works with envelope-aware APIs (BEP-1441)](https://github.com/ballerina-platform/ballerina-spec/issues/1441)
- [Expose the envelope-aware functions in the default module of a `libgen` package (BEP-1441)](https://github.com/ballerina-platform/ballerina-spec/issues/1441)

### Changed
- [Convert EDIFACT schemas from a locally downloaded UNECE directory passed with `convertEdifactSchema -i`, as `service.unece.org` no longer serves the directories to non-browser clients](https://github.com/ballerina-platform/ballerina-library/issues/8983)

### Fixed
- [Retain segment fields whose names wrap across two lines in the EDIFACT specification, which were previously dropped from the generated segment definitions](https://github.com/ballerina-platform/ballerina-library/issues/8983)
- [Surface command failures instead of exiting with a success status: print usage for `--help` and for missing options, propagate the EDI tool exit code, and stop discarding the tool's error output](https://github.com/ballerina-platform/ballerina-library/issues/8982)
- [Skip non-`.json` entries in a `libgen` schema folder with a warning instead of failing on them, and remove the generated package when no schemas could be generated so an unbuildable one is never left behind](https://github.com/ballerina-platform/ballerina-library/issues/8982)

## [2.0.0] - 2024-05-29

### Changed
- [bal tool is not working when java is not installed](https://github.com/ballerina-platform/ballerina-library/issues/6473)

## [1.0.0] - 2024-03-13

### Added
- [Add support for Ballerina Swan Lake Update 8.](https://github.com/ballerina-platform/ballerina-library/issues/5900)
- [Add support for field length constraints (min/max).](https://github.com/ballerina-platform/ballerina-library/issues/5896)
- Add support for EDIFACT to Ballerina schema conversion.

### Changed
- Documentation improvements on tool and CLI commands.
- Set the default value of `required` to `true` for the field `code` in schema definitions.
