import { Contract, JsonRpcProvider, Wallet } from "ethers";
import { setRegistryAbi } from "../abis/registry.js";
import { setPaymasterAbi } from "../abis/paymaster.js";
import { thresholdKeyRegistryAbi } from "../abis/threshold-key-registry.js";
import { setTimelockAbi } from "../abis/timelock.js";
import { wssUsdAbi } from "../abis/wss-usd.js";
import { navOracleAbi } from "../abis/nav-oracle.js";
import { treasuryVaultAbi } from "../abis/treasury-vault.js";
import { encryptedMempoolAbi } from "../abis/encrypted-mempool.js";
import { forcedInclusionAbi } from "../abis/forced-inclusion.js";
import { sequencerAttestationAbi } from "../abis/sequencer-attestation.js";
import { ssUsdAbi } from "../abis/ss-usd.js";
import { InvalidAddressError } from "../errors.js";

/**
 * Validate an Ethereum address format
 */
function assertValidAddress(address: string, label: string): void {
  if (!address || !address.match(/^0x[0-9a-fA-F]{40}$/)) {
    throw new InvalidAddressError(address, `${label} must be a valid Ethereum address (0x + 40 hex chars)`);
  }
}

/**
 * Create a JSON-RPC provider for Set Chain
 * @param rpcUrl RPC endpoint URL (must start with http:// or https://)
 */
export function createProvider(rpcUrl: string): JsonRpcProvider {
  if (!rpcUrl || (!rpcUrl.startsWith("http://") && !rpcUrl.startsWith("https://"))) {
    throw new Error(`Invalid RPC URL: must start with http:// or https://, got: ${rpcUrl}`);
  }
  return new JsonRpcProvider(rpcUrl);
}

/**
 * Create a wallet connected to a Set Chain provider
 * @param privateKey Wallet private key (0x + 64 hex chars)
 * @param rpcUrl RPC endpoint URL
 */
export function createWallet(privateKey: string, rpcUrl: string): Wallet {
  if (!privateKey) {
    throw new Error("Private key is required");
  }
  return new Wallet(privateKey, createProvider(rpcUrl));
}

export function getSetRegistry(address: string, runner: JsonRpcProvider | Wallet): Contract {
  assertValidAddress(address, "SetRegistry address");
  return new Contract(address, setRegistryAbi, runner);
}

export function getSetPaymaster(address: string, runner: JsonRpcProvider | Wallet): Contract {
  assertValidAddress(address, "SetPaymaster address");
  return new Contract(address, setPaymasterAbi, runner);
}

export function getThresholdKeyRegistry(address: string, runner: JsonRpcProvider | Wallet): Contract {
  assertValidAddress(address, "ThresholdKeyRegistry address");
  return new Contract(address, thresholdKeyRegistryAbi, runner);
}

export function getSetTimelock(address: string, runner: JsonRpcProvider | Wallet): Contract {
  assertValidAddress(address, "SetTimelock address");
  return new Contract(address, setTimelockAbi, runner);
}

export function getWssUSD(address: string, runner: JsonRpcProvider | Wallet): Contract {
  assertValidAddress(address, "wssUSD address");
  return new Contract(address, wssUsdAbi, runner);
}

export function getNAVOracle(address: string, runner: JsonRpcProvider | Wallet): Contract {
  assertValidAddress(address, "NAVOracle address");
  return new Contract(address, navOracleAbi, runner);
}

export function getTreasuryVault(address: string, runner: JsonRpcProvider | Wallet): Contract {
  assertValidAddress(address, "TreasuryVault address");
  return new Contract(address, treasuryVaultAbi, runner);
}

export function getEncryptedMempool(address: string, runner: JsonRpcProvider | Wallet): Contract {
  assertValidAddress(address, "EncryptedMempool address");
  return new Contract(address, encryptedMempoolAbi, runner);
}

export function getForcedInclusion(address: string, runner: JsonRpcProvider | Wallet): Contract {
  assertValidAddress(address, "ForcedInclusion address");
  return new Contract(address, forcedInclusionAbi, runner);
}

export function getSequencerAttestation(address: string, runner: JsonRpcProvider | Wallet): Contract {
  assertValidAddress(address, "SequencerAttestation address");
  return new Contract(address, sequencerAttestationAbi, runner);
}

/**
 * Get ssUSD contract instance
 * @param address Contract address
 * @param runner Provider or wallet
 */
export function getSsUSD(address: string, runner: JsonRpcProvider | Wallet): Contract {
  assertValidAddress(address, "ssUSD address");
  return new Contract(address, ssUsdAbi, runner);
}
