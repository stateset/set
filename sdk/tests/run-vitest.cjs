"use strict";

const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const MIN_NODE_MAJOR = 20;
const DEFAULT_DOCKER_IMAGE = "node:20-bookworm-slim";

function parseMajor(version) {
  const [major] = String(version || "").split(".");
  const parsed = Number(major);
  return Number.isFinite(parsed) ? parsed : 0;
}

function resolveNodeRuntime() {
  const currentMajor = parseMajor(process.versions.node);
  if (currentMajor >= MIN_NODE_MAJOR) {
    return { kind: "binary", value: process.execPath };
  }

  const candidates = new Set();
  if (process.env.SET_SDK_NODE_BIN) {
    candidates.add(process.env.SET_SDK_NODE_BIN);
  }
  if (process.env.HOME) {
    const nvmRoot = path.join(process.env.HOME, ".nvm/versions/node");
    if (fs.existsSync(nvmRoot)) {
      const nvmCandidates = fs.readdirSync(nvmRoot)
        .sort((left, right) => parseMajor(right.replace(/^v/, "")) - parseMajor(left.replace(/^v/, "")))
        .map((version) => path.join(nvmRoot, version, "bin/node"));
      for (const candidate of nvmCandidates) {
        candidates.add(candidate);
      }
    }
  }
  candidates.add("node22");
  candidates.add("node20");

  for (const candidate of candidates) {
    const probe = spawnSync(candidate, ["-e", "process.stdout.write(process.versions.node)"], {
      encoding: "utf8"
    });

    if (probe.status !== 0) {
      continue;
    }

    if (parseMajor(probe.stdout) >= MIN_NODE_MAJOR) {
      return { kind: "binary", value: candidate };
    }
  }

  if (process.env.SET_SDK_DISABLE_DOCKER !== "1") {
    const dockerProbe = spawnSync("docker", ["--version"], { encoding: "utf8" });
    if (dockerProbe.status === 0) {
      return {
        kind: "docker",
        image: process.env.SET_SDK_NODE_IMAGE || DEFAULT_DOCKER_IMAGE
      };
    }
  }

  console.error(
    `Vitest requires Node ${MIN_NODE_MAJOR}+; current runtime is ${process.versions.node}. ` +
    `Install Node ${MIN_NODE_MAJOR}+, set SET_SDK_NODE_BIN to a newer node binary, ` +
    `or allow Docker fallback with SET_SDK_NODE_IMAGE.`
  );
  process.exit(1);
}

const runtime = resolveNodeRuntime();
const sdkRoot = path.resolve(__dirname, "..");
const polyfillPath = path.resolve(__dirname, "polyfill-crypto.cjs");
const vitestEntrypoint = path.resolve(__dirname, "../node_modules/vitest/vitest.mjs");
const args = process.argv.slice(2);
let child;

if (runtime.kind === "binary") {
  child = spawnSync(runtime.value, ["-r", polyfillPath, vitestEntrypoint, ...args], {
    stdio: "inherit"
  });
} else {
  console.error(
    `Local Node ${MIN_NODE_MAJOR}+ not found; running Vitest via Docker image ${runtime.image}.`
  );

  const dockerArgs = ["run", "--rm"];
  if (process.stdin.isTTY && process.stdout.isTTY) {
    dockerArgs.push("-it");
  }
  dockerArgs.push(
    "-v",
    `${sdkRoot}:/workspace`,
    "-w",
    "/workspace",
    runtime.image,
    "node",
    "-r",
    "tests/polyfill-crypto.cjs",
    "node_modules/vitest/vitest.mjs",
    ...args
  );

  child = spawnSync("docker", dockerArgs, {
    stdio: "inherit"
  });
}

if (child.error) {
  console.error(child.error.message);
  process.exit(1);
}

process.exit(child.status ?? 1);
