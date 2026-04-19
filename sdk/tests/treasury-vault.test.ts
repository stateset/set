import { describe, expect, it, vi } from "vitest";
import {
  batchCheckTreasuryVaultOperators,
  batchGetCollateralBalances,
  batchGetRedemptionRequests,
  getCollateralBreakdown,
  getRedemptionRequest,
  getRedemptionStatus
} from "../src/contracts/treasury-vault";
import { SDKErrorCode } from "../src/errors";

describe("treasury vault helpers", () => {
  it("maps aligned collateral breakdown and batch reads", async () => {
    const vault = {
      getCollateralBreakdown: vi.fn().mockResolvedValue([
        [
          "0x1000000000000000000000000000000000000001",
          "0x2000000000000000000000000000000000000002"
        ],
        [500n, 300n],
        [550n, 330n]
      ]),
      batchGetCollateralBalances: vi.fn().mockResolvedValue([500n, 300n]),
      batchIsOperator: vi.fn().mockResolvedValue([true, false])
    };

    await expect(getCollateralBreakdown(vault as any)).resolves.toEqual({
      tokens: [
        "0x1000000000000000000000000000000000000001",
        "0x2000000000000000000000000000000000000002"
      ],
      balances: [500n, 300n],
      values: [550n, 330n]
    });

    await expect(
      batchGetCollateralBalances(vault as any, [
        "0x1000000000000000000000000000000000000001",
        "0x2000000000000000000000000000000000000002"
      ])
    ).resolves.toEqual([500n, 300n]);

    await expect(
      batchCheckTreasuryVaultOperators(vault as any, [
        "0x3000000000000000000000000000000000000003",
        "0x4000000000000000000000000000000000000004"
      ])
    ).resolves.toEqual([true, false]);
  });

  it("normalizes bigint redemption status values", async () => {
    const vault = {
      getRedemptionStatus: vi.fn().mockResolvedValue([2n, 0n, true, 1_000_000_000_000_000_000n]),
      getRedemptionRequest: vi.fn().mockResolvedValue({
        id: 7n,
        requester: "0x1000000000000000000000000000000000000001",
        ssUSDAmount: 500n,
        collateralToken: "0x2000000000000000000000000000000000000002",
        requestedAt: 100n,
        processedAt: 200n,
        status: 3n
      }),
      batchGetRedemptionRequests: vi.fn().mockResolvedValue([{
        id: 8n,
        requester: "0x3000000000000000000000000000000000000003",
        ssUSDAmount: 600n,
        collateralToken: "0x4000000000000000000000000000000000000004",
        requestedAt: 101n,
        processedAt: 201n,
        status: 1n
      }])
    };

    await expect(getRedemptionStatus(vault as any, 7)).resolves.toEqual({
      status: 2,
      timeRemaining: 0n,
      isReady: true,
      ssUSDValue: 1_000_000_000_000_000_000n
    });

    await expect(getRedemptionRequest(vault as any, 7)).resolves.toMatchObject({
      status: 3
    });

    await expect(batchGetRedemptionRequests(vault as any, [8])).resolves.toMatchObject([
      { status: 1 }
    ]);
  });

  it("rejects malformed collateral and batch helper responses", async () => {
    const vault = {
      getCollateralBreakdown: vi.fn().mockResolvedValue([
        [
          "0x1000000000000000000000000000000000000001",
          "0x2000000000000000000000000000000000000002"
        ],
        [500n],
        [550n, 330n]
      ]),
      batchGetCollateralBalances: vi.fn().mockResolvedValue([500n]),
      batchGetRedemptionRequests: vi.fn().mockResolvedValue([]),
      batchIsOperator: vi.fn().mockResolvedValue([true])
    };

    await expect(getCollateralBreakdown(vault as any)).rejects.toMatchObject({
      code: SDKErrorCode.VALIDATION_ERROR,
      message: expect.stringContaining("getCollateralBreakdown returned balances length 1, expected 2")
    });

    await expect(
      batchGetCollateralBalances(vault as any, [
        "0x1000000000000000000000000000000000000001",
        "0x2000000000000000000000000000000000000002"
      ])
    ).rejects.toMatchObject({
      code: SDKErrorCode.VALIDATION_ERROR,
      message: expect.stringContaining("batchGetCollateralBalances returned balances length 1, expected 2")
    });

    await expect(batchGetRedemptionRequests(vault as any, [8])).rejects.toMatchObject({
      code: SDKErrorCode.VALIDATION_ERROR,
      message: expect.stringContaining("batchGetRedemptionRequests returned requests length 0, expected 1")
    });

    await expect(
      batchCheckTreasuryVaultOperators(vault as any, [
        "0x3000000000000000000000000000000000000003",
        "0x4000000000000000000000000000000000000004"
      ])
    ).rejects.toMatchObject({
      code: SDKErrorCode.VALIDATION_ERROR,
      message: expect.stringContaining("batchIsOperator returned statuses length 1, expected 2")
    });
  });

  it("rejects out-of-range redemption status values", async () => {
    const vault = {
      getRedemptionStatus: vi.fn().mockResolvedValue([
        BigInt(Number.MAX_SAFE_INTEGER) + 1n,
        0n,
        false,
        0n
      ])
    };

    await expect(getRedemptionStatus(vault as any, 7)).rejects.toMatchObject({
      code: SDKErrorCode.VALIDATION_ERROR,
      message: expect.stringContaining("status exceeds safe integer range")
    });
  });
});
