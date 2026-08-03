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
import java.util.ArrayList;
import java.util.List;

@CommandLine.Command(name = "convertX12Schema", description = "Converts X12 schema to JSON schema.")
public class ConvertX12Cmd implements BLauncherCmd {

    private static final String CMD_NAME = "convertX12Schema";
    private static final String HELP_FILE = "convertX12.help";

    private final PrintStream printStream;

    @CommandLine.Option(names = { "-h", "--help" }, hidden = true, usageHelp = true)
    private boolean helpFlag;

    @CommandLine.Option(names = { "-H", "--headers" }, description = { "Include headers in the input" })
    private boolean headersIncluded;

    @CommandLine.Option(names = { "-c", "--collection" }, description = { "Switch to collection mode" })
    private boolean collectionMode;

    @CommandLine.Option(names = { "-i", "--input" }, required = true, description = { "Input X12 schema path" })
    private String inputPath;

    @CommandLine.Option(names = { "-o", "--output" }, required = true, description = { "Output path" })
    private String outputPath;

    @CommandLine.Option(names = { "-d", "--segdet" }, description = { "Segment details path" })
    private String segdetPath;

    public ConvertX12Cmd() {
        this.printStream = System.out;
    }

    @Override
    public void execute() {
        if (helpFlag) {
            EdiCmdUtils.printHelp(printStream, HELP_FILE);
            return;
        }
        if (inputPath == null || outputPath == null) {
            throw EdiCmdUtils.missingOptions(CMD_NAME, HELP_FILE);
        }
        StringBuilder progress = new StringBuilder("Converting schema ");
        if (collectionMode) {
            progress.append("in collection ");
        }
        if (headersIncluded) {
            progress.append("with headers ");
        }
        progress.append(inputPath).append("...");
        printStream.println(progress);

        List<String> toolArgs = new ArrayList<>();
        toolArgs.add(CMD_NAME);
        if (headersIncluded) {
            toolArgs.add("H");
        }
        if (collectionMode) {
            toolArgs.add("c");
        }
        toolArgs.add(inputPath);
        toolArgs.add(outputPath);
        if (segdetPath != null) {
            toolArgs.add(segdetPath);
        }
        EdiCmdUtils.runEdiTool(toolArgs);
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
