import { beforeEach, describe, expect, it, vi } from "vitest";

const contractRegistry = vi.hoisted(() => new Map<string, any>());

vi.mock("ethers", async () => {
  const actual = await vi.importActual<typeof import("ethers")>("ethers");

  return {
    ...actual,
    Contract: vi.fn((address: string) => {
      const contract = contractRegistry.get(address);
      if (!contract) {
        throw new Error(`Missing mock contract for ${address}`);
      }
      return contract;
    })
  };
});

import { Interface } from "ethers";
import { StablecoinClient } from "../src/stablecoin/StablecoinClient";
import {
  treasuryVaultAbi,
  wssUSDAbi,
  ssUSDAbi,
  tokenRegistryAbi,
  navOracleAbi
} from "../src/stablecoin/abis";
import {
  EventParseError,
  RedemptionsPausedError,
  TransactionFailedError
} from "../src/errors";

const ADDRESSES = {
  tokenRegistry: "0x0000000000000000000000000000000000000101",
  navOracle: "0x0000000000000000000000000000000000000102",
  ssUSD: "0x0000000000000000000000000000000000000103",
  wssUSD: "0x0000000000000000000000000000000000000104",
  treasury: "0x0000000000000000000000000000000000000105",
  collateral: "0x0000000000000000000000000000000000000106",
  user: "0x0000000000000000000000000000000000000201",
  recipient: "0x0000000000000000000000000000000000000202"
} as const;

function createReceipt(
  iface: Interface,
  eventName: string,
  args: readonly unknown[],
  address: string,
  hash: string
) {
  const fragment = iface.getEvent(eventName);
  const encoded = iface.encodeEventLog(fragment, args);

  return {
    hash,
    status: 1,
    logs: [
      {
        address,
        topics: encoded.topics,
        data: encoded.data
      }
    ]
  };
}

function createTx(
  hash: string,
  receipt: ReturnType<typeof createReceipt> | ReturnType<typeof createStatusReceipt>
) {
  return {
    hash,
    wait: vi.fn().mockResolvedValue(receipt)
  };
}

function createStatusReceipt(hash: string, status: number, logs: unknown[] = []) {
  return {
    hash,
    status,
    logs
  };
}

function createWriteMock(tx: unknown, gasEstimate: bigint = 1_000n) {
  const fn = vi.fn().mockResolvedValue(tx);
  Object.assign(fn, {
    estimateGas: vi.fn().mockResolvedValue(gasEstimate)
  });
  return fn;
}

function createBaseClient() {
  const provider = {
    getFeeData: vi.fn().mockResolvedValue({
      gasPrice: 1_000_000_000n,
      maxFeePerGas: 1_500_000_000n,
      maxPriorityFeePerGas: 100_000_000n
    })
  };
  const signer = {
    provider,
    getAddress: vi.fn().mockResolvedValue(ADDRESSES.user)
  };

  const tokenRegistry = {
    interface: new Interface(tokenRegistryAbi),
    isApprovedCollateral: vi.fn().mockResolvedValue(true)
  };
  const navOracle = {
    interface: new Interface(navOracleAbi)
  };
  const ssUSD = {
    interface: new Interface(ssUSDAbi),
    runner: { provider },
    balanceOf: vi.fn().mockResolvedValue(1_000_000_000_000_000_000_000n),
    allowance: vi.fn().mockResolvedValue(0n),
    approve: vi.fn()
  };
  const wssUSD = {
    interface: new Interface(wssUSDAbi),
    runner: { provider },
    balanceOf: vi.fn().mockResolvedValue(1_000_000_000_000_000_000_000n),
    getSSDCValue: vi.fn().mockResolvedValue(0n),
    wrap: createWriteMock(undefined),
    unwrap: createWriteMock(undefined)
  };
  const treasury = {
    interface: new Interface(treasuryVaultAbi),
    runner: { provider },
    depositsPaused: vi.fn().mockResolvedValue(false),
    redemptionsPaused: vi.fn().mockResolvedValue(false),
    deposit: createWriteMock(undefined),
    requestRedemption: createWriteMock(undefined),
    cancelRedemption: vi.fn()
  };
  const collateral = {
    interface: new Interface(ssUSDAbi),
    runner: { provider },
    balanceOf: vi.fn().mockResolvedValue(1_000_000n),
    allowance: vi.fn().mockResolvedValue(0n),
    approve: vi.fn()
  };

  contractRegistry.set(ADDRESSES.tokenRegistry, tokenRegistry);
  contractRegistry.set(ADDRESSES.navOracle, navOracle);
  contractRegistry.set(ADDRESSES.ssUSD, ssUSD);
  contractRegistry.set(ADDRESSES.wssUSD, wssUSD);
  contractRegistry.set(ADDRESSES.treasury, treasury);
  contractRegistry.set(ADDRESSES.collateral, collateral);

  const client = new StablecoinClient(ADDRESSES, signer as any);

  return {
    client,
    signer,
    provider,
    tokenRegistry,
    navOracle,
    ssUSD,
    wssUSD,
    treasury,
    collateral
  };
}

