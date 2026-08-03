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

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.PrintStream;
import java.net.URL;
import java.nio.charset.StandardCharsets;
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
    private final PrintStream printStream;

    @CommandLine.Option(names = { "-v", "--version" }, description = "EDIFACT version")
    private String version;

    @CommandLine.Option(names = { "-t", "--type" }, description = "EDIFACT message type")
    private String type;

    @CommandLine.Option(names = { "-o", "--output" }, description = "EDIFACT schema directory path")
    private String dir;

    @CommandLine.Option(names = { "-i", "--input" },
            description = "UNECE EDIFACT directory archive or extracted directory")
    private String input;

    public ConvertEdifactCmd() {
        this.printStream = System.out;
    }

    @Override
    public void execute() {
        if (version == null || dir == null) {
            StringBuilder stringBuilder = new StringBuilder();
            printUsage(stringBuilder);
            printStream.println(stringBuilder.toString());
            return;
        }
        Path toolJar = null;
        Path extractedInput = null;
        try {
            printStream.println("Generating EDI schema for EDIFACT schema ...");
            // A blank --input is treated as not supplied, so the conversion reports
            // where to download the directory instead of scanning the current directory.
            String inputPath = input == null ? "" : input.trim();
            String inputDir = "";
            if (!inputPath.isEmpty()) {
                Path source = Path.of(inputPath);
                if (!Files.exists(source)) {
                    throw new IOException("EDIFACT directory input '" + inputPath + "' does not exist.");
                }
                if (Files.isDirectory(source)) {
                    inputDir = source.toAbsolutePath().toString();
                } else {
                    extractedInput = Files.createTempDirectory("edifact-directory");
                    extractArchive(source, extractedInput);
                    inputDir = extractedInput.toString();
                }
            }
            URL res = ConvertEdifactCmd.class.getClassLoader().getResource("editools.jar");
            toolJar = Files.createTempFile(null, ".jar");
            try (InputStream in = res.openStream()) {
                Files.copy(in, toolJar, StandardCopyOption.REPLACE_EXISTING);
            }
            ProcessBuilder processBuilder = new ProcessBuilder(
                    "bal", "run", toolJar.toAbsolutePath().toString(), "--", CMD_NAME, version, type == null ? "" : type,
                    dir, inputDir);
            processBuilder.inheritIO();
            Process process = processBuilder.start();
            process.waitFor();
            java.io.InputStream is = process.getInputStream();
            byte b[] = new byte[is.available()];
            is.read(b, 0, b.length);
            printStream.println(new String(b));
        } catch (Exception e) {
            printStream.println("Error in generating edi schema for edifact schema. " + e.getMessage());
            e.printStackTrace();
        } finally {
            delete(toolJar);
            deleteRecursively(extractedInput);
        }
    }

    private void delete(Path file) {
        if (file == null) {
            return;
        }
        try {
            Files.deleteIfExists(file);
        } catch (IOException e) {
            printStream.println("Warning: could not delete " + file + ". " + e.getMessage());
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
        Class<?> clazz = EdiCmd.class;
        ClassLoader classLoader = clazz.getClassLoader();
        InputStream inputStream = classLoader.getResourceAsStream("cli-docs/convertEDIfact.help");
        if (inputStream != null) {
            try (InputStreamReader inputStreamREader = new InputStreamReader(inputStream, StandardCharsets.UTF_8);
                    BufferedReader br = new BufferedReader(inputStreamREader)) {
                String content = br.readLine();
                printStream.append(content);
                while ((content = br.readLine()) != null) {
                    printStream.append('\n').append(content);
                }
            } catch (IOException e) {
                printStream.println("Helper text is not available.");
            }
        }
    }

    @Override
    public void printUsage(StringBuilder stringBuilder) {
    }

    @Override
    public void setParentCmdParser(CommandLine commandLine) {
    }
}
