/**
 * Set Chain SDK - Event Parsing Utilities
 *
 * Helpers for parsing and extracting events from transaction receipts.
 */

import { Contract, TransactionReceipt, Log, Interface, keccak256, toUtf8Bytes, LogDescription } from "ethers";
import { EventParseError, SDKError, SDKErrorCode } from "../errors";

/**
 * Parsed event result
 */
export interface ParsedEvent<T = Record<string, unknown>> {
  /** Event name */
  name: string;
  /** Event arguments */
  args: T;
  /** Log index in transaction */
  index: number;
  /** Contract address that emitted the event */
  address: string;
  /** Raw log */
  log: Log;
}

/**
 * Find a specific event in transaction receipt
 * @param receipt Transaction receipt
 * @param contract Contract instance with ABI
 * @param eventName Event name to find
 * @returns Parsed event or null
 */
export function findEvent<T = Record<string, unknown>>(
  receipt: TransactionReceipt,
  contract: Contract,
  eventName: string
): ParsedEvent<T> | null {
  const event = contract.interface.getEvent(eventName);
  if (!event) {
    return null;
  }

  const topicHash = event.topicHash;

  for (let i = 0; i < receipt.logs.length; i++) {
    const log = receipt.logs[i];
    if (log.topics[0] === topicHash) {
      try {
        const parsed = contract.interface.parseLog({
          topics: log.topics as string[],
          data: log.data
        });

        if (parsed) {
          return {
            name: parsed.name,
            args: Object.fromEntries(
              parsed.fragment.inputs.map((input, idx) => [
                input.name || `arg${idx}`,
                parsed.args[idx]
              ])
            ) as T,
            index: i,
            address: log.address,
            log
          };
        }
      } catch {
        // Continue to next log
      }
    }
  }

  return null;
}

/**
 * Find a specific event or throw error
 * @param receipt Transaction receipt
 * @param contract Contract instance with ABI
 * @param eventName Event name to find
 * @returns Parsed event
 * @throws EventParseError if event not found
 */
export function findEventOrThrow<T = Record<string, unknown>>(
  receipt: TransactionReceipt,
  contract: Contract,
  eventName: string
): ParsedEvent<T> {
  const event = findEvent<T>(receipt, contract, eventName);
  if (!event) {
    throw new EventParseError(eventName, receipt.hash);
  }
  return event;
}

/**
 * Find all events of a specific type in transaction receipt
 * @param receipt Transaction receipt
 * @param contract Contract instance with ABI
 * @param eventName Event name to find
 * @returns Array of parsed events
 */
export function findAllEvents<T = Record<string, unknown>>(
  receipt: TransactionReceipt,
  contract: Contract,
  eventName: string
): ParsedEvent<T>[] {
  const event = contract.interface.getEvent(eventName);
  if (!event) {
    return [];
  }

  const topicHash = event.topicHash;
  const results: ParsedEvent<T>[] = [];

  for (let i = 0; i < receipt.logs.length; i++) {
    const log = receipt.logs[i];
    if (log.topics[0] === topicHash) {
      try {
        const parsed = contract.interface.parseLog({
          topics: log.topics as string[],
          data: log.data
        });

        if (parsed) {
          results.push({
            name: parsed.name,
            args: Object.fromEntries(
              parsed.fragment.inputs.map((input, idx) => [
                input.name || `arg${idx}`,
                parsed.args[idx]
              ])
            ) as T,
            index: i,
            address: log.address,
            log
          });
        }
      } catch {
        // Continue to next log
      }
    }
  }

  return results;
}

/**
 * Extract a single argument from an event
 * @param receipt Transaction receipt
 * @param contract Contract instance with ABI
 * @param eventName Event name
 * @param argName Argument name to extract
 * @returns Argument value or null
 */
export function extractEventArg<T = unknown>(
  receipt: TransactionReceipt,
  contract: Contract,
  eventName: string,
  argName: string
): T | null {
  const event = findEvent(receipt, contract, eventName);
  if (!event) {
    return null;
  }

  const value = event.args[argName];
  return value !== undefined ? (value as T) : null;
}

