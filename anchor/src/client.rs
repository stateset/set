//! Client for interacting with SetRegistry contract and sequencer API

use std::time::Duration;

use alloy::{
    network::EthereumWallet,
    primitives::{Address, FixedBytes, U256},
    providers::{Provider, ProviderBuilder},
    signers::local::PrivateKeySigner,
    sol,
    transports::http::Http,
};
use anyhow::Result;
use tracing::{debug, info, warn};
use uuid::Uuid;

use crate::types::{AnchorNotification, BatchCommitment, PendingCommitmentsResponse};

// Generate contract bindings for SetRegistry
sol!(
    #[allow(missing_docs)]
    #[sol(rpc)]
    SetRegistry,
    r#"[
        {
            "type": "function",
            "name": "commitBatch",
            "inputs": [
                {"name": "_batchId", "type": "bytes32"},
                {"name": "_tenantId", "type": "bytes32"},
                {"name": "_storeId", "type": "bytes32"},
                {"name": "_eventsRoot", "type": "bytes32"},
                {"name": "_prevStateRoot", "type": "bytes32"},
                {"name": "_newStateRoot", "type": "bytes32"},
                {"name": "_sequenceStart", "type": "uint64"},
                {"name": "_sequenceEnd", "type": "uint64"},
                {"name": "_eventCount", "type": "uint32"}
            ],
            "outputs": [],
            "stateMutability": "nonpayable"
        },
        {
            "type": "function",
            "name": "totalCommitments",
            "inputs": [],
            "outputs": [{"type": "uint256"}],
            "stateMutability": "view"
        },
        {
            "type": "function",
            "name": "authorizedSequencers",
            "inputs": [{"name": "", "type": "address"}],
            "outputs": [{"type": "bool"}],
            "stateMutability": "view"
        },
        {
            "type": "event",
            "name": "BatchCommitted",
            "anonymous": false,
            "inputs": [
                {"name": "batchId", "type": "bytes32", "indexed": true},
                {"name": "tenantStoreKey", "type": "bytes32", "indexed": true},
                {"name": "eventsRoot", "type": "bytes32"},
                {"name": "newStateRoot", "type": "bytes32"},
                {"name": "sequenceStart", "type": "uint64"},
                {"name": "sequenceEnd", "type": "uint64"},
                {"name": "eventCount", "type": "uint32"}
            ]
        }
    ]"#
);

type HttpTransport = Http<reqwest::Client>;

/// Client for SetRegistry contract interactions
pub struct RegistryClient<P> {
    contract: SetRegistry::SetRegistryInstance<HttpTransport, P>,
    provider: P,
    chain_id: u64,
}

impl<P: Provider<HttpTransport> + Clone> RegistryClient<P> {
    /// Create a new registry client
    pub fn new(address: Address, provider: P, chain_id: u64) -> Self {
        let contract = SetRegistry::new(address, provider.clone());
        Self { contract, provider, chain_id }
    }

    /// Check if an address is authorized as a sequencer
    pub async fn is_authorized(&self, address: Address) -> Result<bool> {
        let result = self.contract.authorizedSequencers(address).call().await?;
        Ok(result._0)
    }

    /// Get total number of commitments
    pub async fn total_commitments(&self) -> Result<U256> {
        let result = self.contract.totalCommitments().call().await?;
        Ok(result._0)
    }

    /// Commit a batch to the registry
    pub async fn commit_batch(
        &self,
        commitment: &BatchCommitment,
    ) -> Result<(FixedBytes<32>, u64, u64)> {
        // Convert UUIDs to bytes32
        let batch_id = uuid_to_bytes32(&commitment.batch_id);
        let tenant_id = uuid_to_bytes32(&commitment.tenant_id);
        let store_id = uuid_to_bytes32(&commitment.store_id);

        // Parse hex roots
        let events_root = parse_bytes32(&commitment.events_root)?;
        let prev_state_root = parse_bytes32(&commitment.prev_state_root)?;
        let new_state_root = parse_bytes32(&commitment.new_state_root)?;

        debug!(
            batch_id = %commitment.batch_id,
            sequence_range = ?(commitment.sequence_start, commitment.sequence_end),
            "Submitting batch commitment"
        );

        // Build and send transaction
        let tx = self.contract.commitBatch(
            batch_id,
            tenant_id,
            store_id,
            events_root,
            prev_state_root,
            new_state_root,
            commitment.sequence_start,
            commitment.sequence_end,
            commitment.event_count,
        );

        let pending = tx.send().await?;
        let receipt = pending.get_receipt().await?;

        let tx_hash = receipt.transaction_hash;
        let block_number = receipt.block_number.unwrap_or(0);
        let gas_used = receipt.gas_used;

        info!(
            tx_hash = %tx_hash,
            block_number = block_number,
            gas_used = gas_used,
            "Batch committed successfully"
        );

        Ok((tx_hash, block_number, gas_used as u64))
    }

