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

export function createProvider(rpcUrl: string): JsonRpcProvider {
  return new JsonRpcProvider(rpcUrl);
}

export function createWallet(privateKey: string, rpcUrl: string): Wallet {
  return new Wallet(privateKey, createProvider(rpcUrl));
}

export function getSetRegistry(address: string, runner: JsonRpcProvider | Wallet): Contract {
  return new Contract(address, setRegistryAbi, runner);
}

export function getSetPaymaster(address: string, runner: JsonRpcProvider | Wallet): Contract {
  return new Contract(address, setPaymasterAbi, runner);
}

export function getThresholdKeyRegistry(address: string, runner: JsonRpcProvider | Wallet): Contract {
  return new Contract(address, thresholdKeyRegistryAbi, runner);
}

export function getSetTimelock(address: string, runner: JsonRpcProvider | Wallet): Contract {
  return new Contract(address, setTimelockAbi, runner);
}

export function getWssUSD(address: string, runner: JsonRpcProvider | Wallet): Contract {
  return new Contract(address, wssUsdAbi, runner);
}

export function getNAVOracle(address: string, runner: JsonRpcProvider | Wallet): Contract {
  return new Contract(address, navOracleAbi, runner);
}

export function getTreasuryVault(address: string, runner: JsonRpcProvider | Wallet): Contract {
  return new Contract(address, treasuryVaultAbi, runner);
}

export function getEncryptedMempool(address: string, runner: JsonRpcProvider | Wallet): Contract {
  return new Contract(address, encryptedMempoolAbi, runner);
}

export function getForcedInclusion(address: string, runner: JsonRpcProvider | Wallet): Contract {
  return new Contract(address, forcedInclusionAbi, runner);
}

export function getSequencerAttestation(address: string, runner: JsonRpcProvider | Wallet): Contract {
  return new Contract(address, sequencerAttestationAbi, runner);
}

/**
 * Get ssUSD contract instance
 * @param address Contract address
 * @param runner Provider or wallet
 */
export function getSsUSD(address: string, runner: JsonRpcProvider | Wallet): Contract {
  return new Contract(address, ssUsdAbi, runner);
}
