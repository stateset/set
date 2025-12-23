/**
 * Set Chain SDK - Stablecoin Client
 *
 * High-level interface for interacting with the ssUSD stablecoin system.
 */

import { Contract, JsonRpcProvider, Wallet, formatUnits } from "ethers";
import {
  tokenRegistryAbi,
  navOracleAbi,
  ssUSDAbi,
  wssUSDAbi,
  treasuryVaultAbi,
  erc20Abi
} from "./abis";
import {
  StablecoinAddresses,
  StablecoinStats,
  UserBalance,
  NAVReport,
  RedemptionRequest,
  RedemptionStatus,
  TokenInfo,
  DepositResult,
  RedemptionResult,
  WrapResult,
  UnwrapResult
} from "./types";
import {
  SDKError,
  SDKErrorCode,
  DepositsPausedError,
  RedemptionsPausedError,
  InvalidCollateralError,
  NAVStaleError,
  TransactionFailedError,
  wrapError
} from "../errors";
import {
  validateAddress,
  validatePositiveAmount,
  assertSufficientBalance,
  assertSufficientAllowance
} from "../utils/validation";
import { formatBalance } from "../utils/formatting";
import { estimateGas, DEFAULT_GAS_LIMITS } from "../utils/gas";
import { withRetry } from "../utils/retry";
import { findEvent, extractEventArg } from "../utils/events";
import { getConfig, debugLog } from "../config";

/**
 * Extended user balance with formatted values
 */
export interface FormattedUserBalance extends UserBalance {
  formatted: {
    ssUSD: string;
    wssUSD: string;
    wssUSDValue: string;
  };
}

export class StablecoinClient {
  private provider: JsonRpcProvider;
  private signer: Wallet;
  private addresses: StablecoinAddresses;

  private tokenRegistry: Contract;
  private navOracle: Contract;
  private ssUSD: Contract;
  private wssUSD: Contract;
  private treasury: Contract;

  constructor(
    addresses: StablecoinAddresses,
    signer: Wallet
  ) {
    // Validate addresses
    this.addresses = {
      tokenRegistry: validateAddress(addresses.tokenRegistry, "tokenRegistry"),
      navOracle: validateAddress(addresses.navOracle, "navOracle"),
      ssUSD: validateAddress(addresses.ssUSD, "ssUSD"),
      wssUSD: validateAddress(addresses.wssUSD, "wssUSD"),
      treasury: validateAddress(addresses.treasury, "treasury")
    };

    this.signer = signer;
    this.provider = signer.provider as JsonRpcProvider;

    this.tokenRegistry = new Contract(this.addresses.tokenRegistry, tokenRegistryAbi, signer);
    this.navOracle = new Contract(this.addresses.navOracle, navOracleAbi, signer);
    this.ssUSD = new Contract(this.addresses.ssUSD, ssUSDAbi, signer);
    this.wssUSD = new Contract(this.addresses.wssUSD, wssUSDAbi, signer);
    this.treasury = new Contract(this.addresses.treasury, treasuryVaultAbi, signer);
  }

  // =========================================================================
  // Deposit
  // =========================================================================

