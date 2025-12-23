/**
 * Set Chain SDK - Stablecoin Types
 */

export enum TokenCategory {
  NATIVE = 0,
  BRIDGED = 1,
  STABLECOIN = 2,
  VERIFIED = 3,
  UNKNOWN = 4
}

export enum TrustLevel {
  TRUSTED = 0,
  VERIFIED = 1,
  UNVERIFIED = 2
}

export enum RedemptionStatus {
  PENDING = 0,
  PROCESSING = 1,
  COMPLETED = 2,
  CANCELLED = 3
}

export interface TokenInfo {
  tokenAddress: string;
  name: string;
  symbol: string;
  decimals: number;
  logoURI: string;
  category: TokenCategory;
  trustLevel: TrustLevel;
  isCollateral: boolean;
  addedAt: bigint;
  updatedAt: bigint;
}

export interface NAVReport {
  totalAssets: bigint;
  totalShares: bigint;
  navPerShare: bigint;
  timestamp: bigint;
  reportDate: bigint;
  proofHash: string;
  attestor: string;
}

export interface RedemptionRequest {
  id: bigint;
  requester: string;
  ssUSDAmount: bigint;
  collateralToken: string;
  requestedAt: bigint;
  processedAt: bigint;
  status: RedemptionStatus;
}

export interface StablecoinAddresses {
  tokenRegistry: string;
  navOracle: string;
  ssUSD: string;
  wssUSD: string;
  treasury: string;
}

export interface StablecoinStats {
  totalSupply: bigint;
  totalShares: bigint;
  navPerShare: bigint;
  totalCollateral: bigint;
  collateralRatio: bigint;
  apy: number;
}

export interface UserBalance {
  ssUSD: bigint;
  ssUSDShares: bigint;
  wssUSD: bigint;
  wssUSDValue: bigint;
}

export interface DepositResult {
  txHash: string;
  ssUSDMinted: bigint;
}

export interface RedemptionResult {
  txHash: string;
  requestId: bigint;
}

export interface WrapResult {
  txHash: string;
  wssUSDReceived: bigint;
}

export interface UnwrapResult {
  txHash: string;
  ssUSDReceived: bigint;
}
