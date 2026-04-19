import { describe, expect, it, vi } from "vitest";
import {
  StablecoinClient,
  calculateAnnualizedApy,
  ensureSufficientAllowance,
  waitForSuccessfulTransaction
} from "../src/stablecoin/StablecoinClient";
import { SDKError, SDKErrorCode, TransactionFailedError } from "../src/errors";
import {
  RedemptionStatus,
  TokenCategory,
  TrustLevel
} from "../src/stablecoin/types";

describe("calculateAnnualizedApy", () => {
  it("annualizes NAV growth without losing bigint precision", () => {
    const history = [
      { navPerShare: 1_000_000_000_000_000_000n, timestamp: 1_700_000_000n },
      { navPerShare: 1_000_000_000_000_001_000n, timestamp: 1_702_592_000n }
    ];

    const apy = calculateAnnualizedApy(history);

    expect(apy).toBeGreaterThan(0);
    expect(Math.abs(apy - 1.216666e-12)).toBeLessThan(1e-18);
  });

  it("returns zero for unusable history windows", () => {
    expect(calculateAnnualizedApy([])).toBe(0);
    expect(
      calculateAnnualizedApy([
        { navPerShare: 0n, timestamp: 1n },
        { navPerShare: 1n, timestamp: 2n }
      ])
    ).toBe(0);
    expect(
      calculateAnnualizedApy([
        { navPerShare: 1_000_000_000_000_000_000n, timestamp: 10n },
        { navPerShare: 1_100_000_000_000_000_000n, timestamp: 10n }
      ])
    ).toBe(0);
  });

  it("supports negative APY when NAV declines", () => {
    const history = [
      { navPerShare: 1_000_000_000_000_000_000n, timestamp: 0n },
      { navPerShare: 950_000_000_000_000_000n, timestamp: 31_536_000n }
    ];

    expect(calculateAnnualizedApy(history)).toBeCloseTo(-5, 8);
  });

  it("uses earliest and latest reports even when history is unsorted", () => {
    const history = [
      { navPerShare: 1_010_000_000_000_000_000n, timestamp: 1_702_592_000n },
      { navPerShare: 1_000_000_000_000_000_000n, timestamp: 1_700_000_000n },
      { navPerShare: 1_005_000_000_000_000_000n, timestamp: 1_701_000_000n }
    ];

    expect(calculateAnnualizedApy(history)).toBeCloseTo(12.166666666666666, 10);
  });
});

describe("StablecoinClient.getStats", () => {
  it("uses annualized APY math for NAV history", async () => {
    const client = Object.create(StablecoinClient.prototype) as StablecoinClient & Record<string, unknown>;

    client.ssUSD = {
      totalSupply: vi.fn().mockResolvedValue(5_000_000_000_000_000_000_000n),
      totalShares: vi.fn().mockResolvedValue(4_800_000_000_000_000_000_000n),
      getNavPerShare: vi.fn().mockResolvedValue(1_041_666_666_666_666_666n)
    };
    client.treasury = {
      getTotalCollateralValue: vi.fn().mockResolvedValue(5_200_000_000_000_000_000_000n),
      getCollateralRatio: vi.fn().mockResolvedValue(10_400n)
    };
    client.navOracle = {
      getNAVHistory: vi.fn().mockResolvedValue([
        { navPerShare: 1_000_000_000_000_000_000n, timestamp: 1_700_000_000n },
        { navPerShare: 1_010_000_000_000_000_000n, timestamp: 1_702_592_000n }
      ])
    };

    const stats = await client.getStats();

    expect(stats.totalSupply).toBe(5_000_000_000_000_000_000_000n);
    expect(stats.totalShares).toBe(4_800_000_000_000_000_000_000n);
    expect(stats.navPerShare).toBe(1_041_666_666_666_666_666n);
    expect(stats.totalCollateral).toBe(5_200_000_000_000_000_000_000n);
    expect(stats.collateralRatio).toBe(10_400n);
    expect(stats.apy).toBeCloseTo(12.166666666666666, 10);
  });
});

describe("waitForSuccessfulTransaction", () => {
  it("returns the receipt when the transaction succeeds", async () => {
    const receipt = { hash: "0xabc", status: 1 };

    await expect(
      waitForSuccessfulTransaction(
        {
          hash: "0xabc",
          wait: vi.fn().mockResolvedValue(receipt)
        },
        1,
        "wrap failed"
      )
    ).resolves.toBe(receipt);
  });

  it("throws TransactionFailedError when the receipt is missing or failed", async () => {
    await expect(
      waitForSuccessfulTransaction(
        {
          hash: "0xdead",
          wait: vi.fn().mockResolvedValue({ hash: "0xdead", status: 0 })
        },
        1,
        "wrap failed"
      )
    ).rejects.toBeInstanceOf(TransactionFailedError);
  });
});