  /**
   * Deposit collateral (USDC/USDT) and receive ssUSD
   * @param collateralToken Address of collateral token
   * @param amount Amount in collateral token units
   * @param recipient Optional recipient (defaults to signer)
   */
  async deposit(
    collateralToken: string,
    amount: bigint,
    recipient?: string
  ): Promise<DepositResult> {
    const config = getConfig();

    // Validate inputs
    const validatedToken = validateAddress(collateralToken, "collateralToken");
    validatePositiveAmount(amount, "amount");
    const to = recipient ? validateAddress(recipient, "recipient") : await this.signer.getAddress();

    debugLog("Stablecoin", `Depositing ${amount} of ${validatedToken} to ${to}`);

    try {
      // Check if deposits are paused
      const paused = await withRetry(() => this.treasury.depositsPaused());
      if (paused) {
        throw new DepositsPausedError();
      }

      // Check if token is approved collateral
      const isApproved = await withRetry(() => this.tokenRegistry.isApprovedCollateral(validatedToken));
      if (!isApproved) {
        throw new InvalidCollateralError(validatedToken);
      }

      // Check user balance
      const collateral = new Contract(validatedToken, erc20Abi, this.signer);
      const userAddress = await this.signer.getAddress();
      const balance = await withRetry(() => collateral.balanceOf(userAddress));
      assertSufficientBalance(balance, amount, "collateral", config.collateralDecimals);

      // Check and update allowance
      const currentAllowance = await withRetry(() => collateral.allowance(userAddress, this.addresses.treasury));
      if (currentAllowance < amount) {
        debugLog("Stablecoin", `Approving ${amount} tokens for treasury`);
        const approveTx = await collateral.approve(this.addresses.treasury, amount);
        await approveTx.wait(config.blockConfirmations);
      }

      // Estimate gas
      const gasEstimate = await estimateGas(
        this.treasury,
        "deposit",
        [validatedToken, amount, to],
        { gasBuffer: config.gasBuffer }
      );

      // Deposit
      const tx = await this.treasury.deposit(validatedToken, amount, to, {
        gasLimit: gasEstimate.gasLimitWithBuffer
      });
      const receipt = await tx.wait(config.blockConfirmations);

      if (!receipt || receipt.status !== 1) {
        throw new TransactionFailedError("Deposit transaction failed", tx.hash);
      }

      // Parse events for minted amount
      const ssUSDMinted = extractEventArg<bigint>(receipt, this.treasury, "Deposited", "ssUSDMinted") ?? 0n;

      debugLog("Stablecoin", `Deposit successful: ${formatBalance(ssUSDMinted, 18)} ssUSD minted`);

      return {
        txHash: receipt.hash,
        ssUSDMinted
      };
    } catch (error) {
      throw wrapError(error, "Deposit failed");
    }
  }

  // =========================================================================
  // Redemption
  // =========================================================================

  /**
   * Request redemption of ssUSD for collateral
   * @param ssUSDAmount Amount of ssUSD to redeem
   * @param preferredCollateral Preferred collateral token address
   */
  async requestRedemption(
    ssUSDAmount: bigint,
    preferredCollateral: string
  ): Promise<RedemptionResult> {
    const config = getConfig();

    // Validate inputs
    validatePositiveAmount(ssUSDAmount, "ssUSDAmount");
    const validatedCollateral = validateAddress(preferredCollateral, "preferredCollateral");

    debugLog("Stablecoin", `Requesting redemption of ${formatBalance(ssUSDAmount, 18)} ssUSD`);

    try {
      // Check if redemptions are paused
      const paused = await withRetry(() => this.treasury.redemptionsPaused());
      if (paused) {
        throw new RedemptionsPausedError();
      }

      // Check user balance
      const userAddress = await this.signer.getAddress();
      const balance = await withRetry(() => this.ssUSD.balanceOf(userAddress));
      assertSufficientBalance(balance, ssUSDAmount, "ssUSD", config.ssUSDDecimals);

      // Check and update allowance
      const currentAllowance = await withRetry(() => this.ssUSD.allowance(userAddress, this.addresses.treasury));
      if (currentAllowance < ssUSDAmount) {
        debugLog("Stablecoin", `Approving ${ssUSDAmount} ssUSD for treasury`);
        const approveTx = await this.ssUSD.approve(this.addresses.treasury, ssUSDAmount);
        await approveTx.wait(config.blockConfirmations);
      }

      // Estimate gas
      const gasEstimate = await estimateGas(
        this.treasury,
        "requestRedemption",
        [ssUSDAmount, validatedCollateral],
        { gasBuffer: config.gasBuffer }
      );

      // Request redemption
      const tx = await this.treasury.requestRedemption(ssUSDAmount, validatedCollateral, {
        gasLimit: gasEstimate.gasLimitWithBuffer
      });
      const receipt = await tx.wait(config.blockConfirmations);

      if (!receipt || receipt.status !== 1) {
        throw new TransactionFailedError("Redemption request failed", tx.hash);
      }

      // Parse events for request ID
      const requestId = extractEventArg<bigint>(receipt, this.treasury, "RedemptionRequested", "requestId") ?? 0n;

      debugLog("Stablecoin", `Redemption request successful: ID ${requestId}`);

      return {
        txHash: receipt.hash,
        requestId
      };
    } catch (error) {
      throw wrapError(error, "Redemption request failed");
    }
  }

