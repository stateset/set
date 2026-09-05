import { describe, expect, it } from "vitest";
import { AbiCoder, Interface, id, TypedDataEncoder, Wallet, verifyTypedData, ZeroAddress, ZeroHash, keccak256, concat } from "ethers";
import { agentPaymentAccountV2Abi, buildMerchantInvoiceTypedData } from "../src/stablecoin/v2/index.js";

describe("restricted payment account ABI", () => {
  const abi = new Interface(agentPaymentAccountV2Abi);
  it("encodes all authorization-bound payment fields", () => {
    const fields = [id("order-1"), 3n, 7n, 1_000_000n, 1_000_001n, 1_800_000_000n, "0x1234"];
    const wire = abi.encodeFunctionData("pay", fields);
    expect(wire.slice(0, 10)).toBe(id("pay(bytes32,uint256,uint256,uint256,uint256,uint40,bytes)").slice(0, 10));
    expect(Array.from(abi.decodeFunctionData("pay", wire))).toEqual(fields);
  });
  it("decodes the Solidity session layout", () => {
    const fields = ["0x" + "11".repeat(20), 1_800_000_000n, 2_000_000n, 3n];
    const wire = AbiCoder.defaultAbiCoder().encode(["address", "uint40", "uint256", "uint256"], fields);
    expect(Array.from(abi.decodeFunctionResult("sessions", wire))).toEqual(fields);
  });
  it("does not expose arbitrary execution or approvals", () => {
    expect(abi.getFunction("execute")).toBeNull();
    expect(abi.getFunction("approve")).toBeNull();
  });
});

describe("merchant invoice typed data", () => {
  const invoice = {
    chainId: 84532001n, accountAddress: "0x" + "11".repeat(20),
    merchant: "0x" + "22".repeat(20), vault: "0x" + "33".repeat(20),
    orderId: id("merchant-order-1"), assets: 1_000_000n, deadline: 1_800_000_000n,
  };
  const hash = (input = invoice) => {
    const data = buildMerchantInvoiceTypedData(input);
    return TypedDataEncoder.hash(data.domain, data.types, data.value);
  };

  it("matches Solidity's independently encoded domain and invoice digest", () => {
    const coder = AbiCoder.defaultAbiCoder();
    const domain = keccak256(coder.encode(["bytes32", "bytes32", "bytes32", "uint256", "address"], [
      id("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
      id("AgentPaymentAccountV2"), id("1"), invoice.chainId, invoice.accountAddress,
    ]));
    const body = keccak256(coder.encode(["bytes32", "bytes32", "address", "address", "uint256", "uint40"], [
      id("Invoice(bytes32 orderId,address merchant,address vault,uint256 assets,uint40 deadline)"),
      invoice.orderId, invoice.merchant, invoice.vault, invoice.assets, invoice.deadline,
    ]));
    expect(hash()).toBe(keccak256(concat(["0x1901", domain, body])));
  });

  it("supports merchant signing through the standard ethers signer API", async () => {
    const merchant = Wallet.createRandom();
    const data = buildMerchantInvoiceTypedData({ ...invoice, merchant: merchant.address });
    const signature = await merchant.signTypedData(data.domain, data.types, data.value);
    expect(verifyTypedData(data.domain, data.types, data.value, signature)).toBe(merchant.address);
  });

  it.each([
    { chainId: 1n }, { accountAddress: "0x" + "44".repeat(20) },
    { merchant: "0x" + "55".repeat(20) }, { vault: "0x" + "66".repeat(20) },
    { orderId: id("different-order") }, { assets: 2n }, { deadline: 1_800_000_001n },
  ])("binds every domain and invoice field (case %#)", (change) => {
    expect(hash({ ...invoice, ...change })).not.toBe(hash());
  });

  it.each([
    { assets: 0n }, { assets: -1n }, { assets: 1n << 256n },
    { chainId: 0n }, { chainId: 1n << 256n },
    { deadline: 0n }, { deadline: 1n << 40n }, { deadline: 1 as any },
    { orderId: ZeroHash }, { orderId: "0x1234" },
    { accountAddress: ZeroAddress }, { merchant: ZeroAddress }, { vault: ZeroAddress },
    { merchant: invoice.accountAddress },
  ])("rejects malformed or out-of-range invoices (case %#)", (change) => {
    expect(() => buildMerchantInvoiceTypedData({ ...invoice, ...change })).toThrow();
  });

  it("returns isolated schemas and values for each call", () => {
    const data = buildMerchantInvoiceTypedData(invoice);
    data.types.Invoice[0].name = "tampered";
    data.value.assets = 2n;
    expect(buildMerchantInvoiceTypedData(invoice).types.Invoice[0].name).toBe("orderId");
    expect(buildMerchantInvoiceTypedData(invoice).value.assets).toBe(invoice.assets);
  });
});
