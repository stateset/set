#!/usr/bin/env node
/**
 * End-to-end protected payments on a throwaway Anvil chain.
 *
 * Deploys MockSsUSD, ArbiterRegistry and ProtectedPayments from compiled Foundry
 * artifacts, then drives three disputes through ProtectedPaymentsClient:
 *
 *   1. Instant settlement, then a chargeback 20 days after the merchant was paid
 *   2. Contested dispute resolved by a bonded arbiter with a partial refund
 *   3. Merchant ignores a dispute; anyone executes the buyer-favoring default
 *
 * Usage (from sdk/):
 *   npm run build
 *   ARTIFACTS_DIR=../contracts/out_ar node examples/protected-payments-e2e.mjs
 *
 * ARTIFACTS_DIR must contain MockSsUSD.sol/, ArbiterRegistry.sol/ and
 * ProtectedPayments.sol/ (any Foundry profile). Needs `anvil` on PATH.
 */

import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { ContractFactory, JsonRpcProvider, NonceManager, Wallet, formatUnits, id, parseUnits } from "ethers";
import {
  ProtectedDisputeReason,
  ProtectedPaymentsClient,
} from "../dist/protection/index.js";

const ARTIFACTS = path.resolve(process.env.ARTIFACTS_DIR ?? "../contracts/out_ar");
const PORT = Number(process.env.ANVIL_PORT ?? 8547);
const RPC = `http://127.0.0.1:${PORT}`;
const DAY = 86_400;
const u = (n) => parseUnits(String(n), 6);
const fmt = (v) => formatUnits(v, 6).padStart(10);
const c = { dim: "\x1b[2m", g: "\x1b[32m", y: "\x1b[33m", b: "\x1b[36m", r: "\x1b[0m" };

// Anvil's default mnemonic accounts.
const KEYS = [
  "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", // admin
  "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d", // buyer
  "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a", // merchant
  "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6", // arbiter
];

function artifact(file, name) {
  const p = path.join(ARTIFACTS, file, `${name}.json`);
  if (!fs.existsSync(p)) throw new Error(`missing artifact ${p}; build the contracts first`);
  const j = JSON.parse(fs.readFileSync(p, "utf8"));
  return { abi: j.abi, bytecode: j.bytecode.object };
}

async function startAnvil() {
  const proc = spawn("anvil", ["--port", String(PORT), "--silent"], { stdio: "ignore" });
  // Probe with raw RPC: an ethers provider created before the node is up keeps
  // retrying network detection, and its calls wait on that indefinitely.
  const body = JSON.stringify({ jsonrpc: "2.0", id: 1, method: "eth_chainId", params: [] });
  for (let i = 0; i < 300; i++) {
    try {
      const res = await fetch(RPC, { method: "POST", headers: { "content-type": "application/json" }, body });
      const { result } = await res.json();
      const provider = new JsonRpcProvider(RPC, Number(result), { staticNetwork: true, cacheTimeout: -1 });
      return { proc, provider };
    } catch {
      await new Promise((r) => setTimeout(r, 100));
    }
  }
  proc.kill();
  throw new Error("anvil did not start");
}

