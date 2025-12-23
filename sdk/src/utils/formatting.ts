/**
 * Set Chain SDK - Formatting Utilities
 *
 * Helper functions for formatting balances, amounts, and display values.
 */

import { formatUnits, parseUnits } from "ethers";
import { SDKError, SDKErrorCode } from "../errors";

/**
 * Options for formatting balances
 */
export interface FormatBalanceOptions {
  /** Maximum number of decimal places (default: 4) */
  maxDecimals?: number;
  /** Trim trailing zeros (default: true) */
  trimZeros?: boolean;
  /** Include thousand separators (default: false) */
  separators?: boolean;
  /** Suffix to append (e.g., " ETH") */
  suffix?: string;
}

/**
 * Format a balance for display
 * @param amount Amount in wei/smallest unit
 * @param decimals Token decimals
 * @param options Formatting options
 * @returns Formatted string
 */
export function formatBalance(
  amount: bigint,
  decimals = 18,
  options: FormatBalanceOptions = {}
): string {
  const {
    maxDecimals = 4,
    trimZeros = true,
    separators = false,
    suffix = ""
  } = options;

  // Convert to string representation
  const raw = formatUnits(amount, decimals);

  // Split into integer and decimal parts
  const [intPart, decPart = ""] = raw.split(".");

  // Truncate decimals
  let truncatedDec = decPart.slice(0, maxDecimals);

  // Trim trailing zeros if requested
  if (trimZeros) {
    truncatedDec = truncatedDec.replace(/0+$/, "");
  }

  // Format integer part with separators if requested
  let formattedInt = intPart;
  if (separators) {
    formattedInt = parseInt(intPart, 10).toLocaleString("en-US");
  }

  // Combine
  let result = truncatedDec ? `${formattedInt}.${truncatedDec}` : formattedInt;

  // Add suffix
  if (suffix) {
    result += suffix;
  }

  return result;
}

/**
 * Parse a human-readable amount to wei/smallest unit
 * @param amount Amount as string or number
 * @param decimals Token decimals
 * @returns Amount in smallest unit
 * @throws SDKError if parsing fails
 */
export function parseAmount(amount: string | number, decimals = 18): bigint {
  try {
    // Handle numeric input
    const strAmount = typeof amount === "number" ? amount.toString() : amount;

    // Remove any thousand separators
    const cleaned = strAmount.replace(/,/g, "");

    return parseUnits(cleaned, decimals);
  } catch (error) {
    throw new SDKError(SDKErrorCode.VALIDATION_ERROR, `Failed to parse amount: ${amount}`, {
      details: { amount, decimals },
      cause: error instanceof Error ? error : undefined
    });
  }
}

/**
 * Format ETH value
 * @param wei Amount in wei
 * @param options Formatting options
 */
export function formatETH(wei: bigint, options: FormatBalanceOptions = {}): string {
  return formatBalance(wei, 18, { suffix: " ETH", ...options });
}

/**
 * Parse ETH value
 * @param eth Amount in ETH
 * @returns Amount in wei
 */
export function parseETH(eth: string | number): bigint {
  return parseAmount(eth, 18);
}

/**
 * Format USD value (6 decimals for USDC/USDT)
 * @param amount Amount in smallest unit
 * @param options Formatting options
 */
export function formatUSD(amount: bigint, options: FormatBalanceOptions = {}): string {
  return formatBalance(amount, 6, { maxDecimals: 2, suffix: " USD", ...options });
}

/**
 * Parse USD value (6 decimals for USDC/USDT)
 * @param usd Amount in USD
 * @returns Amount in smallest unit
 */
export function parseUSD(usd: string | number): bigint {
  return parseAmount(usd, 6);
}

/**
 * Format ssUSD value (18 decimals)
 * @param amount Amount in smallest unit
 * @param options Formatting options
 */
export function formatssUSD(amount: bigint, options: FormatBalanceOptions = {}): string {
  return formatBalance(amount, 18, { suffix: " ssUSD", ...options });
}

/**
 * Parse ssUSD value (18 decimals)
 * @param ssUsd Amount in ssUSD
 * @returns Amount in smallest unit
 */
export function parsessUSD(ssUsd: string | number): bigint {
  return parseAmount(ssUsd, 18);
}

/**
 * Format gas amount
 * @param gas Gas units
 * @returns Formatted string
 */
export function formatGas(gas: bigint): string {
  if (gas >= 1_000_000n) {
    return `${(Number(gas) / 1_000_000).toFixed(2)}M gas`;
  }
  if (gas >= 1_000n) {
    return `${(Number(gas) / 1_000).toFixed(1)}K gas`;
  }
  return `${gas} gas`;
}

/**
 * Format gas price in gwei
 * @param wei Gas price in wei
 * @returns Formatted string
 */
export function formatGasPrice(wei: bigint): string {
  const gwei = Number(wei) / 1e9;
  if (gwei < 1) {
    return `${(gwei * 1000).toFixed(2)} mwei`;
  }
  return `${gwei.toFixed(2)} gwei`;
}

/**
 * Format percentage
 * @param value Value as decimal (0.05 = 5%)
 * @param decimals Number of decimal places
 * @returns Formatted percentage string
 */
export function formatPercentage(value: number, decimals = 2): string {
  return `${(value * 100).toFixed(decimals)}%`;
}

/**
 * Format APY
 * @param apy APY as decimal (0.05 = 5%)
 * @returns Formatted APY string
 */
export function formatAPY(apy: number): string {
  return formatPercentage(apy) + " APY";
}

/**
 * Shorten address for display
 * @param address Full address
 * @param chars Number of characters to show on each side (default: 4)
 * @returns Shortened address (e.g., "0x1234...5678")
 */
export function shortenAddress(address: string, chars = 4): string {
  if (!address || address.length < chars * 2 + 2) {
    return address;
  }
  return `${address.slice(0, chars + 2)}...${address.slice(-chars)}`;
}

/**
 * Format timestamp as ISO string
 * @param timestamp Unix timestamp (seconds)
 * @returns ISO date string
 */
export function formatTimestamp(timestamp: bigint | number): string {
  const ts = typeof timestamp === "bigint" ? Number(timestamp) : timestamp;
  return new Date(ts * 1000).toISOString();
}

/**
 * Format duration in human-readable form
 * @param seconds Duration in seconds
 * @returns Human-readable duration
 */
export function formatDuration(seconds: bigint | number): string {
  const secs = typeof seconds === "bigint" ? Number(seconds) : seconds;

  if (secs < 60) {
    return `${secs}s`;
  }

  if (secs < 3600) {
    const mins = Math.floor(secs / 60);
    const remainingSecs = secs % 60;
    return remainingSecs > 0 ? `${mins}m ${remainingSecs}s` : `${mins}m`;
  }

  if (secs < 86400) {
    const hours = Math.floor(secs / 3600);
    const mins = Math.floor((secs % 3600) / 60);
    return mins > 0 ? `${hours}h ${mins}m` : `${hours}h`;
  }

  const days = Math.floor(secs / 86400);
  const hours = Math.floor((secs % 86400) / 3600);
  return hours > 0 ? `${days}d ${hours}h` : `${days}d`;
}

/**
 * Format a transaction hash for display
 * @param hash Full transaction hash
 * @param chars Number of characters on each side
 * @returns Shortened hash
 */
export function shortenTxHash(hash: string, chars = 6): string {
  if (!hash || hash.length < chars * 2 + 2) {
    return hash;
  }
  return `${hash.slice(0, chars + 2)}...${hash.slice(-chars)}`;
}