    /// Get chain ID
    pub fn chain_id(&self) -> u64 {
        self.chain_id
    }

    /// Get current gas price from provider
    pub async fn gas_price(&self) -> Result<U256> {
        Ok(U256::from(self.provider.get_gas_price().await?))
    }
}

/// Client for stateset-sequencer API
pub struct SequencerApiClient {
    base_url: String,
    client: reqwest::Client,
}

impl SequencerApiClient {
    const DEFAULT_REQUEST_TIMEOUT_SECS: u64 = 10;
    const DEFAULT_CONNECT_TIMEOUT_SECS: u64 = 3;

    /// Create a new sequencer API client
    pub fn new(base_url: &str) -> Self {
        Self::new_with_timeouts(
            base_url,
            Duration::from_secs(Self::DEFAULT_REQUEST_TIMEOUT_SECS),
            Duration::from_secs(Self::DEFAULT_CONNECT_TIMEOUT_SECS),
        )
    }

    /// Create a new sequencer API client with timeouts
    pub fn new_with_timeouts(
        base_url: &str,
        request_timeout: Duration,
        connect_timeout: Duration,
    ) -> Self {
        let client = reqwest::Client::builder()
            .timeout(request_timeout)
            .connect_timeout(connect_timeout)
            .build()
            .unwrap_or_else(|err| {
                warn!(
                    error = %err,
                    "Failed to build sequencer HTTP client with timeouts; falling back to defaults"
                );
                reqwest::Client::new()
            });

        Self {
            base_url: base_url.trim_end_matches('/').to_string(),
            client,
        }
    }

    /// Fetch pending commitments that need anchoring
    pub async fn get_pending_commitments(&self) -> Result<Vec<BatchCommitment>> {
        let url = format!("{}/v1/commitments/pending", self.base_url);

        let response = self.client.get(&url).send().await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            anyhow::bail!("Failed to fetch pending commitments: {} - {}", status, body);
        }

        let data: PendingCommitmentsResponse = response.json().await?;
        Ok(data.commitments)
    }

    /// Notify sequencer that a commitment was anchored
    pub async fn notify_anchored(
        &self,
        batch_id: Uuid,
        notification: &AnchorNotification,
    ) -> Result<()> {
        let url = format!("{}/v1/commitments/{}/anchored", self.base_url, batch_id);

        let response = self.client
            .post(&url)
            .json(notification)
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            anyhow::bail!("Failed to notify anchoring: {} - {}", status, body);
        }

        Ok(())
    }

    /// Health check
    pub async fn health(&self) -> Result<bool> {
        let url = format!("{}/health", self.base_url);
        let response = self.client.get(&url).send().await?;
        Ok(response.status().is_success())
    }
}

/// Create a provider with signer for the given config
pub async fn create_provider(
    rpc_url: &str,
    private_key: &str,
) -> Result<impl Provider<HttpTransport> + Clone> {
    let signer: PrivateKeySigner = private_key.parse()?;
    let wallet = EthereumWallet::from(signer);

    let provider = ProviderBuilder::new()
        .with_recommended_fillers()
        .wallet(wallet)
        .on_http(rpc_url.parse()?);

    Ok(provider)
}

// Helper functions

fn uuid_to_bytes32(uuid: &Uuid) -> FixedBytes<32> {
    let mut bytes = [0u8; 32];
    bytes[..16].copy_from_slice(uuid.as_bytes());
    FixedBytes::from(bytes)
}

fn parse_bytes32(hex_str: &str) -> Result<FixedBytes<32>> {
    let hex_str = hex_str.strip_prefix("0x").unwrap_or(hex_str);

    if hex_str.is_empty() || hex_str.chars().all(|c| c == '0') {
        return Ok(FixedBytes::ZERO);
    }

    let bytes = hex::decode(hex_str)?;

    if bytes.len() != 32 {
        anyhow::bail!("Invalid bytes32 length: expected 32, got {}", bytes.len());
    }

    let mut arr = [0u8; 32];
    arr.copy_from_slice(&bytes);
    Ok(FixedBytes::from(arr))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_uuid_to_bytes32() {
        let uuid = Uuid::new_v4();
        let bytes = uuid_to_bytes32(&uuid);
        assert_eq!(&bytes[..16], uuid.as_bytes());
    }

    #[test]
    fn test_parse_bytes32() {
        let hex = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
        let result = parse_bytes32(hex).unwrap();
        assert_eq!(result.len(), 32);
    }

    #[test]
    fn test_parse_zero_bytes32() {
        let result = parse_bytes32("").unwrap();
        assert_eq!(result, FixedBytes::ZERO);
    }
}