describe("ensureSufficientAllowance", () => {
  it("skips approval when allowance is already sufficient", async () => {
    const contract = {
      allowance: vi.fn().mockResolvedValue(500n),
      approve: vi.fn()
    };

    await ensureSufficientAllowance(
      contract,
      "0x00000000000000000000000000000000000000aa",
      "0x00000000000000000000000000000000000000bb",
      400n,
      1,
      "approval failed"
    );

    expect(contract.approve).not.toHaveBeenCalled();
  });

  it("resets nonzero allowance before approving the required amount", async () => {
    const resetTx = {
      hash: "0xreset",
      wait: vi.fn().mockResolvedValue({ hash: "0xreset", status: 1 })
    };
    const approveTx = {
      hash: "0xapprove",
      wait: vi.fn().mockResolvedValue({ hash: "0xapprove", status: 1 })
    };
    const contract = {
      allowance: vi.fn().mockResolvedValue(100n),
      approve: vi.fn()
        .mockResolvedValueOnce(resetTx)
        .mockResolvedValueOnce(approveTx)
    };

    await ensureSufficientAllowance(
      contract,
      "0x00000000000000000000000000000000000000aa",
      "0x00000000000000000000000000000000000000bb",
      400n,
      1,
      "approval failed"
    );

    expect(contract.approve).toHaveBeenNthCalledWith(
      1,
      "0x00000000000000000000000000000000000000bb",
      0n
    );
    expect(contract.approve).toHaveBeenNthCalledWith(
      2,
      "0x00000000000000000000000000000000000000bb",
      400n
    );
  });
});

describe("StablecoinClient read helpers", () => {
  it("normalizes bigint enum fields returned by getRedemptionRequest", async () => {
    const client = Object.create(StablecoinClient.prototype) as StablecoinClient & Record<string, unknown>;

    client.treasury = {
      getRedemptionRequest: vi.fn().mockResolvedValue({
        id: 7n,
        requester: "0x00000000000000000000000000000000000000aa",
        ssUSDAmount: 250n,
        collateralToken: "0x00000000000000000000000000000000000000bb",
        requestedAt: 1000n,
        processedAt: 0n,
        status: 2n
      })
    };

    await expect(client.getRedemptionRequest(7n)).resolves.toEqual({
      id: 7n,
      requester: "0x00000000000000000000000000000000000000aa",
      ssUSDAmount: 250n,
      collateralToken: "0x00000000000000000000000000000000000000bb",
      requestedAt: 1000n,
      processedAt: 0n,
      status: RedemptionStatus.COMPLETED
    });
  });

  it("normalizes bigint token metadata fields returned by getTokenInfo", async () => {
    const client = Object.create(StablecoinClient.prototype) as StablecoinClient & Record<string, unknown>;

    client.tokenRegistry = {
      getTokenInfo: vi.fn().mockResolvedValue({
        tokenAddress: "0x00000000000000000000000000000000000000aa",
        name: "USD Coin",
        symbol: "USDC",
        decimals: 6n,
        logoURI: "ipfs://logo",
        category: 2n,
        trustLevel: 1n,
        isCollateral: true,
        addedAt: 10n,
        updatedAt: 11n
      })
    };

    await expect(
      client.getTokenInfo("0x00000000000000000000000000000000000000aa")
    ).resolves.toEqual({
      tokenAddress: "0x00000000000000000000000000000000000000aa",
      name: "USD Coin",
      symbol: "USDC",
      decimals: 6,
      logoURI: "ipfs://logo",
      category: TokenCategory.STABLECOIN,
      trustLevel: TrustLevel.VERIFIED,
      isCollateral: true,
      addedAt: 10n,
      updatedAt: 11n
    });
  });

  it("rejects out-of-range bigint metadata before coercing to number", async () => {
    const client = Object.create(StablecoinClient.prototype) as StablecoinClient & Record<string, unknown>;

    client.tokenRegistry = {
      getTokenInfo: vi.fn().mockResolvedValue({
        tokenAddress: "0x00000000000000000000000000000000000000aa",
        name: "USD Coin",
        symbol: "USDC",
        decimals: BigInt(Number.MAX_SAFE_INTEGER) + 1n,
        logoURI: "ipfs://logo",
        category: 2n,
        trustLevel: 1n,
        isCollateral: true,
        addedAt: 10n,
        updatedAt: 11n
      })
    };

    await expect(
      client.getTokenInfo("0x00000000000000000000000000000000000000aa")
    ).rejects.toMatchObject<Partial<SDKError>>({
      code: SDKErrorCode.VALIDATION_ERROR,
      message: expect.stringContaining("decimals exceeds safe integer range")
    });
  });
});
