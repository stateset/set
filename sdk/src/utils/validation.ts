/**
 * Set Chain SDK - Validation Utilities
 *
 * Input validation functions for addresses, amounts, and data.
 */

import { isAddress, getAddress } from "ethers";
import { InvalidAddressError, InvalidAmountError, SDKError, SDKErrorCode } from "../errors";

/**
 * Validate and normalize an Ethereum address
 * @param address Address to validate
 * @param name Optional name for error messages
 * @returns Checksummed address
 * @throws InvalidAddressError if invalid
 */
export function validateAddress(address: string, name = "address"): string {
  if (!address || typeof address !== "string") {
    throw new InvalidAddressError(address || "undefined", `${name} is required`);
  }

  if (!isAddress(address)) {
    throw new InvalidAddressError(address, `Invalid ${name} format`);
  }

  // Return checksummed address
  return getAddress(address);
}

/**
 * Validate that an address is not the zero address
 * @param address Address to validate
 * @param name Optional name for error messages
 * @returns Checksummed address
 * @throws InvalidAddressError if zero address
 */
export function validateNonZeroAddress(address: string, name = "address"): string {
  const checksummed = validateAddress(address, name);

  if (checksummed === "0x0000000000000000000000000000000000000000") {
    throw new InvalidAddressError(address, `${name} cannot be zero address`);
  }

  return checksummed;
}

/**
 * Check if a string is a valid address (without throwing)
 * @param address Address to check
 * @returns True if valid
 */
export function isValidAddress(address: string): boolean {
  try {
    validateAddress(address);
    return true;
  } catch {
    return false;
  }
}

/**
 * Validate amount is positive
 * @param amount Amount to validate
 * @param name Optional name for error messages
 * @throws InvalidAmountError if not positive
 */
export function validatePositiveAmount(amount: bigint, name = "amount"): void {
  if (typeof amount !== "bigint") {
    throw new InvalidAmountError(amount, `${name} must be a bigint`);
  }

  if (amount <= 0n) {
    throw new InvalidAmountError(amount, `${name} must be positive`);
  }
}

/**
 * Validate amount is non-negative
 * @param amount Amount to validate
 * @param name Optional name for error messages
 * @throws InvalidAmountError if negative
 */
export function validateNonNegativeAmount(amount: bigint, name = "amount"): void {
  if (typeof amount !== "bigint") {
    throw new InvalidAmountError(amount, `${name} must be a bigint`);
  }

  if (amount < 0n) {
    throw new InvalidAmountError(amount, `${name} cannot be negative`);
  }
}

/**
 * Validate amount is within bounds
 * @param amount Amount to validate
 * @param min Minimum value (inclusive)
 * @param max Maximum value (inclusive)
 * @param name Optional name for error messages
 * @throws InvalidAmountError if out of bounds
 */
export function validateAmountBounds(
  amount: bigint,
  min: bigint,
  max: bigint,
  name = "amount"
): void {
  validateNonNegativeAmount(amount, name);

  if (amount < min) {
    throw new InvalidAmountError(amount, `${name} must be at least ${min}`);
  }

  if (amount > max) {
    throw new InvalidAmountError(amount, `${name} must be at most ${max}`);
  }
}

/**
 * Validate hex data string
 * @param data Data to validate
 * @param name Optional name for error messages
 * @returns Normalized hex string
 * @throws SDKError if invalid
 */
export function validateHexData(data: string, name = "data"): string {
  if (!data || typeof data !== "string") {
    throw new SDKError(SDKErrorCode.INVALID_DATA, `${name} is required`);
  }

  // Must start with 0x
  if (!data.startsWith("0x")) {
    throw new SDKError(SDKErrorCode.INVALID_DATA, `${name} must start with 0x`, {
      details: { data },
      suggestion: `Prepend "0x" to the data`
    });
  }

  // Must be valid hex (0-9, a-f, A-F)
  const hexPart = data.slice(2);
  if (!/^[0-9a-fA-F]*$/.test(hexPart)) {
    throw new SDKError(SDKErrorCode.INVALID_DATA, `${name} contains invalid hex characters`, {
      details: { data }
    });
  }

  // Must have even length (complete bytes)
  if (hexPart.length % 2 !== 0) {
    throw new SDKError(SDKErrorCode.INVALID_DATA, `${name} must have even length`, {
      details: { data, length: hexPart.length }
    });
  }

  return data.toLowerCase();
}

/**
 * Validate bytes32 value
 * @param value Value to validate
 * @param name Optional name for error messages
 * @returns Normalized hex string
 * @throws SDKError if invalid
 */
export function validateBytes32(value: string, name = "value"): string {
  const validated = validateHexData(value, name);

  if (validated.length !== 66) { // 0x + 64 hex chars
    throw new SDKError(SDKErrorCode.INVALID_DATA, `${name} must be 32 bytes (66 characters including 0x)`, {
      details: { value, length: validated.length, expectedLength: 66 }
    });
  }

  return validated;
}

/**
 * Assert that balance is sufficient
 * @param available Available balance
 * @param required Required balance
 * @param tokenSymbol Token symbol for error message
 * @param decimals Token decimals
 * @throws InsufficientBalanceError if insufficient
 */
export function assertSufficientBalance(
  available: bigint,
  required: bigint,
  tokenSymbol = "tokens",
  decimals = 18
): void {
  const { InsufficientBalanceError } = require("../errors");

  if (available < required) {
    throw new InsufficientBalanceError(available, required, tokenSymbol, decimals);
  }
}

/**
 * Assert that allowance is sufficient
 * @param currentAllowance Current allowance
 * @param required Required allowance
 * @param spender Spender address
 * @param tokenSymbol Token symbol for error message
 * @param decimals Token decimals
 * @throws InsufficientAllowanceError if insufficient
 */
export function assertSufficientAllowance(
  currentAllowance: bigint,
  required: bigint,
  spender: string,
  tokenSymbol = "tokens",
  decimals = 18
): void {
  const { InsufficientAllowanceError } = require("../errors");

  if (currentAllowance < required) {
    throw new InsufficientAllowanceError(currentAllowance, required, spender, tokenSymbol, decimals);
  }
}
