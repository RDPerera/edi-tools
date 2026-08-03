/*
 *  Copyright (c) 2023, WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
 *
 *  WSO2 Inc. licenses this file to you under the Apache License,
 *  Version 2.0 (the "License"); you may not use this file except
 *  in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing,
 *  software distributed under the License is distributed on an
 *  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 *  KIND, either express or implied.  See the License for the
 *  specific language governing permissions and limitations
 *  under the License.
 */

package io.ballerina.edi.cmd;

import io.ballerina.cli.BLauncherCmd;
import picocli.CommandLine;

import java.io.PrintStream;
import java.util.List;

@CommandLine.Command(name = "codegen", description = "Generates Ballerina records and parser functions for a given EDI schema.")
public class CodegenCmd implements BLauncherCmd {
    private static final String CMD_NAME = "codegen";
    private static final String HELP_FILE = CMD_NAME + ".help";

    private final PrintStream printStream;

    @CommandLine.Option(names = { "-h", "--help" }, hidden = true, usageHelp = true)
    private boolean helpFlag;

    @CommandLine.Option(names = { "-i", "--input" }, required = true, description = "EDI schema file path")
    private String schemaPath;

    @CommandLine.Option(names = { "-o", "--output" }, required = true, description = "Output path")
    private String outputPath;

    public CodegenCmd() {
        this.printStream = System.out;
    }

    @Override
    public void execute() {
        if (helpFlag) {
            EdiCmdUtils.printHelp(printStream, HELP_FILE);
            return;
        }
        if (schemaPath == null || outputPath == null) {
            throw EdiCmdUtils.missingOptions(CMD_NAME, HELP_FILE);
        }
        printStream.println("Generating code for " + schemaPath + "...");
        EdiCmdUtils.runEdiTool(List.of(CMD_NAME, schemaPath, outputPath));
    }

    @Override
    public String getName() {
        return CMD_NAME;
    }

    @Override
    public void printLongDesc(StringBuilder stringBuilder) {
        EdiCmdUtils.appendHelp(stringBuilder, HELP_FILE);
    }

    @Override
    public void printUsage(StringBuilder stringBuilder) {
        EdiCmdUtils.appendHelp(stringBuilder, HELP_FILE);
    }

    @Override
    public void setParentCmdParser(CommandLine commandLine) {
    }
}
