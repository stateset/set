//! Main anchor service implementation

use std::sync::Arc;
use std::time::Duration;

use alloy::{primitives::Address, providers::Provider};
use anyhow::Result;
use chrono::Utc;
use tokio::sync::RwLock;
use tracing::{debug, error, info, warn};

use crate::{
    client::{create_provider, RegistryClient, SequencerApiClient},
    config::AnchorConfig,
    types::{AnchorNotification, AnchorResult, AnchorStats, BatchCommitment},
};

/// Anchor service that bridges sequencer to on-chain registry
pub struct AnchorService {
    config: AnchorConfig,
    sequencer_client: SequencerApiClient,
    stats: Arc<RwLock<AnchorStats>>,
}

impl AnchorService {
    /// Create a new anchor service
    pub fn new(config: AnchorConfig) -> Self {
        let sequencer_client = SequencerApiClient::new(&config.sequencer_api_url);

        Self {
            config,
            sequencer_client,
            stats: Arc::new(RwLock::new(AnchorStats::default())),
        }
    }

    /// Run the anchor service loop
    pub async fn run(&self) -> Result<()> {
        info!(
            l2_rpc = %self.config.l2_rpc_url,
            registry = %self.config.set_registry_address,
            interval = self.config.anchor_interval_secs,
            "Starting Set Chain anchor service"
        );

        // Create provider and registry client
        let provider = create_provider(
            &self.config.l2_rpc_url,
            &self.config.sequencer_private_key,
        ).await?;

        let chain_id = provider.get_chain_id().await?;
        info!(chain_id = chain_id, "Connected to Set Chain");

        let registry_address: Address = self.config.set_registry_address.parse()?;
        let registry = RegistryClient::new(registry_address, provider, chain_id);

        // Verify sequencer authorization
        let signer_address = self.get_signer_address()?;
        let is_authorized = registry.is_authorized(signer_address).await?;

        if !is_authorized {
            error!(
                address = %signer_address,
                "Sequencer address not authorized in SetRegistry"
            );
            anyhow::bail!("Sequencer not authorized");
        }

        info!(
            address = %signer_address,
            "Sequencer authorization verified"
        );

        // Main loop
        loop {
            match self.anchor_pending(&registry).await {
                Ok(results) => {
                    let successful = results.iter().filter(|r| r.success).count();
                    let failed = results.iter().filter(|r| !r.success).count();

                    if !results.is_empty() {
                        info!(
                            successful = successful,
                            failed = failed,
                            "Anchor cycle complete"
                        );
                    }
                }
                Err(e) => {
                    error!(error = %e, "Anchor cycle failed");
                }
            }

            tokio::time::sleep(Duration::from_secs(self.config.anchor_interval_secs)).await;
        }
    }

    /// Anchor all pending commitments
    async fn anchor_pending<P: Provider + Clone>(
        &self,
        registry: &RegistryClient<P>,
    ) -> Result<Vec<AnchorResult>> {
        // Fetch pending commitments from sequencer
        let commitments = match self.sequencer_client.get_pending_commitments().await {
            Ok(c) => c,
            Err(e) => {
                debug!(error = %e, "Failed to fetch pending commitments");
                return Ok(vec![]);
            }
        };

        if commitments.is_empty() {
            debug!("No pending commitments to anchor");
            return Ok(vec![]);
        }

        info!(
            count = commitments.len(),
            "Found pending commitments"
        );

        let mut results = Vec::new();

        for commitment in commitments {
            // Check minimum event threshold
            if commitment.event_count < self.config.min_events_for_anchor {
                debug!(
                    batch_id = %commitment.batch_id,
                    event_count = commitment.event_count,
                    min_required = self.config.min_events_for_anchor,
                    "Skipping batch: below minimum event threshold"
                );
                continue;
            }

            // Anchor with retries
            let result = self.anchor_with_retry(registry, &commitment).await;
            results.push(result);
        }

        Ok(results)
    }

    /// Anchor a single commitment with retries
    async fn anchor_with_retry<P: Provider + Clone>(
        &self,
        registry: &RegistryClient<P>,
        commitment: &BatchCommitment,
    ) -> AnchorResult {
        let mut last_error = None;

        for attempt in 1..=self.config.max_retries {
            match self.anchor_commitment(registry, commitment).await {
                Ok(result) => {
                    // Update stats
                    let mut stats = self.stats.write().await;
                    stats.total_anchored += 1;
                    stats.total_events_anchored += commitment.event_count as u64;
                    stats.last_anchor_time = Some(Utc::now());
                    stats.last_batch_id = Some(commitment.batch_id);

                    return result;
                }
                Err(e) => {
                    warn!(
                        batch_id = %commitment.batch_id,
                        attempt = attempt,
                        max_retries = self.config.max_retries,
                        error = %e,
                        "Anchor attempt failed"
                    );
                    last_error = Some(e.to_string());

                    if attempt < self.config.max_retries {
                        tokio::time::sleep(Duration::from_secs(
                            self.config.retry_delay_secs * attempt as u64,
                        ))
                        .await;
                    }
                }
            }
        }

        // All retries failed
        let mut stats = self.stats.write().await;
        stats.total_failed += 1;

        AnchorResult {
            batch_id: commitment.batch_id,
            tx_hash: String::new(),
            block_number: 0,
            gas_used: 0,
            success: false,
            error: last_error,
        }
    }

    /// Anchor a single commitment
    async fn anchor_commitment<P: Provider + Clone>(
        &self,
        registry: &RegistryClient<P>,
        commitment: &BatchCommitment,
    ) -> Result<AnchorResult> {
        info!(
            batch_id = %commitment.batch_id,
            sequence_range = ?(commitment.sequence_start, commitment.sequence_end),
            event_count = commitment.event_count,
            "Anchoring commitment"
        );

        // Submit to chain
        let (tx_hash, block_number, gas_used) = registry.commit_batch(commitment).await?;

        let tx_hash_hex = format!("0x{}", hex::encode(tx_hash.as_slice()));

        // Notify sequencer of successful anchoring
        let notification = AnchorNotification {
            chain_tx_hash: tx_hash_hex.clone(),
            chain_id: registry.chain_id(),
            block_number: Some(block_number),
            gas_used: Some(gas_used),
        };

        if let Err(e) = self
            .sequencer_client
            .notify_anchored(commitment.batch_id, &notification)
            .await
        {
            warn!(
                batch_id = %commitment.batch_id,
                error = %e,
                "Failed to notify sequencer of anchoring"
            );
            // Don't fail the anchor - the on-chain tx succeeded
        }

        info!(
            batch_id = %commitment.batch_id,
            tx_hash = %tx_hash_hex,
            block_number = block_number,
            gas_used = gas_used,
            "Commitment anchored successfully"
        );

        Ok(AnchorResult {
            batch_id: commitment.batch_id,
            tx_hash: tx_hash_hex,
            block_number,
            gas_used,
            success: true,
            error: None,
        })
    }

    /// Get signer address from private key
    fn get_signer_address(&self) -> Result<Address> {
        use alloy::signers::local::PrivateKeySigner;

        let signer: PrivateKeySigner = self.config.sequencer_private_key.parse()?;
        Ok(signer.address())
    }

    /// Get current statistics
    pub async fn stats(&self) -> AnchorStats {
        self.stats.read().await.clone()
    }
}
