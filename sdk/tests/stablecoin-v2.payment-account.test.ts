import { describe, expect, it } from "vitest";
import { AbiCoder, Interface, id } from "ethers";
import { agentPaymentAccountV2Abi } from "../src/stablecoin/v2/index.js";

describe("restricted payment account ABI", () => {
  const abi = new Interface(agentPaymentAccountV2Abi);
  it("encodes all authorization-bound payment fields", () => {
    const fields = [id("order-1"), 3n, 7n, 1_000_000n, 1_000_001n, 1_800_000_000n];
    const wire = abi.encodeFunctionData("pay", fields);
    expect(wire.slice(0, 10)).toBe(id("pay(bytes32,uint256,uint256,uint256,uint256,uint40)").slice(0, 10));
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
