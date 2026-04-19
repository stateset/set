import { describe, expect, it } from "vitest";
import { Interface } from "ethers";
import {
  extractEventArg,
  findAllEvents,
  findEvent,
  parseAllEvents
} from "../src/utils/events";

const transferAbi = [
  "event Transfer(address indexed from, address indexed to, uint256 value)"
];

function createContract(address: string) {
  return {
    target: address,
    interface: new Interface(transferAbi)
  } as any;
}

function createTransferLog(
  contract: ReturnType<typeof createContract>,
  from: string,
  to: string,
  value: bigint
) {
  const fragment = contract.interface.getEvent("Transfer");
  const encoded = contract.interface.encodeEventLog(fragment, [from, to, value]);

  return {
    address: contract.target,
    topics: encoded.topics,
    data: encoded.data
  };
}

describe("event utilities", () => {
  it("does not parse a matching signature from a different contract address", () => {
    const contractA = createContract("0x1000000000000000000000000000000000000001");
    const contractB = createContract("0x2000000000000000000000000000000000000002");
    const receipt = {
      hash: "0xreceipt",
      logs: [
        createTransferLog(
          contractB,
          "0x3000000000000000000000000000000000000003",
          "0x4000000000000000000000000000000000000004",
          25n
        )
      ]
    } as any;

    expect(findEvent(receipt, contractA, "Transfer")).toBeNull();
    expect(extractEventArg(receipt, contractA, "Transfer", "value")).toBeNull();
  });

  it("filters to logs emitted by the target contract instance", () => {
    const contractA = createContract("0x1000000000000000000000000000000000000001");
    const contractB = createContract("0x2000000000000000000000000000000000000002");
    const receipt = {
      hash: "0xreceipt",
      logs: [
        createTransferLog(
          contractB,
          "0x3000000000000000000000000000000000000003",
          "0x4000000000000000000000000000000000000004",
          25n
        ),
        createTransferLog(
          contractA,
          "0x5000000000000000000000000000000000000005",
          "0x6000000000000000000000000000000000000006",
          50n
        )
      ]
    } as any;

    const events = findAllEvents(receipt, contractA, "Transfer");

    expect(events).toHaveLength(1);
    expect(events[0]?.address).toBe(contractA.target);
    expect(events[0]?.args).toMatchObject({
      from: "0x5000000000000000000000000000000000000005",
      to: "0x6000000000000000000000000000000000000006",
      value: 50n
    });
  });

  it("attributes logs to the correct contract in parseAllEvents", () => {
    const contractA = createContract("0x1000000000000000000000000000000000000001");
    const contractB = createContract("0x2000000000000000000000000000000000000002");
    const receipt = {
      hash: "0xreceipt",
      logs: [
        createTransferLog(
          contractB,
          "0x3000000000000000000000000000000000000003",
          "0x4000000000000000000000000000000000000004",
          25n
        ),
        createTransferLog(
          contractA,
          "0x5000000000000000000000000000000000000005",
          "0x6000000000000000000000000000000000000006",
          50n
        )
      ]
    } as any;

    const events = parseAllEvents(receipt, [contractA, contractB]);

    expect(events).toHaveLength(2);
    expect(events.map(event => event.address)).toEqual([
      contractB.target,
      contractA.target
    ]);
    expect(events.map(event => event.args.value)).toEqual([25n, 50n]);
  });
});