  /**
   * Cancel a pending redemption
   */
  async cancelRedemption(requestId: bigint): Promise<string> {
    const config = getConfig();

    try {
      const tx = await this.treasury.cancelRedemption(requestId);
      const receipt = await tx.wait(config.blockConfirmations);

      if (!receipt || receipt.status !== 1) {
        throw new TransactionFailedError("Cancel redemption failed", tx.hash);
      }

      return receipt.hash;
    } catch (error) {
      throw wrapError(error, "Cancel redemption failed");
    }
  }

  /**
   * Get redemption request details
   */
  async getRedemptionRequest(requestId: bigint): Promise<RedemptionRequest> {
    try {
      const request = await withRetry(() => this.treasury.getRedemptionRequest(requestId));
      return {
        id: request.id,
        requester: request.requester,
        ssUSDAmount: request.ssUSDAmount,
        collateralToken: request.collateralToken,
        requestedAt: request.requestedAt,
        processedAt: request.processedAt,
        status: request.status as RedemptionStatus
      };
    } catch (error) {
      throw wrapError(error, "Failed to get redemption request");
    }
  }

  /**
   * Get user's redemption request IDs
   */
  async getUserRedemptions(user: string): Promise<bigint[]> {
    const validatedUser = validateAddress(user, "user");
    try {
      return await withRetry(() => this.treasury.getUserRedemptions(validatedUser));
    } catch (error) {
      throw wrapError(error, "Failed to get user redemptions");
    }
  }

  // =========================================================================
  // Wrap/Unwrap
  // =========================================================================

  /**
   * Wrap ssUSD to wssUSD (for DeFi compatibility)
   */
  async wrap(ssUSDAmount: bigint): Promise<WrapResult> {
    const config = getConfig();
    validatePositiveAmount(ssUSDAmount, "ssUSDAmount");

    debugLog("Stablecoin", `Wrapping ${formatBalance(ssUSDAmount, 18)} ssUSD`);

    try {
      // Check user balance
      const userAddress = await this.signer.getAddress();
      const balance = await withRetry(() => this.ssUSD.balanceOf(userAddress));
      assertSufficientBalance(balance, ssUSDAmount, "ssUSD", config.ssUSDDecimals);

      // Check and update allowance
      const currentAllowance = await withRetry(() => this.ssUSD.allowance(userAddress, this.addresses.wssUSD));
      if (currentAllowance < ssUSDAmount) {
        const approveTx = await this.ssUSD.approve(this.addresses.wssUSD, ssUSDAmount);
        await approveTx.wait(config.blockConfirmations);
      }

      // Wrap
      const tx = await this.wssUSD.wrap(ssUSDAmount);
      const receipt = await tx.wait(config.blockConfirmations);

      if (!receipt || receipt.status !== 1) {
        throw new TransactionFailedError("Wrap failed", tx.hash);
      }

      // Parse events
      const wssUSDReceived = extractEventArg<bigint>(receipt, this.wssUSD, "Wrapped", "wssUSDAmount") ?? 0n;

      debugLog("Stablecoin", `Wrap successful: ${formatBalance(wssUSDReceived, 18)} wssUSD received`);

      return {
        txHash: receipt.hash,
        wssUSDReceived
      };
    } catch (error) {
      throw wrapError(error, "Wrap failed");
    }
  }

  /**
   * Unwrap wssUSD to ssUSD
   */
  async unwrap(wssUSDAmount: bigint): Promise<UnwrapResult> {
    const config = getConfig();
    validatePositiveAmount(wssUSDAmount, "wssUSDAmount");

    debugLog("Stablecoin", `Unwrapping ${formatBalance(wssUSDAmount, 18)} wssUSD`);

    try {
      // Check user balance
      const userAddress = await this.signer.getAddress();
      const balance = await withRetry(() => this.wssUSD.balanceOf(userAddress));
      assertSufficientBalance(balance, wssUSDAmount, "wssUSD", config.ssUSDDecimals);

      // Unwrap
      const tx = await this.wssUSD.unwrap(wssUSDAmount);
      const receipt = await tx.wait(config.blockConfirmations);

      if (!receipt || receipt.status !== 1) {
        throw new TransactionFailedError("Unwrap failed", tx.hash);
      }

      // Parse events
      const ssUSDReceived = extractEventArg<bigint>(receipt, this.wssUSD, "Unwrapped", "ssUSDAmount") ?? 0n;

      debugLog("Stablecoin", `Unwrap successful: ${formatBalance(ssUSDReceived, 18)} ssUSD received`);

      return {
        txHash: receipt.hash,
        ssUSDReceived
      };
    } catch (error) {
      throw wrapError(error, "Unwrap failed");
    }
  }

