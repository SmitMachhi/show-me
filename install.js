#!/usr/bin/env node
// What `npx show-me-cli` and `bunx show-me-cli` run. It starts the installer for this
// system: install.ps1 on Windows, install.sh on Linux and macOS.
// npm only delivers the installer. show-me itself goes on the PATH as one native program,
// because each npm or Bun command shim adds 12 ms to 260 ms to every show-me command.
const { spawnSync } = require("child_process");
const path = require("path");

const windows = process.platform === "win32";
const script = path.join(__dirname, windows ? "install.ps1" : "install.sh");
const run = windows
    ? spawnSync("powershell", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script], { stdio: "inherit" })
    : spawnSync("sh", [script], { stdio: "inherit" });
process.exit(run.status ?? 1);
