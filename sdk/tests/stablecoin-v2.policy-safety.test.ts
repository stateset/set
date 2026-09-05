import { describe, expect, it, vi } from "vitest";
import { AbiCoder, Interface, JsonRpcProvider, JsonRpcSigner, VoidSigner } from "ethers";
import { AgentClient, AgentErrorCode, createAgentClient } from "../src/stablecoin/v2/AgentClient.js";
import { ssdcPolicyModuleV2Abi } from "../src/stablecoin/v2/abis.js";
import type { SSDCV2Addresses } from "../src/stablecoin/v2/types.js";

const address = "0x" + "11".repeat(20);
const addresses = Object.fromEntries([
  "vault", "gateway", "navController", "escrow", "claimQueue", "policyModule",
  "groundingRegistry", "paymaster", "bridge", "statusLens", "circuitBreaker", "settlementAsset",
].map(key => [key, address])) as unknown as SSDCV2Addresses;

function statusClient(revoked: boolean) {
  // Encode the actual Solidity struct getter order, independently of the SDK ABI.
  const wire = AbiCoder.defaultAbiCoder().encode(
    ["uint128", "uint128", "uint128", "uint128", "uint128", "uint40", "uint40", "bool", "bool"],
    [100n, 200n, 10n, 20n, 30n, 1_700_000_000n, 0n, true, true],
  );
  const raw = new Interface(ssdcPolicyModuleV2Abi).decodeFunctionResult("policies", wire);
  const client = Object.create(AgentClient.prototype) as any;
  client.signer = { getAddress: vi.fn().mockResolvedValue(address) };
  client.vault = { balanceOf: vi.fn().mockResolvedValue(1000n) };
  client.paymaster = { gasTankShares: vi.fn().mockResolvedValue(0n) };
  client.policyModule = {
    policies: vi.fn().mockResolvedValue(raw),
    policyRevoked: vi.fn().mockResolvedValue(revoked),
  };
  client.groundingRegistry = {
    isGroundedNow: vi.fn().mockResolvedValue(false),
    currentAssets: vi.fn().mockResolvedValue([1000n, 50n, 10n ** 27n]),
  };
  client.transfer = vi.fn();
  client.assetsToShares = vi.fn();
  return client;
}

describe("policy wire format and revocation", () => {
  it("decodes packed getter fields in Solidity declaration order", async () => {
    const status = await statusClient(false).getStatus();
    expect(status.policy).toMatchObject({
      perTxLimitAssets: 100n, dailyLimitAssets: 200n, spentTodayAssets: 10n,
      minAssetsFloor: 20n, committedAssets: 30n, dayStart: 1_700_000_000,
      sessionExpiry: 0, enforceMerchantAllowlist: true, exists: true,
    });
    expect(status.policyRevoked).toBe(false);
    expect(status.sessionActive).toBe(true);
  });

  it("reports no available spend for a revoked unexpired policy", async () => {
    expect(await statusClient(true).getStatus()).toMatchObject({
      policyRevoked: true, availableSpend: 0n, sessionActive: false,
    });
  });

  it("rejects revoked pay before conversion or submission", async () => {
    const client = statusClient(true);
    await expect(client.pay(address, 1n)).rejects.toMatchObject({ code: AgentErrorCode.POLICY_REVOKED });
    expect(client.assetsToShares).not.toHaveBeenCalled();
    expect(client.transfer).not.toHaveBeenCalled();
  });
});

describe("externally managed agent signer", () => {
  it("accepts a provider-connected JSON-RPC signer without a private key", async () => {
    const provider = new JsonRpcProvider("http://127.0.0.1:1");
    const send = vi.spyOn(provider, "send");
    const signer = new JsonRpcSigner(provider, address);
    try {
      const client = createAgentClient({ addresses, signer });
      expect(await client.address).toBe(address);
      expect(send).not.toHaveBeenCalled();
    } finally {
      provider.destroy();
    }
  });

  it("rejects disconnected signers", () => {
    expect(() => createAgentClient({ addresses, signer: new VoidSigner(address) }))
      .toThrow("requires a provider");
  });

  it("snapshots deployment addresses instead of following later caller mutations", () => {
    const provider = new JsonRpcProvider("http://127.0.0.1:1");
    try {
      const configured = { ...addresses };
      const client = createAgentClient({ addresses: configured, signer: new JsonRpcSigner(provider, address) });
      configured.gateway = "0x" + "22".repeat(20);
      expect((client as any).addresses.gateway).toBe(address);
    } finally {
      provider.destroy();
    }
  });

  it("rejects ambiguous signer and private-key options", () => {
    expect(() => createAgentClient({ addresses, signer: new VoidSigner(address), privateKey: "not-a-key" } as any))
      .toThrow("not both");
  });
});
