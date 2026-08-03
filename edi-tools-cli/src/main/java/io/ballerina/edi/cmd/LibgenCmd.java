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
import io.ballerina.cli.launcher.LauncherUtils;
import picocli.CommandLine;

import java.io.PrintStream;
import java.util.List;

@CommandLine.Command(name = "libgen", description = "Generates Ballerina package for code for the given collection of EDI schemas.")
public class LibgenCmd implements BLauncherCmd {
    private static final String CMD_NAME = "libgen";
    private static final String HELP_FILE = CMD_NAME + ".help";

    private PrintStream printStream;

    @CommandLine.Option(names = { "-h", "--help" }, hidden = true, usageHelp = true)
    private boolean helpFlag;

    @CommandLine.Option(names = { "-p", "--package" }, required = true,
            description = "Package name(organization-name/package-name)")
    private String packageName;

    @CommandLine.Option(names = { "-i", "--input" }, required = true, description = "EDI schemas path")
    private String schemaPath;

    @CommandLine.Option(names = { "-o", "--output" }, required = true, description = "Output path")
    private String outputPath;

    public LibgenCmd() {
        printStream = System.out;
    }

    @Override
    public void execute() {
        if (helpFlag) {
            EdiCmdUtils.printHelp(printStream, HELP_FILE);
            return;
        }
        if (packageName == null || schemaPath == null || outputPath == null) {
            throw EdiCmdUtils.missingOptions(CMD_NAME, HELP_FILE);
        }
        if (!packageName.matches("^[a-zA-Z0-9_]{1,256}/[a-zA-Z0-9_.]{1,256}$")) {
            throw LauncherUtils.createLauncherException(
                    "invalid package name. Package name should be in the format orgname/packagename." +
                    " The orgname part must contain only alphanumeric characters or underscores and be 1 to 256 characters long." +
                    " The packagename part must contain only alphanumeric characters, underscores, or periods and be 1 to 256 characters long.");
        }
        printStream.println("Generating library package for " + packageName + " : " + schemaPath);
        String orgName = packageName.split("/")[0];
        String libName = packageName.split("/")[1];
        EdiCmdUtils.runEdiTool(List.of(CMD_NAME, orgName, libName, schemaPath, outputPath));
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
