/**
 * Set Chain SDK - Stablecoin Module
 *
 * High-level interface for interacting with the ssUSD stablecoin system.
 *
 * @example
 * ```typescript
 * import { createStablecoinClient, StablecoinAddresses } from "@set-chain/sdk/stablecoin";
 *
 * const addresses: StablecoinAddresses = {
 *   tokenRegistry: "0x...",
 *   navOracle: "0x...",
 *   ssUSD: "0x...",
 *   wssUSD: "0x...",
 *   treasury: "0x..."
 * };
 *
 * const client = createStablecoinClient(addresses, privateKey, rpcUrl);
 *
 * // Deposit USDC to get ssUSD
 * const result = await client.deposit(USDC_ADDRESS, parseUnits("1000", 6));
 * console.log("ssUSD minted:", formatUnits(result.ssUSDMinted, 18));
 *
 * // Check balance (auto-rebases with yield)
 * const balance = await client.getBalance(address);
 * console.log("ssUSD:", formatUnits(balance.ssUSD, 18));
 *
 * // Wrap ssUSD for DeFi compatibility
 * const wrapResult = await client.wrap(parseUnits("500", 18));
 * console.log("wssUSD received:", formatUnits(wrapResult.wssUSDReceived, 18));
 *
 * // Get system stats
 * const stats = await client.getStats();
 * console.log("APY:", stats.apy.toFixed(2) + "%");
 * ```
 */

export { StablecoinClient, createStablecoinClient } from "./StablecoinClient";

export {
  TokenCategory,
  TrustLevel,
  RedemptionStatus,
  type TokenInfo,
  type NAVReport,
  type RedemptionRequest,
  type StablecoinAddresses,
  type StablecoinStats,
  type UserBalance,
  type DepositResult,
  type RedemptionResult,
  type WrapResult,
  type UnwrapResult
} from "./types";

export {
  tokenRegistryAbi,
  navOracleAbi,
  ssUSDAbi,
  wssUSDAbi,
  treasuryVaultAbi,
  erc20Abi
} from "./abis";
