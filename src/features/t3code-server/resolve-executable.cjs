#!/usr/bin/env node
"use strict";

// Prints the executable that should run the T3 Code server for the package
// installed at argv[2].
//
// The npm `t3` package ships `bin/t3.js`, a Node shim that spawns a
// platform-specific binary from an `@t3code/t3-<platform>-<arch>` optional
// dependency and does not forward signals to it. Under s6 that shim is the
// supervised process, so a restart kills the shim and orphans the server, which
// keeps the port. For packages that declare those platform binaries the
// launcher execs the binary directly. Packages without them, such as the
// wyrd-company/t3code fork, run the server in-process from their own bin.

const { dirname, join } = require("node:path");

const packageDir = process.argv[2];
const fallback = process.argv[3];
const prefix = "@t3code/t3-";

const manifest = require(join(packageDir, "package.json"));
const declaresPlatformBinaries = Object.keys(manifest.optionalDependencies || {}).some((name) =>
    name.startsWith(prefix),
);

if (!declaresPlatformBinaries) {
    process.stdout.write(fallback);
    process.exit(0);
}

const platformPackage = prefix + process.platform + "-" + process.arch;
let platformDir;
try {
    platformDir = dirname(require.resolve(platformPackage + "/package.json", { paths: [packageDir] }));
} catch {
    process.stderr.write(`ERROR: ${packageDir} declares platform binaries but ${platformPackage} is not installed.\n`);
    process.exit(1);
}

process.stdout.write(join(platformDir, process.platform === "win32" ? "t3.exe" : "t3"));
