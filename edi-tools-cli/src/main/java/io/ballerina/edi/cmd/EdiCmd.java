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

import java.util.List;

/**
 * Main class to implement "edi" command for ballerina.
 */
@CommandLine.Command(name = "edi", description = "Provides the functionality required to process EDI files and implement EDI integrations", subcommands = {
        CodegenCmd.class,
        LibgenCmd.class,
        EslCmd.class,
        ConvertX12Cmd.class,
        ConvertEdifactCmd.class
})
public class EdiCmd implements BLauncherCmd {
    private static final String CMD_NAME = "edi";
    private static final String HELP_FILE = "edi.help";

    @CommandLine.Option(names = { "-h", "--help" }, hidden = true)
    private boolean helpFlag;

    public EdiCmd() {
    }

    @Override
    public void execute() {
        EdiCmdUtils.runEdiTool(List.of());
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
    public void setParentCmdParser(CommandLine parentCmdParser) {
    }
}
