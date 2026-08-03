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

import io.ballerina.cli.BLauncherCmd;
import io.ballerina.cli.launcher.BLauncherException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;
import picocli.CommandLine;

import java.io.ByteArrayOutputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.function.Supplier;
import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Tests that command failures are reported rather than silently swallowed: usage text is
 * produced, missing mandatory options are rejected, and a failing EDI tool run fails the command.
 */
class ErrorReportingTest {

    private static Stream<Arguments> commands() {
        return Stream.of(
                Arguments.of("codegen", (Supplier<BLauncherCmd>) CodegenCmd::new),
                Arguments.of("libgen", (Supplier<BLauncherCmd>) LibgenCmd::new),
                Arguments.of("convertESL", (Supplier<BLauncherCmd>) EslCmd::new),
                Arguments.of(
                        "convertX12Schema", (Supplier<BLauncherCmd>) ConvertX12Cmd::new),
                Arguments.of(
                        "convertEdifactSchema", (Supplier<BLauncherCmd>) ConvertEdifactCmd::new),
                Arguments.of("edi", (Supplier<BLauncherCmd>) EdiCmd::new));
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("commands")
    void testPrintUsageProducesHelpText(String name, Supplier<BLauncherCmd> factory) {
        StringBuilder stringBuilder = new StringBuilder();
        factory.get().printUsage(stringBuilder);

        String usage = stringBuilder.toString();
        assertFalse(usage.isBlank(), "printUsage produced no text for '" + name + "'");
        assertFalse(usage.contains("Helper text is not available."),
                "Help resource is missing for '" + name + "': " + usage);
        assertTrue(usage.contains("bal edi"), "Usage text for '" + name + "' looks wrong: " + usage);
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("commands")
    void testPrintLongDescProducesHelpText(String name, Supplier<BLauncherCmd> factory) {
        StringBuilder stringBuilder = new StringBuilder();
        factory.get().printLongDesc(stringBuilder);

        assertFalse(stringBuilder.toString().isBlank(),
                "printLongDesc appended nothing to the builder for '" + name + "'");
    }

    /**
     * {@code --help} must print the help text rather than complaining about the mandatory options
     * it was asking about. Declaring the options {@code required} without a {@code usageHelp}
     * option would make picocli reject the invocation before the command runs.
     */
    @ParameterizedTest(name = "{0}")
    @MethodSource("commands")
    void testHelpFlagPrintsHelpInsteadOfRequiringOptions(String name, Supplier<BLauncherCmd> factory) {
        PrintStream original = System.out;
        ByteArrayOutputStream captured = new ByteArrayOutputStream();
        System.setOut(new PrintStream(captured, true, StandardCharsets.UTF_8));
        try {
            // The commands capture System.out in their constructors
            BLauncherCmd cmd = factory.get();
            CommandLine.ParseResult parsed = new CommandLine(cmd).parseArgs("--help");
            assertTrue(parsed.isUsageHelpRequested(), "'--help' was not treated as a help request for " + name);
            cmd.execute();
        } finally {
            System.setOut(original);
        }
        String help = captured.toString(StandardCharsets.UTF_8);
        assertTrue(help.contains("bal edi"), "'--help' printed no usage for '" + name + "': " + help);
        assertFalse(help.contains("Helper text is not available."),
                "Help resource missing for '" + name + "'");
    }

    /**
     * Missing mandatory options must be rejected at parse time rather than producing a blank line.
     */
    @ParameterizedTest(name = "{0}")
    @MethodSource("incompleteInvocations")
    void testMissingMandatoryOptionsAreRejected(String name, Supplier<BLauncherCmd> factory, List<String> args) {
        CommandLine commandLine = new CommandLine(factory.get());
        assertThrows(CommandLine.MissingParameterException.class,
                () -> commandLine.parseArgs(args.toArray(new String[0])),
                "Missing mandatory options should be rejected for '" + name + "'");
    }

    private static Stream<Arguments> incompleteInvocations() {
        return Stream.of(
                Arguments.of(
                        "codegen without -o", (Supplier<BLauncherCmd>) CodegenCmd::new, List.of("-i", "schema.json")),
                Arguments.of(
                        "libgen without -p", (Supplier<BLauncherCmd>) LibgenCmd::new,
                        List.of("-i", "schemas", "-o", "out")),
                Arguments.of(
                        "convertESL without -b", (Supplier<BLauncherCmd>) EslCmd::new,
                        List.of("-i", "a.esl", "-o", "out.json")),
                Arguments.of(
                        "convertX12Schema without -o", (Supplier<BLauncherCmd>) ConvertX12Cmd::new,
                        List.of("-i", "a.xsd")),
                Arguments.of(
                        "convertEdifactSchema without -o", (Supplier<BLauncherCmd>) ConvertEdifactCmd::new,
                        List.of("-v", "d03a", "-t", "ORDERS")));
    }

    /**
     * Guards the defensive check inside execute(), reached only on programmatic invocation.
     */
    @Test
    void testExecuteWithoutOptionsFailsWithUsage() {
        BLauncherException e = assertThrows(BLauncherException.class, () -> new LibgenCmd().execute());
        String message = String.join("\n", e.getMessages());
        assertTrue(message.contains("missing mandatory options"), "Unexpected message: " + message);
        assertTrue(message.contains("bal edi libgen"), "Usage text was not included: " + message);
    }

    /**
     * A non-zero exit from the bundled EDI tool must fail the command instead of being discarded.
     */
    @Test
    void testFailingToolRunFailsTheCommand(@TempDir Path tempDir) {
        Path missingSchema = tempDir.resolve("does-not-exist.json");
        CodegenCmd cmd = new CodegenCmd();
        new CommandLine(cmd).parseArgs(
                "-i", missingSchema.toString(), "-o", tempDir.resolve("out.bal").toString());

        BLauncherException e = assertThrows(BLauncherException.class, cmd::execute,
                "A failing EDI tool run should fail the command");
        assertTrue(String.join("\n", e.getMessages()).contains("EDI tool failed"),
                "Unexpected failure message: " + e.getMessages());
        assertFalse(Files.exists(tempDir.resolve("out.bal")), "No output should be generated");
    }
}
