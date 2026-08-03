/*
 *  Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
 *
 *  WSO2 LLC. licenses this file to you under the Apache License,
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

import io.ballerina.cli.launcher.BLauncherException;
import io.ballerina.cli.launcher.LauncherUtils;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.List;

/**
 * Shared helpers for the {@code bal edi} commands: loading CLI help text and running the
 * bundled EDI tool as a child process.
 */
final class EdiCmdUtils {

    private static final String EDI_TOOL = "editools.jar";
    private static final String CLI_DOCS = "cli-docs/";
    private static final String HELP_NOT_AVAILABLE = "Helper text is not available.";

    private EdiCmdUtils() {
    }

    /**
     * Appends the contents of the given {@code cli-docs} help file to the given builder.
     *
     * @param stringBuilder builder to append the help text to
     * @param helpFileName  help file name within {@code cli-docs}, e.g. {@code libgen.help}
     */
    static void appendHelp(StringBuilder stringBuilder, String helpFileName) {
        ClassLoader classLoader = EdiCmdUtils.class.getClassLoader();
        try (InputStream inputStream = classLoader.getResourceAsStream(CLI_DOCS + helpFileName)) {
            if (inputStream == null) {
                stringBuilder.append(HELP_NOT_AVAILABLE);
                return;
            }
            try (BufferedReader reader = new BufferedReader(
                    new InputStreamReader(inputStream, StandardCharsets.UTF_8))) {
                String line = reader.readLine();
                if (line == null) {
                    stringBuilder.append(HELP_NOT_AVAILABLE);
                    return;
                }
                stringBuilder.append(line);
                while ((line = reader.readLine()) != null) {
                    stringBuilder.append('\n').append(line);
                }
            }
        } catch (IOException e) {
            stringBuilder.append(HELP_NOT_AVAILABLE);
        }
    }

    /**
     * Reports missing mandatory options by printing the command usage and failing the command.
     * Reached only when a command is invoked programmatically, since picocli rejects missing
     * required options before {@code execute()} runs.
     *
     * @param command      command name, e.g. {@code libgen}
     * @param helpFileName help file name within {@code cli-docs}, e.g. {@code libgen.help}
     * @return the exception to throw
     */
    static BLauncherException missingOptions(String command, String helpFileName) {
        StringBuilder stringBuilder = new StringBuilder();
        appendHelp(stringBuilder, helpFileName);
        return LauncherUtils.createLauncherException(
                "missing mandatory options for the 'edi " + command + "' command." + System.lineSeparator()
                        + System.lineSeparator() + stringBuilder);
    }

    /**
     * Runs the bundled EDI tool with the given arguments, streaming its output to the terminal.
     * Fails the command if the tool cannot be started or exits with a non-zero status.
     *
     * @param toolArgs arguments passed to the EDI tool, the first being the mode
     */
    static void runEdiTool(List<String> toolArgs) {
        Path toolJar = null;
        try {
            toolJar = extractEdiTool();
            List<String> command = new ArrayList<>(List.of("bal", "run", toolJar.toAbsolutePath().toString()));
            if (!toolArgs.isEmpty()) {
                command.add("--");
                command.addAll(toolArgs);
            }
            Process process = new ProcessBuilder(command).inheritIO().start();
            int exitCode = process.waitFor();
            if (exitCode != 0) {
                throw LauncherUtils.createLauncherException(
                        "the EDI tool failed with exit code " + exitCode + ".");
            }
        } catch (IOException e) {
            throw LauncherUtils.createLauncherException("failed to run the EDI tool: " + e.getMessage());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw LauncherUtils.createLauncherException("the EDI tool was interrupted: " + e.getMessage());
        } finally {
            if (toolJar != null) {
                try {
                    Files.deleteIfExists(toolJar);
                } catch (IOException e) {
                    // The jar is also registered for deletion on exit, so a failure here is not fatal.
                }
            }
        }
    }

    private static Path extractEdiTool() throws IOException {
        Path tempFile = Files.createTempFile(null, ".jar");
        tempFile.toFile().deleteOnExit();
        try (InputStream in = EdiCmdUtils.class.getClassLoader().getResourceAsStream(EDI_TOOL)) {
            if (in == null) {
                throw LauncherUtils.createLauncherException(
                        "the bundled EDI tool (" + EDI_TOOL + ") could not be found.");
            }
            Files.copy(in, tempFile, StandardCopyOption.REPLACE_EXISTING);
        }
        return tempFile;
    }
}
