import { describe, expect, it, vi } from "vitest";
import {
  EncryptedMempoolClient,
  EncryptedTxStatus,
  MEVProtectionClient,
  ThresholdEncryption
} from "../src/encryption";
import { SDKErrorCode } from "../src/errors";

describe("EncryptedMempoolClient", () => {
  it("rejects failed submission receipts", async () => {
    const encryptSpy = vi
      .spyOn(ThresholdEncryption, "encrypt")
      .mockReturnValue(`0x${"11".repeat(64)}`);
    const client = Object.create(EncryptedMempoolClient.prototype) as EncryptedMempoolClient & {
      keyRegistry: {
        getCurrentEpoch: ReturnType<typeof vi.fn>;
        getCurrentPublicKey: ReturnType<typeof vi.fn>;
      };
      contract: {
        submitEncryptedTx: ReturnType<typeof vi.fn>;
      };
    };

    client.keyRegistry = {
      getCurrentEpoch: vi.fn().mockResolvedValue(1n),
      getCurrentPublicKey: vi.fn().mockResolvedValue(`0x${"22".repeat(32)}`),
    };
    client.contract = {
      submitEncryptedTx: vi.fn().mockResolvedValue({
        hash: "0xsubmitfail",
        wait: vi.fn().mockResolvedValue({ hash: "0xsubmitfail", status: 0, logs: [] }),
      }),
    };

    await expect(client.submitEncryptedTransaction({
      to: "0x1000000000000000000000000000000000000001",
      data: "0x",
      value: 0n,
    })).rejects.toMatchObject({
      code: SDKErrorCode.TRANSACTION_FAILED,
      message: expect.stringContaining("Encrypted transaction submission failed"),
    });

    encryptSpy.mockRestore();
  });

  it("rejects failed cancellation receipts", async () => {
    const client = Object.create(EncryptedMempoolClient.prototype) as EncryptedMempoolClient & {
      contract: {
        cancelEncryptedTx: ReturnType<typeof vi.fn>;
      };
    };

    client.contract = {
      cancelEncryptedTx: vi.fn().mockResolvedValue({
        hash: "0xcancelfail",
        wait: vi.fn().mockResolvedValue({ hash: "0xcancelfail", status: 0 }),
      }),
    };

    await expect(client.cancelTransaction(`0x${"ab".repeat(32)}`)).rejects.toMatchObject({
      code: SDKErrorCode.TRANSACTION_FAILED,
      message: expect.stringContaining("Encrypted transaction cancellation failed"),
    });
  });

  it("normalizes bigint transaction status values", async () => {
    const client = Object.create(EncryptedMempoolClient.prototype) as EncryptedMempoolClient & {
      contract: {
        getEncryptedTx: ReturnType<typeof vi.fn>;
      };
    };

    client.contract = {
      getEncryptedTx: vi.fn().mockResolvedValue({
        id: `0x${"aa".repeat(32)}`,
        sender: "0x1000000000000000000000000000000000000001",
        encryptedPayload: `0x${"11".repeat(64)}`,
        payloadHash: `0x${"22".repeat(32)}`,
        epoch: 1n,
        gasLimit: 200000n,
        maxFeePerGas: 1000000000n,
        valueDeposit: 0n,
        submittedAt: 123n,
        orderPosition: 1n,
        status: 4n,
      }),
    };

    await expect(client.getTransaction(`0x${"aa".repeat(32)}`)).resolves.toMatchObject({
      status: EncryptedTxStatus.Executed,
    });
  });

  it("rejects out-of-range bigint transaction status values", async () => {
    const client = Object.create(EncryptedMempoolClient.prototype) as EncryptedMempoolClient & {
      contract: {
        getEncryptedTx: ReturnType<typeof vi.fn>;
      };
    };

    client.contract = {
      getEncryptedTx: vi.fn().mockResolvedValue({
        id: `0x${"aa".repeat(32)}`,
        sender: "0x1000000000000000000000000000000000000001",
        encryptedPayload: `0x${"11".repeat(64)}`,
        payloadHash: `0x${"22".repeat(32)}`,
        epoch: 1n,
        gasLimit: 200000n,
        maxFeePerGas: 1000000000n,
        valueDeposit: 0n,
        submittedAt: 123n,
        orderPosition: 1n,
        status: BigInt(Number.MAX_SAFE_INTEGER) + 1n,
      }),
    };

    await expect(client.getTransaction(`0x${"aa".repeat(32)}`)).rejects.toMatchObject({
      code: SDKErrorCode.VALIDATION_ERROR,
      message: expect.stringContaining("status exceeds safe integer range"),
    });
  });

  it("rejects unknown encrypted transaction status codes", async () => {
    const client = Object.create(EncryptedMempoolClient.prototype) as EncryptedMempoolClient & {
      contract: {
        getEncryptedTx: ReturnType<typeof vi.fn>;
      };
    };

    client.contract = {
      getEncryptedTx: vi.fn().mockResolvedValue({
        id: `0x${"aa".repeat(32)}`,
        sender: "0x1000000000000000000000000000000000000001",
        encryptedPayload: `0x${"11".repeat(64)}`,
        payloadHash: `0x${"22".repeat(32)}`,
        epoch: 1n,
        gasLimit: 200000n,
        maxFeePerGas: 1000000000n,
        valueDeposit: 0n,
        submittedAt: 123n,
        orderPosition: 1n,
        status: 99n,
      }),
    };

    await expect(client.getTransaction(`0x${"aa".repeat(32)}`)).rejects.toMatchObject({
      code: SDKErrorCode.VALIDATION_ERROR,
      message: expect.stringContaining("status is not a valid encrypted transaction status"),
    });
  });
});

describe("MEVProtectionClient", () => {
  it("returns terminal failed status even when decrypted details are unavailable", async () => {
    const client = Object.create(MEVProtectionClient.prototype) as MEVProtectionClient & {
      mempool: {
        getTransaction: ReturnType<typeof vi.fn>;
        getDecryptedTransaction: ReturnType<typeof vi.fn>;
      };
    };

    client.mempool = {
      getTransaction: vi.fn().mockResolvedValue({
        status: EncryptedTxStatus.Failed,
      }),
      getDecryptedTransaction: vi.fn().mockRejectedValue(new Error("decrypted tx not found")),
    };

    await expect(client.getTransactionStatus(`0x${"aa".repeat(32)}`)).resolves.toEqual({
      status: "Failed",
      executed: false,
      success: false,
    });
  });

  it("returns decrypted execution details when they are available", async () => {
    const client = Object.create(MEVProtectionClient.prototype) as MEVProtectionClient & {
      mempool: {
        getTransaction: ReturnType<typeof vi.fn>;
        getDecryptedTransaction: ReturnType<typeof vi.fn>;
      };
    };

    client.mempool = {
      getTransaction: vi.fn().mockResolvedValue({
        status: EncryptedTxStatus.Executed,
      }),
      getDecryptedTransaction: vi.fn().mockResolvedValue({
        executed: true,
        success: true,
      }),
    };

    await expect(client.getTransactionStatus(`0x${"bb".repeat(32)}`)).resolves.toEqual({
      status: "Executed",
      executed: true,
      success: true,
    });
  });
});