/**
 * Extract a single argument from an event or throw
 * @param receipt Transaction receipt
 * @param contract Contract instance with ABI
 * @param eventName Event name
 * @param argName Argument name to extract
 * @returns Argument value
 * @throws EventParseError if event or argument not found
 */
export function extractEventArgOrThrow<T = unknown>(
  receipt: TransactionReceipt,
  contract: Contract,
  eventName: string,
  argName: string
): T {
  const value = extractEventArg<T>(receipt, contract, eventName, argName);
  if (value === null) {
    throw new EventParseError(`${eventName}.${argName}`, receipt.hash);
  }
  return value;
}

/**
 * Parse all events from a receipt using multiple contracts
 * @param receipt Transaction receipt
 * @param contracts Array of contract instances
 * @returns Array of parsed events
 */
export function parseAllEvents(
  receipt: TransactionReceipt,
  contracts: Contract[]
): ParsedEvent[] {
  const results: ParsedEvent[] = [];

  for (let i = 0; i < receipt.logs.length; i++) {
    const log = receipt.logs[i];

    for (const contract of contracts) {
      try {
        const parsed = contract.interface.parseLog({
          topics: log.topics as string[],
          data: log.data
        });

        if (parsed) {
          results.push({
            name: parsed.name,
            args: Object.fromEntries(
              parsed.fragment.inputs.map((input, idx) => [
                input.name || `arg${idx}`,
                parsed.args[idx]
              ])
            ),
            index: i,
            address: log.address,
            log
          });
          break; // Found a match, move to next log
        }
      } catch {
        // Continue to next contract
      }
    }
  }

  return results;
}

/**
 * Create an event topic hash
 * @param eventSignature Event signature (e.g., "Transfer(address,address,uint256)")
 * @returns Topic hash
 */
export function getEventTopic(eventSignature: string): string {
  return keccak256(toUtf8Bytes(eventSignature));
}

/**
 * Find event by topic hash (without ABI)
 * @param receipt Transaction receipt
 * @param topicHash Topic hash to search for
 * @returns Log or null
 */
export function findLogByTopic(
  receipt: TransactionReceipt,
  topicHash: string
): Log | null {
  for (const log of receipt.logs) {
    if (log.topics[0] === topicHash) {
      return log;
    }
  }
  return null;
}

/**
 * Decode indexed event argument from topic
 * @param topic Topic hex string
 * @param type Argument type (e.g., "address", "bytes32", "uint256")
 * @returns Decoded value
 */
export function decodeIndexedArg(topic: string, type: "address"): string;
export function decodeIndexedArg(topic: string, type: "bytes32"): string;
export function decodeIndexedArg(topic: string, type: "uint256"): bigint;
export function decodeIndexedArg(topic: string, type: string): unknown {
  switch (type) {
    case "address":
      return "0x" + topic.slice(26);
    case "bytes32":
      return topic;
    case "uint256":
      return BigInt(topic);
    default:
      return topic;
  }
}

/**
 * Common event signatures for Set Chain contracts
 */
export const EVENT_SIGNATURES = {
  // ERC20
  Transfer: "Transfer(address,address,uint256)",
  Approval: "Approval(address,address,uint256)",

  // SetRegistry
  BatchCommitted: "BatchCommitted(bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,uint64,uint64,uint32)",
  StarkProofCommitted: "StarkProofCommitted(bytes32,bytes32)",

  // SetPaymaster
  MerchantSponsored: "MerchantSponsored(address,uint256)",
  SponsorshipExecuted: "SponsorshipExecuted(address,uint256,uint8)",

  // Stablecoin
  Deposited: "Deposited(address,address,uint256,uint256)",
  RedemptionRequested: "RedemptionRequested(uint256,address,uint256,address)",
  Wrapped: "Wrapped(address,uint256,uint256)",
  Unwrapped: "Unwrapped(address,uint256,uint256)",

  // MEV
  EncryptedTxSubmitted: "EncryptedTxSubmitted(bytes32,address,bytes32,uint256,uint256)"
} as const;