  // =========================================================================
  // Balances
  // =========================================================================

  /**
   * Get user's stablecoin balances
   */
  async getBalance(address: string): Promise<UserBalance> {
    const validatedAddress = validateAddress(address, "address");

    try {
      const [ssUSDBalance, ssUSDShares, wssUSDBalance, wssUSDValue] = await Promise.all([
        withRetry(() => this.ssUSD.balanceOf(validatedAddress)),
        withRetry(() => this.ssUSD.sharesOf(validatedAddress)),
        withRetry(() => this.wssUSD.balanceOf(validatedAddress)),
        withRetry(() => this.wssUSD.getssUSDValue(validatedAddress))
      ]);

      return {
        ssUSD: ssUSDBalance,
        ssUSDShares: ssUSDShares,
        wssUSD: wssUSDBalance,
        wssUSDValue: wssUSDValue
      };
    } catch (error) {
      throw wrapError(error, "Failed to get balance");
    }
  }

  /**
   * Get user's stablecoin balances with formatted values
   */
  async getFormattedBalance(address: string): Promise<FormattedUserBalance> {
    const balance = await this.getBalance(address);

    return {
      ...balance,
      formatted: {
        ssUSD: formatBalance(balance.ssUSD, 18, { suffix: " ssUSD" }),
        wssUSD: formatBalance(balance.wssUSD, 18, { suffix: " wssUSD" }),
        wssUSDValue: formatBalance(balance.wssUSDValue, 18, { suffix: " ssUSD" })
      }
    };
  }

  // =========================================================================
  // Statistics
  // =========================================================================

  /**
   * Get stablecoin system statistics
   */
  async getStats(): Promise<StablecoinStats> {
    try {
      const [
        totalSupply,
        totalShares,
        navPerShare,
        totalCollateral,
        collateralRatio
      ] = await Promise.all([
        withRetry(() => this.ssUSD.totalSupply()),
        withRetry(() => this.ssUSD.totalShares()),
        withRetry(() => this.ssUSD.getNavPerShare()),
        withRetry(() => this.treasury.getTotalCollateralValue()),
        withRetry(() => this.treasury.getCollateralRatio())
      ]);

      // Calculate APY from NAV history
      let apy = 0;
      try {
        const history = await this.navOracle.getNAVHistory(30);
        if (history.length >= 2) {
          const oldest = history[0];
          const newest = history[history.length - 1];
          const daysDiff = Number(newest.timestamp - oldest.timestamp) / 86400;
          if (daysDiff > 0) {
            const navChange = Number(newest.navPerShare - oldest.navPerShare) / Number(oldest.navPerShare);
            apy = (navChange / daysDiff) * 365 * 100;
          }
        }
      } catch {
        // No history available
      }

      return {
        totalSupply,
        totalShares,
        navPerShare,
        totalCollateral,
        collateralRatio,
        apy
      };
    } catch (error) {
      throw wrapError(error, "Failed to get stats");
    }
  }

  /**
   * Get current NAV report
   */
  async getCurrentNAV(): Promise<NAVReport> {
    try {
      const nav = await withRetry(() => this.navOracle.getCurrentNAV());
      return {
        totalAssets: nav.totalAssets,
        totalShares: nav.totalShares,
        navPerShare: nav.navPerShare,
        timestamp: nav.timestamp,
        reportDate: nav.reportDate,
        proofHash: nav.proofHash,
        attestor: nav.attestor
      };
    } catch (error) {
      throw wrapError(error, "Failed to get NAV");
    }
  }

  /**
   * Check if NAV is fresh (not stale)
   */
  async isNAVFresh(): Promise<boolean> {
    try {
      return await withRetry(() => this.navOracle.isNAVFresh());
    } catch (error) {
      throw wrapError(error, "Failed to check NAV freshness");
    }
  }

