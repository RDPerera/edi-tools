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

import java.io.IOException;
import java.io.PrintStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.stream.Stream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

@CommandLine.Command(name = "convertEdifactSchema", description = "Converts EDIFACT schema to EDI schema.")
public class ConvertEdifactCmd implements BLauncherCmd {
    private static final String CMD_NAME = "convertEdifactSchema";
    private static final String HELP_FILE = "convertEDIfact.help";

    private final PrintStream printStream;

    @CommandLine.Option(names = { "-h", "--help" }, hidden = true, usageHelp = true)
    private boolean helpFlag;

    @CommandLine.Option(names = { "-v", "--version" }, required = true, description = "EDIFACT version")
    private String version;

    @CommandLine.Option(names = { "-t", "--type" }, description = "EDIFACT message type")
    private String type;

    @CommandLine.Option(names = { "-o", "--output" }, required = true,
            description = "EDIFACT schema directory path")
    private String dir;

    @CommandLine.Option(names = { "-i", "--input" },
            description = "UNECE EDIFACT directory archive or extracted directory")
    private String input;

    public ConvertEdifactCmd() {
        this.printStream = System.out;
    }

    @Override
    public void execute() {
        if (helpFlag) {
            EdiCmdUtils.printHelp(printStream, HELP_FILE);
            return;
        }
        if (version == null || dir == null) {
            throw EdiCmdUtils.missingOptions(CMD_NAME, HELP_FILE);
        }
        printStream.println("Generating EDI schema for EDIFACT schema ...");
        // A blank --input is treated as not supplied, so the conversion reports
        // where to download the directory instead of scanning the current directory.
        String inputPath = input == null ? "" : input.trim();
        Path extractedInput = null;
        try {
            String inputDir = "";
            if (!inputPath.isEmpty()) {
                Path source = Path.of(inputPath);
                if (!Files.exists(source)) {
                    throw LauncherUtils.createLauncherException(
                            "EDIFACT directory input '" + inputPath + "' does not exist.");
                }
                if (Files.isDirectory(source)) {
                    inputDir = source.toAbsolutePath().toString();
                } else {
                    extractedInput = Files.createTempDirectory("edifact-directory");
                    extractArchive(source, extractedInput);
                    inputDir = extractedInput.toString();
                }
            }
            EdiCmdUtils.runEdiTool(List.of(CMD_NAME, version, type == null ? "" : type, dir, inputDir));
        } catch (IOException e) {
            throw LauncherUtils.createLauncherException(
                    "failed to read the EDIFACT directory input '" + inputPath + "': " + e.getMessage());
        } finally {
            deleteRecursively(extractedInput);
        }
    }

    private void deleteRecursively(Path directory) {
        if (directory == null) {
            return;
        }
        try (Stream<Path> paths = Files.walk(directory)) {
            for (Path path : paths.sorted(Comparator.reverseOrder()).toList()) {
                Files.deleteIfExists(path);
            }
        } catch (IOException e) {
            printStream.println("Warning: could not delete " + directory + ". " + e.getMessage());
        }
    }

    /**
     * Extracts the given archive into the target directory. A UNECE release is an archive of archives:
     * the release archive holds the EDMD and EDSD archives, which in turn hold the batch files, so
     * nested archives are extracted as well and users do not have to unpack anything.
     */
    private void extractArchive(Path archive, Path target) throws IOException {
        List<Path> nestedArchives = new ArrayList<>();
        try (ZipInputStream zip = new ZipInputStream(Files.newInputStream(archive))) {
            ZipEntry entry;
            while ((entry = zip.getNextEntry()) != null) {
                if (entry.isDirectory()) {
                    continue;
                }
                Path extracted = resolveWithinTarget(target, entry.getName());
                Files.createDirectories(extracted.getParent());
                Files.copy(zip, extracted, StandardCopyOption.REPLACE_EXISTING);
                if (extracted.getFileName().toString().toLowerCase(Locale.ROOT).endsWith(".zip")) {
                    nestedArchives.add(extracted);
                }
            }
        }
        for (Path nested : nestedArchives) {
            String name = nested.getFileName().toString();
            Path nestedTarget = nested.resolveSibling(name.substring(0, name.length() - ".zip".length()));
            Files.createDirectories(nestedTarget);
            extractArchive(nested, nestedTarget);
        }
    }

    // Rejects archive entries that would be written outside the target directory.
    private Path resolveWithinTarget(Path target, String entryName) throws IOException {
        Path resolved = target.resolve(entryName).normalize();
        if (!resolved.startsWith(target)) {
            throw new IOException("Archive entry '" + entryName + "' resolves outside the extraction directory.");
        }
        return resolved;
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
