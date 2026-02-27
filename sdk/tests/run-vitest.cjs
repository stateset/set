"use strict";

const { spawnSync } = require("child_process");
const path = require("path");

const MIN_NODE_MAJOR = 18;

function parseMajor(version) {
  const [major] = String(version || "").split(".");
  const parsed = Number(major);
  return Number.isFinite(parsed) ? parsed : 0;
}

function resolveNodeBin() {
  const currentMajor = parseMajor(process.versions.node);
  if (currentMajor >= MIN_NODE_MAJOR) {
    return process.execPath;
  }

  const candidates = [];
  if (process.env.SET_SDK_NODE_BIN) {
    candidates.push(process.env.SET_SDK_NODE_BIN);
  }
  if (process.env.HOME) {
    candidates.push(path.join(process.env.HOME, ".nvm/versions/node/v20.20.0/bin/node"));
  }
  candidates.push("node20", "node18");

  for (const candidate of candidates) {
    const probe = spawnSync(candidate, ["-e", "process.stdout.write(process.versions.node)"], {
      encoding: "utf8"
    });

    if (probe.status !== 0) {
      continue;
    }

    if (parseMajor(probe.stdout) >= MIN_NODE_MAJOR) {
      return candidate;
    }
  }

  console.error(
    `Vitest requires Node ${MIN_NODE_MAJOR}+; current runtime is ${process.versions.node}. ` +
    "Install Node 18+ or set SET_SDK_NODE_BIN to a newer node binary."
  );
  process.exit(1);
}

const nodeBin = resolveNodeBin();
const polyfillPath = path.resolve(__dirname, "polyfill-crypto.cjs");
const vitestEntrypoint = path.resolve(__dirname, "../node_modules/vitest/vitest.mjs");
const args = process.argv.slice(2);

const child = spawnSync(nodeBin, ["-r", polyfillPath, vitestEntrypoint, ...args], {
  stdio: "inherit"
});

if (child.error) {
  console.error(child.error.message);
  process.exit(1);
}

process.exit(child.status ?? 1);
