import { afterEach, describe, expect, it } from "vitest";
import { createServer, type Server } from "node:http";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { id, JsonRpcProvider } from "ethers";
import { inspectTransactionFinality, verifyERC20Payment } from "../src/index.js";

const servers: Server[] = [];
const providers: JsonRpcProvider[] = [];
const tx = "0x" + "ab".repeat(32);
const hash = "0x" + "cd".repeat(32);
const token = "0x" + "11".repeat(20);
const payer = "0x" + "22".repeat(20);
const recipient = "0x" + "33".repeat(20);
const directories: string[] = [];
const driver = fileURLToPath(new URL("./fixtures/payment-ledger-driver.py", import.meta.url));

function database() {
  const directory = mkdtempSync(join(tmpdir(), "set-commerce-e2e-"));
  directories.push(directory);
  return (request: Record<string, unknown>) => {
    const result = spawnSync("python3", [driver, join(directory, "ledger.sqlite")], {
      input: JSON.stringify(request), encoding: "utf8", timeout: 10000
    });
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error(result.stderr);
    return JSON.parse(result.stdout);
  };
}

async function node(chain = "0xa", amount = 1_000_000n) {
  const server = createServer(async (request, response) => {
    let data = "";
    for await (const chunk of request) data += chunk;
    const payload = JSON.parse(data);
    let result: unknown;
    switch (payload.method) {
      case "eth_chainId": result = chain; break;
      case "eth_getTransactionReceipt":
        result = { transactionHash: tx, blockHash: hash, blockNumber: "0x1", status: "0x1", logs: [{
          transactionHash: tx, blockHash: hash, blockNumber: "0x1", logIndex: "0x7", removed: false,
          address: token, topics: [id("Transfer(address,address,uint256)"),
            "0x" + "0".repeat(24) + payer.slice(2), "0x" + "0".repeat(24) + recipient.slice(2)],
          data: "0x" + amount.toString(16).padStart(64, "0")
        }] };
        break;
      case "eth_getBlockByNumber": result = { hash, number: "0x1" }; break;
      default: throw new Error("Unexpected method");
    }
    response.setHeader("Content-Type", "application/json");
    response.end(JSON.stringify({ jsonrpc: "2.0", id: payload.id, result }));
  });
  servers.push(server);
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const address = server.address();
  if (!address || typeof address === "string") throw new Error("Missing listener");
  const provider = new JsonRpcProvider(`http://127.0.0.1:${address.port}`, undefined,
    { batchMaxCount: 1, cacheTimeout: -1 });
  providers.push(provider);
  return provider;
}

afterEach(async () => {
  for (const provider of providers.splice(0)) provider.destroy();
  await Promise.all(servers.splice(0).map(server => new Promise<void>(resolve => {
    server.closeAllConnections();
    server.close(() => resolve());
  })));
  for (const directory of directories.splice(0)) rmSync(directory, { recursive: true, force: true });
});

describe("commerce RPC-to-ledger integration", () => {
  const terms = { chain_id: "10", token, payer, recipient, amount: "1000000" };
  const expected = { chainId: 10n, transactionHash: tx, logIndex: 7n, token, payer, recipient, amount: 1_000_000n };

  // This case starts a fresh interpreter and fsyncs SQLite for each operation.
  // Allow bounded headroom under full-suite load, retaining each process timeout.
  it("credits once and survives a crash after fulfillment before acknowledgment", async () => {
    const db = database();
    db({ action: "create", order_id: "order-1", terms });
    db({ action: "create", order_id: "order-2", terms });
    const verification = await verifyERC20Payment([await node(), await node()], expected);
    expect(verification.status).toBe("verified");
    expect(db({ action: "credit", order_id: "order-1", verification })).toBe("credited");
    // Every database operation is a fresh Python process / SQLite connection.
    expect(db({ action: "credit", order_id: "order-1", verification })).toBe("already_credited");
    expect(() => db({ action: "credit", order_id: "order-2", verification })).toThrow("already consumed");
    expect(db({ action: "counts" })).toEqual({ credits: 1, fulfillment_outbox: 1 });
    const first = db({ action: "claim" });
    expect(db({ action: "deliver", ...first })).toBe(1);
    db({ action: "expire" });
    const retry = db({ action: "claim" });
    expect(retry.lease_token).not.toBe(first.lease_token);
    expect(db({ action: "deliver", ...retry })).toBe(1);
    expect(() => db({ action: "ack", ...first })).toThrow("Lease expired");
    expect(db({ action: "ack", ...retry })).toBe("acknowledged");
    expect(db({ action: "claim" })).toBeNull();
  }, 20000);

  it("never credits an underpayment returned through real HTTP transport", async () => {
    const db = database();
    db({ action: "create", order_id: "order-1", terms });
    const verification = await verifyERC20Payment([await node("0xa", 999999n), await node("0xa", 999999n)], expected);
    expect(verification.status).toBe("rejected");
    expect(() => db({ action: "credit", order_id: "order-1", verification })).toThrow("verification required");
    expect(db({ action: "counts" })).toEqual({ credits: 0, fulfillment_outbox: 0 });
  });
});

describe("finality observer through ethers JSON-RPC transport", () => {
  it("corroborates a finalized successful receipt across two local servers", async () => {
    const observation = await inspectTransactionFinality([await node(), await node()], tx, 10n);
    expect(observation).toMatchObject({ finality: "finalized", execution: "succeeded", sources: 2 });
  });

  it("rejects a verifier serving another chain", async () => {
    await expect(inspectTransactionFinality([await node(), await node("0x1")], tx, 10n))
      .rejects.toThrow("chain ID");
  });
});