  /**
   * Assert NAV is fresh or throw
   */
  async assertNAVFresh(): Promise<void> {
    const isFresh = await this.isNAVFresh();
    if (!isFresh) {
      const nav = await this.getCurrentNAV();
      throw new NAVStaleError(nav.timestamp);
    }
  }

  // =========================================================================
  // Token Registry
  // =========================================================================

  /**
   * Get approved collateral tokens
   */
  async getCollateralTokens(): Promise<string[]> {
    try {
      return await withRetry(() => this.tokenRegistry.getCollateralTokens());
    } catch (error) {
      throw wrapError(error, "Failed to get collateral tokens");
    }
  }

  /**
   * Check if token is approved collateral
   */
  async isApprovedCollateral(token: string): Promise<boolean> {
    const validatedToken = validateAddress(token, "token");
    try {
      return await withRetry(() => this.tokenRegistry.isApprovedCollateral(validatedToken));
    } catch (error) {
      throw wrapError(error, "Failed to check collateral approval");
    }
  }

  /**
   * Get token info
   */
  async getTokenInfo(token: string): Promise<TokenInfo> {
    const validatedToken = validateAddress(token, "token");
    try {
      const info = await withRetry(() => this.tokenRegistry.getTokenInfo(validatedToken));
      return {
        tokenAddress: info.tokenAddress,
        name: info.name,
        symbol: info.symbol,
        decimals: info.decimals,
        logoURI: info.logoURI,
        category: info.category,
        trustLevel: info.trustLevel,
        isCollateral: info.isCollateral,
        addedAt: info.addedAt,
        updatedAt: info.updatedAt
      };
    } catch (error) {
      throw wrapError(error, "Failed to get token info");
    }
  }

  // =========================================================================
  // Utility
  // =========================================================================

  /**
   * Get wssUSD share price (ssUSD per wssUSD)
   */
  async getWssUSDSharePrice(): Promise<bigint> {
    try {
      return await withRetry(() => this.wssUSD.getSharePrice());
    } catch (error) {
      throw wrapError(error, "Failed to get share price");
    }
  }

  /**
   * Convert ssUSD amount to wssUSD
   */
  async convertToWssUSD(ssUSDAmount: bigint): Promise<bigint> {
    validatePositiveAmount(ssUSDAmount, "ssUSDAmount");
    try {
      return await withRetry(() => this.wssUSD.convertToShares(ssUSDAmount));
    } catch (error) {
      throw wrapError(error, "Failed to convert to wssUSD");
    }
  }

  /**
   * Convert wssUSD to ssUSD amount
   */
  async convertToSsUSD(wssUSDAmount: bigint): Promise<bigint> {
    validatePositiveAmount(wssUSDAmount, "wssUSDAmount");
    try {
      return await withRetry(() => this.wssUSD.convertToAssets(wssUSDAmount));
    } catch (error) {
      throw wrapError(error, "Failed to convert to ssUSD");
    }
  }

  /**
   * Get redemption delay in seconds
   */
  async getRedemptionDelay(): Promise<bigint> {
    try {
      return await withRetry(() => this.treasury.redemptionDelay());
    } catch (error) {
      throw wrapError(error, "Failed to get redemption delay");
    }
  }

  /**
   * Check if deposits are paused
   */
  async areDepositsPaused(): Promise<boolean> {
    try {
      return await withRetry(() => this.treasury.depositsPaused());
    } catch (error) {
      throw wrapError(error, "Failed to check deposit pause status");
    }
  }

  /**
   * Check if redemptions are paused
   */
  async areRedemptionsPaused(): Promise<boolean> {
    try {
      return await withRetry(() => this.treasury.redemptionsPaused());
    } catch (error) {
      throw wrapError(error, "Failed to check redemption pause status");
    }
  }
}

/**
 * Create a stablecoin client
 */
export function createStablecoinClient(
  addresses: StablecoinAddresses,
  privateKey: string,
  rpcUrl: string
): StablecoinClient {
  const provider = new JsonRpcProvider(rpcUrl);
  const signer = new Wallet(privateKey, provider);
  return new StablecoinClient(addresses, signer);
}
