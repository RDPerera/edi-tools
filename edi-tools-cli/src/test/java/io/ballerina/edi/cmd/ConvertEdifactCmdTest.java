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

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import picocli.CommandLine;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.stream.Stream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

/**
 * Tests the convertEdifactSchema command end-to-end against a locally supplied EDIFACT directory.
 * The fixture under edifact/local is a hand written sample in the UNTDID layout, so these tests do
 * not depend on https://service.unece.org/ being reachable.
 */
class ConvertEdifactCmdTest {

    @Test
    void testConvertEdifactSchemaFromDirectory(@TempDir Path tempDir) throws Exception {
        Path directory = TestUtils.testResources().resolve("edifact/local/directory");
        Path expected = TestUtils.testResources().resolve("edifact/local/TESTMSG_expected.json");
        Path output = tempDir.resolve("TESTMSG.json");

        ConvertEdifactCmd cmd = new ConvertEdifactCmd();
        new CommandLine(cmd).parseArgs("-v", "d03a", "-t", "TESTMSG", "-i", directory.toString(),
                "-o", tempDir.toString());
        cmd.execute();

        TestUtils.assertJsonEquals(expected, output);
    }

    /**
     * A UNECE release is an archive holding the EDMD and EDSD archives, so the command has to unpack
     * both levels before the directory can be read.
     */
    @Test
    void testConvertEdifactSchemaFromReleaseArchive(@TempDir Path tempDir) throws Exception {
        Path directory = TestUtils.testResources().resolve("edifact/local/directory");
        Path expected = TestUtils.testResources().resolve("edifact/local/TESTMSG_expected.json");
        Path archive = tempDir.resolve("d03a.zip");
        writeReleaseArchive(directory, archive);
        Path outputDir = Files.createDirectory(tempDir.resolve("out"));

        ConvertEdifactCmd cmd = new ConvertEdifactCmd();
        new CommandLine(cmd).parseArgs("-v", "d03a", "-t", "TESTMSG", "-i", archive.toString(),
                "-o", outputDir.toString());
        cmd.execute();

        TestUtils.assertJsonEquals(expected, outputDir.resolve("TESTMSG.json"));
    }

    // Packs the fixture the way UNECE distributes a release: EDMD.ZIP and EDSD.ZIP, each holding the
    // batch files, inside one release archive.
    private static void writeReleaseArchive(Path directory, Path archive) throws IOException {
        try (ZipOutputStream release = new ZipOutputStream(Files.newOutputStream(archive))) {
            for (String batch : List.of("EDMD", "EDSD")) {
                release.putNextEntry(new ZipEntry("Edifact/Directory/Files/" + batch + ".ZIP"));
                release.write(zipDirectory(directory.resolve(batch)));
                release.closeEntry();
            }
        }
    }

    private static byte[] zipDirectory(Path directory) throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        try (ZipOutputStream zip = new ZipOutputStream(bytes)) {
            try (Stream<Path> files = Files.list(directory)) {
                for (Path file : files.toList()) {
                    zip.putNextEntry(new ZipEntry(file.getFileName().toString()));
                    zip.write(Files.readAllBytes(file));
                    zip.closeEntry();
                }
            }
        }
        return bytes.toByteArray();
    }
}