async function main() {
  const { proc, provider } = await startAnvil();
  try {
    const [admin, buyer, merchant, arbiter] = KEYS.map((k) => new NonceManager(new Wallet(k, provider)));
    const addr = {
      admin: await admin.getAddress(),
      buyer: await buyer.getAddress(),
      merchant: await merchant.getAddress(),
      arbiter: await arbiter.getAddress(),
    };
    const warp = async (secs) => {
      await provider.send("evm_increaseTime", [secs]);
      await provider.send("evm_mine", []);
    };
    const now = async () => BigInt((await provider.getBlock("latest")).timestamp);

    // ── deploy ────────────────────────────────────────────────────────────
    const deploy = async (file, name, args, signer = admin) => {
      const a = artifact(file, name);
      const contract = await new ContractFactory(a.abi, a.bytecode, signer).deploy(...args);
      await contract.waitForDeployment();
      return contract;
    };
    const token = await deploy("MockSsUSD.sol", "MockSsUSD", []);
    const tokenAddr = await token.getAddress();
    const registry = await deploy("ArbiterRegistry.sol", "ArbiterRegistry", [tokenAddr, addr.admin, u(500), u(100), 14 * DAY, addr.admin]);
    const pp = await deploy("ProtectedPayments.sol", "ProtectedPayments", [
      await registry.getAddress(), addr.admin, addr.admin,
      [1 * DAY, 120 * DAY, 3 * DAY, 7 * DAY, 90, 100],
    ]);
    const ppAddr = await pp.getAddress();
    const tx = async (p) => (await p).wait();

    await tx(registry.grantRole(await registry.COURT_ROLE(), ppAddr));
    await tx(pp.setTokenConfig(tokenAddr, [true, 100, 50, u(25), u(20)]));
    await tx(registry.setApproved(addr.arbiter, true));
    for (const [who, amt] of [[addr.buyer, 10_000], [addr.merchant, 10_000], [addr.arbiter, 500]]) {
      await tx(token.mint(who, u(amt)));
    }
    await tx(token.connect(arbiter).approve(await registry.getAddress(), u(500)));
    await tx(registry.connect(arbiter).depositBond(u(500)));

    const asBuyer = new ProtectedPaymentsClient(ppAddr, buyer);
    const asMerchant = new ProtectedPaymentsClient(ppAddr, merchant);
    const asArbiter = new ProtectedPaymentsClient(ppAddr, arbiter);

    console.log(`\n${c.b}Protected Payments — end to end${c.r}  ${c.dim}(Anvil :${PORT})${c.r}`);
    console.log(`${c.dim}ProtectedPayments ${ppAddr}\nArbiterRegistry   ${await registry.getAddress()}${c.r}`);

    let order = 0;
    const offer = async (amount) => {
      const terms = {
        buyer: addr.buyer, merchant: addr.merchant, token: tokenAddr, amount: u(amount), arbiter: addr.arbiter,
        fulfillBy: (await now()) + BigInt(7 * DAY), protectionWindow: BigInt(30 * DAY),
        orderRef: id(`demo-order-${++order}`), deadline: (await now()) + 3600n,
      };
      return { terms, sig: await asMerchant.signTerms(merchant, terms) };
    };
    const balances = async (label) => {
      const [b, m, a, reserve] = await Promise.all([
        token.balanceOf(addr.buyer), token.balanceOf(addr.merchant), token.balanceOf(addr.arbiter),
        asMerchant.getReserve(addr.merchant, tokenAddr),
      ]);
      console.log(`  ${c.dim}${label.padEnd(34)}${c.r} buyer ${fmt(b)}  merchant ${fmt(m)}  arbiter ${fmt(a)}  reserve free/locked ${formatUnits(reserve.free, 6)}/${formatUnits(reserve.locked, 6)}`);
    };
    const withdrawAll = async () => {
      for (const client of [asBuyer, asMerchant, asArbiter]) {
        const who = client === asBuyer ? addr.buyer : client === asMerchant ? addr.merchant : addr.arbiter;
        if ((await client.getCredits(tokenAddr, who)) > 0n) await client.withdraw(tokenAddr);
      }
    };

    // ── 1. instant settlement + chargeback after payout ───────────────────
    console.log(`\n${c.g}1. Instant settlement, chargeback 20 days after payout${c.r}`);
    await tx(pp.setMerchantRisk(addr.merchant, true, 2000));
    await asMerchant.depositReserve(tokenAddr, u(1000));
    await balances("start");
    let { terms, sig } = await offer(1000);
    const p1 = (await asBuyer.pay(terms, sig)).paymentId;
    const info1 = await asBuyer.getPayment(p1);
    console.log(`  paid 1000 → instant=${info1.instant}, reserve locked ${formatUnits(info1.reserveLocked, 6)}`);
    await balances("merchant paid immediately");
    await asMerchant.markFulfilled(p1, id("tracking:1Z999"));
    await warp(20 * DAY);
    console.log(`  buyer actions now: ${(await asBuyer.actionsFor(p1, addr.buyer)).actions.join(", ")}`);
    await asBuyer.openDispute(p1, ProtectedDisputeReason.DEFECTIVE, u(400), id("photos-of-cracked-unit"));
    console.log(`  merchant actions: ${(await asMerchant.actionsFor(p1, addr.merchant)).actions.join(", ")}`);
    await asMerchant.acceptDispute(p1);
    await withdrawAll();
    await balances("after 400 chargeback (from reserve)");

    // ── 2. contested dispute, arbiter partial ruling ──────────────────────
    console.log(`\n${c.g}2. Contested dispute, arbiter rules a partial refund${c.r}`);
    await tx(pp.setMerchantRisk(addr.merchant, false, 0));
    ({ terms, sig } = await offer(800));
    const p2 = (await asBuyer.pay(terms, sig)).paymentId;
    await asMerchant.markFulfilled(p2, id("tracking:1Z888"));
    await asBuyer.openDispute(p2, ProtectedDisputeReason.NOT_AS_DESCRIBED, u(800), id("listing-said-blue"));
    await asMerchant.contest(p2, id("photos-show-blue"));
    console.log(`  arbiter actions: ${(await asArbiter.actionsFor(p2, addr.arbiter)).actions.join(", ")}`);
    await asArbiter.resolve(p2, u(200), id("ruling: shade mismatch, 25% refund"));
    await withdrawAll();
    await balances("after ruling (200 refund, fee→arbiter)");

    // ── 3. merchant silence → default ─────────────────────────────────────
    console.log(`\n${c.g}3. Merchant ignores the dispute; default refunds the buyer${c.r}`);
    ({ terms, sig } = await offer(300));
    const p3 = (await asBuyer.pay(terms, sig)).paymentId;
    await asBuyer.openDispute(p3, ProtectedDisputeReason.NOT_RECEIVED, u(300), id("no-package"));
    await warp(3 * DAY);
    await new ProtectedPaymentsClient(ppAddr, admin).executeDefault(p3);
    await withdrawAll();
    await balances("after default");

    const ms = await asBuyer.getMerchantStats(addr.merchant);
    const bs = await asBuyer.getBuyerStats(addr.buyer);
    console.log(`\n${c.y}Dispute record${c.r}  merchant ${ms.payments} payments / ${ms.disputes} disputes / ${ms.lost} lost (ratio ${ms.ratioBps} bps)` +
      `   buyer ${bs.payments} / ${bs.disputes} / ${bs.lost}`);
    console.log(`${c.dim}protection pool ${formatUnits(await pp.poolBalance(tokenAddr), 6)}  protocol fees ${formatUnits(await pp.protocolFeesAccrued(tokenAddr), 6)}${c.r}\n`);
  } finally {
    proc.kill();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
