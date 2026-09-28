import { describe, expect, it } from "vitest";
import { AbiCoder, Interface, TypedDataEncoder, Wallet, ZeroAddress, ZeroHash, concat, id, keccak256, verifyTypedData } from "ethers";
import * as SDK from "../src/index.js";
import {
  arbiterRegistryAbi,
  buildProtectedPaymentTypedData,
  protectedPaymentsAbi,
} from "../src/protection/index.js";

const terms = {
  chainId: 84532001n,
  contractAddress: "0x" + "11".repeat(20),
  buyer: "0x" + "22".repeat(20),
  merchant: "0x" + "33".repeat(20),
  token: "0x" + "44".repeat(20),
  amount: 1_000_000_000n,
  arbiter: "0x" + "55".repeat(20),
  fulfillBy: 1_800_000_000n,
  protectionWindow: 2_592_000n,
  orderRef: id("order-1"),
  deadline: 1_799_000_000n,
};

const hash = (input = terms) => {
  const data = buildProtectedPaymentTypedData(input);
  return TypedDataEncoder.hash(data.domain, data.types, data.value);
};

describe("protected payment typed data", () => {
  it("matches the Solidity EIP-712 encoding", () => {
    const coder = AbiCoder.defaultAbiCoder();
    const domain = keccak256(coder.encode(["bytes32", "bytes32", "bytes32", "uint256", "address"], [
      id("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
      id("SetProtectedPayments"), id("1"), terms.chainId, terms.contractAddress,
    ]));
    const body = keccak256(coder.encode(
      ["bytes32", "address", "address", "address", "uint128", "address", "uint64", "uint32", "bytes32", "uint64"],
      [
        id("PaymentTerms(address buyer,address merchant,address token,uint128 amount,address arbiter,uint64 fulfillBy,uint32 protectionWindow,bytes32 orderRef,uint64 deadline)"),
        terms.buyer, terms.merchant, terms.token, terms.amount, terms.arbiter,
        terms.fulfillBy, terms.protectionWindow, terms.orderRef, terms.deadline,
      ],
    ));
    expect(hash()).toBe(keccak256(concat(["0x1901", domain, body])));
  });

  it("signs with the standard ethers signer API", async () => {
    const merchant = Wallet.createRandom();
    const data = buildProtectedPaymentTypedData({ ...terms, merchant: merchant.address });
    const sig = await merchant.signTypedData(data.domain, data.types, data.value);
    expect(verifyTypedData(data.domain, data.types, data.value, sig)).toBe(merchant.address);
  });

  it("allows open offers and default arbiters", () => {
    expect(() => buildProtectedPaymentTypedData({ ...terms, buyer: ZeroAddress, arbiter: ZeroAddress })).not.toThrow();
  });

  it.each([
    { chainId: 1n }, { contractAddress: "0x" + "66".repeat(20) }, { buyer: ZeroAddress },
    { token: "0x" + "77".repeat(20) }, { amount: 2n }, { arbiter: ZeroAddress },
    { fulfillBy: 1_800_000_001n }, { protectionWindow: 1n }, { orderRef: id("order-2") }, { deadline: 1n },
  ])("binds every field (case %#)", (change) => {
    expect(hash({ ...terms, ...change })).not.toBe(hash());
  });

  it.each([
    { amount: 0n }, { amount: 1n << 128n }, { protectionWindow: 1n << 32n }, { fulfillBy: 1n << 64n },
    { deadline: 0n }, { orderRef: ZeroHash }, { orderRef: "0x12" },
    { merchant: ZeroAddress }, { token: ZeroAddress }, { contractAddress: ZeroAddress },
    { buyer: terms.merchant }, { arbiter: terms.merchant }, { arbiter: terms.buyer },
  ])("rejects malformed terms (case %#)", (change) => {
    expect(() => buildProtectedPaymentTypedData({ ...terms, ...change })).toThrow();
  });
});

describe("protected payment ABIs", () => {
  it("parse and expose the dispute lifecycle", () => {
    const pp = new Interface(protectedPaymentsAbi);
    for (const fn of ["pay", "openDispute", "contest", "resolve", "proposeSettlement", "arbiterTimeout", "claimPending", "withdraw"]) {
      expect(pp.getFunction(fn)).not.toBeNull();
    }
    expect(pp.getFunction("pay")!.selector).toBe(
      id("pay((address,address,address,uint128,address,uint64,uint32,bytes32,uint64),bytes)").slice(0, 10),
    );
    expect(new Interface(arbiterRegistryAbi).getFunction("isEligible")).not.toBeNull();
  });

  it("is exported from the package root", () => {
    expect(SDK.protection.buildProtectedPaymentTypedData).toBe(buildProtectedPaymentTypedData);
  });
});
