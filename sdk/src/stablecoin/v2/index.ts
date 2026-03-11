/**
 * Set Chain SDK - V2 Stablecoin Agent Module
 */

export { AgentClient, AgentError, AgentErrorCode, createAgentClient } from "./AgentClient.js";
export type { CreateAgentClientOptions } from "./AgentClient.js";

export {
  // Enums
  FulfillmentType,
  DisputeResolution,
  DisputeReason,
  EscrowStatus,
  SettlementMode,
} from "./types.js";

export type {
  // Addresses
  SSDCV2Addresses,
  // Agent
  AgentPolicy,
  AgentStatus,
  // Escrow
  InvoiceTerms,
  EscrowInfo,
  ReleaseSplit,
  // System
  SystemStatus,
  // Results
  TxResult,
  DepositResult,
  EscrowFundResult,
  RedeemRequestResult,
  GasTankTopUpResult,
  // Agent Protocol
  PaymentRequest,
  PaymentAcceptance,
  FulfillmentProof,
} from "./types.js";