beforeEach(() => {
  contractRegistry.clear();
});

describe("StablecoinClient flow methods", () => {
  it("deposit resets nonzero collateral allowance, estimates gas, and returns minted ssUSD", async () => {
    const { client, treasury, collateral } = createBaseClient();

    collateral.allowance.mockResolvedValue(50n);
    const resetTx = { hash: "0xreset", wait: vi.fn().mockResolvedValue({ hash: "0xreset", status: 1 }) };
    const approveTx = { hash: "0xapprove", wait: vi.fn().mockResolvedValue({ hash: "0xapprove", status: 1 }) };
    collateral.approve
      .mockResolvedValueOnce(resetTx)
      .mockResolvedValueOnce(approveTx);

    const depositReceipt = createReceipt(
      treasury.interface,
      "Deposited",
      [ADDRESSES.user, ADDRESSES.collateral, 100n, 95n, ADDRESSES.recipient],
      ADDRESSES.treasury,
      "0xdeposit"
    );
    const depositTx = createTx("0xdeposit", depositReceipt);
    treasury.deposit = createWriteMock(depositTx, 1_000n);

    const result = await client.deposit(ADDRESSES.collateral, 100n, ADDRESSES.recipient);

    expect(collateral.approve).toHaveBeenNthCalledWith(1, ADDRESSES.treasury, 0n);
    expect(collateral.approve).toHaveBeenNthCalledWith(2, ADDRESSES.treasury, 100n);
    expect(treasury.deposit).toHaveBeenCalledWith(
      ADDRESSES.collateral,
      100n,
      ADDRESSES.recipient,
      { gasLimit: 1_200n }
    );
    expect(result).toEqual({
      txHash: "0xdeposit",
      ssUSDMinted: 95n
    });
  });

  it("requestRedemption throws early when redemptions are paused", async () => {
    const { client, treasury, ssUSD } = createBaseClient();
    treasury.redemptionsPaused.mockResolvedValue(true);

    await expect(
      client.requestRedemption(100n, ADDRESSES.collateral)
    ).rejects.toBeInstanceOf(RedemptionsPausedError);

    expect(ssUSD.approve).not.toHaveBeenCalled();
    expect(treasury.requestRedemption).not.toHaveBeenCalled();
  });

  it("wrap ensures approval, applies buffered gas, and parses the wrapped amount", async () => {
    const { client, ssUSD, wssUSD } = createBaseClient();

    ssUSD.allowance.mockResolvedValue(0n);
    const approveTx = { hash: "0xapprove", wait: vi.fn().mockResolvedValue({ hash: "0xapprove", status: 1 }) };
    ssUSD.approve.mockResolvedValueOnce(approveTx);

    const wrapReceipt = createReceipt(
      wssUSD.interface,
      "Wrapped",
      [ADDRESSES.user, 250n, 240n],
      ADDRESSES.wssUSD,
      "0xwrap"
    );
    const wrapTx = createTx("0xwrap", wrapReceipt);
    wssUSD.wrap = createWriteMock(wrapTx, 2_000n);

    const result = await client.wrap(250n);

    expect(ssUSD.approve).toHaveBeenCalledWith(ADDRESSES.wssUSD, 250n);
    expect(wssUSD.wrap).toHaveBeenCalledWith(250n, { gasLimit: 2_400n });
    expect(result).toEqual({
      txHash: "0xwrap",
      wssUSDReceived: 240n
    });
  });

  it("unwrap applies buffered gas and parses the returned ssUSD amount", async () => {
    const { client, wssUSD } = createBaseClient();

    const unwrapReceipt = createReceipt(
      wssUSD.interface,
      "Unwrapped",
      [ADDRESSES.user, 240n, 250n],
      ADDRESSES.wssUSD,
      "0xunwrap"
    );
    const unwrapTx = createTx("0xunwrap", unwrapReceipt);
    wssUSD.unwrap = createWriteMock(unwrapTx, 1_500n);

    const result = await client.unwrap(240n);

    expect(wssUSD.unwrap).toHaveBeenCalledWith(240n, { gasLimit: 1_800n });
    expect(result).toEqual({
      txHash: "0xunwrap",
      ssUSDReceived: 250n
    });
  });

  it("deposit surfaces event parse failures when the expected mint event is missing", async () => {
    const { client, treasury, collateral } = createBaseClient();

    const approveTx = {
      hash: "0xapprove",
      wait: vi.fn().mockResolvedValue({ hash: "0xapprove", status: 1 })
    };
    collateral.approve.mockResolvedValueOnce(approveTx);

    const depositTx = createTx(
      "0xdeposit-missing-event",
      createStatusReceipt("0xdeposit-missing-event", 1, [])
    );
    treasury.deposit = createWriteMock(depositTx, 1_000n);

    await expect(
      client.deposit(ADDRESSES.collateral, 100n, ADDRESSES.recipient)
    ).rejects.toBeInstanceOf(EventParseError);
  });

  it("requestRedemption surfaces event parse failures when the request event is missing", async () => {
    const { client, treasury, ssUSD } = createBaseClient();

    const approveTx = {
      hash: "0xapprove",
      wait: vi.fn().mockResolvedValue({ hash: "0xapprove", status: 1 })
    };
    ssUSD.approve.mockResolvedValueOnce(approveTx);

    const redemptionTx = createTx(
      "0xredemption-missing-event",
      createStatusReceipt("0xredemption-missing-event", 1, [])
    );
    treasury.requestRedemption = createWriteMock(redemptionTx, 1_000n);

    await expect(
      client.requestRedemption(100n, ADDRESSES.collateral)
    ).rejects.toBeInstanceOf(EventParseError);
  });

  it("wrap fails with TransactionFailedError when the wrapped event is missing", async () => {
    const { client, ssUSD, wssUSD } = createBaseClient();

    const approveTx = {
      hash: "0xapprove",
      wait: vi.fn().mockResolvedValue({ hash: "0xapprove", status: 1 })
    };
    ssUSD.approve.mockResolvedValueOnce(approveTx);

    const wrapTx = createTx(
      "0xwrap-missing-event",
      createStatusReceipt("0xwrap-missing-event", 1, [])
    );
    wssUSD.wrap = createWriteMock(wrapTx, 2_000n);

    await expect(client.wrap(250n)).rejects.toBeInstanceOf(TransactionFailedError);
  });

  it("cancelRedemption fails with TransactionFailedError when the receipt status is unsuccessful", async () => {
    const { client, treasury } = createBaseClient();

    treasury.cancelRedemption = vi.fn().mockResolvedValue({
      hash: "0xcancel",
      wait: vi.fn().mockResolvedValue(createStatusReceipt("0xcancel", 0))
    });

    await expect(client.cancelRedemption(7n)).rejects.toBeInstanceOf(TransactionFailedError);
  });
});
