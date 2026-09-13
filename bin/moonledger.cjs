#!/usr/bin/env node
"use strict";
// Node supplies bounded local IO and process output. All CSV/decimal/matching
// logic is compiled from MoonBit. No network requests or file writes.
const fs = require("node:fs");
const path = require("node:path");
const { TextDecoder } = require("node:util");
const MAX_BYTES = 8 * 1024 * 1024;
let inputPath = "";
globalThis.moonledgerHost = {
  readInput(file) {
    inputPath = file;
    const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NONBLOCK);
    try {
      const stat = fs.fstatSync(fd);
      if (!stat.isFile()) throw Object.assign(new Error("Input must be a regular file"), {code:"not_regular_file"});
      if (stat.size > MAX_BYTES) throw Object.assign(new Error("Input exceeds 8 MiB"), {code:"input_too_large"});
      const buffer = Buffer.alloc(MAX_BYTES + 1);
      let size = 0, n;
      while (size <= MAX_BYTES && (n = fs.readSync(fd, buffer, size, buffer.length - size, null)) > 0) size += n;
      if (size > MAX_BYTES) throw Object.assign(new Error("Input exceeds 8 MiB"), {code:"input_too_large"});
      try {
        return new TextDecoder("utf-8", {fatal:true, ignoreBOM:true}).decode(buffer.subarray(0,size));
      } catch {
        throw Object.assign(new Error("Input must be valid UTF-8"), {code:"invalid_utf8"});
      }
    } finally { fs.closeSync(fd); }
  },
  finish(json, summary, code) {
    if (json) process.stdout.write(json + "\n");
    if (summary) process.stderr.write(summary + "\n");
    process.exitCode = code;
  }
};
try {
  require(path.join(__dirname, "../_build/js/release/build/cmd/main/main.js"));
} catch (error) {
  const diagnostic = {schema:"moonledger.error/1",error:{
    code:error.code || "runtime_error",file:inputPath,record:0,line:0,
    message:error.message || String(error)
  }};
  process.stdout.write(JSON.stringify(diagnostic) + "\n");
  process.stderr.write(diagnostic.error.code + ": " + diagnostic.error.message + "\n");
  process.exitCode = 2;
} finally {
  delete globalThis.moonledgerHost;
}
