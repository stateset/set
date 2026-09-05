#!/usr/bin/env node
// Read-only local diagnostic. Never submits transactions or changes node state.
import { inspectTransactionFinality } from "../dist/index.js";

const [tx, chain, ...endpoints] = process.argv.slice(2);
try {
  if (!tx || !chain || !/^[1-9][0-9]*$/.test(chain) || endpoints.length !== 2) {
    throw new Error("Usage: node sdk/scripts/observe-local-finality.mjs TX_HASH CHAIN_ID LOCAL_RPC LOCAL_VERIFIER_RPC");
  }
  const urls = endpoints.map(endpoint => {
    const url = new URL(endpoint);
    if (url.protocol !== "http:" || !["127.0.0.1", "[::1]"].includes(url.hostname) ||
        url.username || url.password || url.search || url.hash || url.pathname !== "/") {
      throw new Error("Use credential-free numeric loopback HTTP endpoints with no path or query");
    }
    return url.href;
  });
  if (new Set(urls).size !== 2) throw new Error("Two distinct local endpoints are required");
  let id = 0;
  const providers = urls.map(url => ({ async send(method, params) {
    const requestId = ++id;
    const response = await fetch(url, {
      method: "POST", redirect: "error", signal: AbortSignal.timeout(10000),
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: requestId, method, params })
    });
    if (!response.ok) throw new Error("RPC HTTP failure");
    const body = await response.json();
    if (!body || body.jsonrpc !== "2.0" || body.id !== requestId ||
        Object.hasOwn(body, "error") || !Object.hasOwn(body, "result")) {
      throw new Error("Malformed or failed JSON-RPC response");
    }
    return body.result;
  } }));
  const observation = await inspectTransactionFinality(providers, tx, BigInt(chain));
  console.log(JSON.stringify(observation, null, 2));
  if (observation.finality !== "finalized" || observation.execution !== "succeeded") process.exitCode = 1;
} catch (error) {
  console.error(error instanceof Error ? error.message : "Finality observation failed");
  process.exitCode = 1;
}
