//! Main anchor service implementation

use std::sync::Arc;
use std::time::Duration;

use alloy::{primitives::{Address, U256}, providers::Provider, transports::http::Http};
use anyhow::Result;
use chrono::Utc;
use tokio::sync::RwLock;
use tracing::{debug, error, info, warn};

use crate::{
    client::{create_provider, RegistryClient, SequencerApiClient},
    config::AnchorConfig,
    error::{AnchorError, AuthorizationError, ConfigError, L2Error, SequencerApiError, TransactionError},
    health::HealthState,
    types::{AnchorNotification, AnchorResult, AnchorStats, BatchCommitment, CircuitBreaker, CircuitBreakerState, ErrorType},
};

type HttpTransport = Http<reqwest::Client>;

/// Anchor service that bridges sequencer to on-chain registry
pub struct AnchorService {
    config: AnchorConfig,
    sequencer_client: SequencerApiClient,
    stats: Arc<RwLock<AnchorStats>>,
    health_state: Option<Arc<HealthState>>,
    circuit_breaker: Arc<RwLock<CircuitBreaker>>,
}

impl AnchorService {
    /// Create a new anchor service
    pub fn new(config: AnchorConfig) -> Self {
        let sequencer_client = SequencerApiClient::new_with_timeouts(
            &config.sequencer_api_url,
            Duration::from_secs(config.sequencer_request_timeout_secs),
            Duration::from_secs(config.sequencer_connect_timeout_secs),
        );
        let mut circuit_breaker = CircuitBreaker::new(
            config.circuit_breaker_failure_threshold,
            config.circuit_breaker_reset_timeout_secs,
        );
        circuit_breaker.half_open_success_threshold = config.circuit_breaker_half_open_success_threshold;

        Self {
            config,
            sequencer_client,
            stats: Arc::new(RwLock::new(AnchorStats::default())),
            health_state: None,
            circuit_breaker: Arc::new(RwLock::new(circuit_breaker)),
        }
    }

    /// Create anchor service with health state for monitoring
    pub fn with_health_state(config: AnchorConfig, health_state: Arc<HealthState>) -> Self {
        let sequencer_client = SequencerApiClient::new_with_timeouts(
            &config.sequencer_api_url,
            Duration::from_secs(config.sequencer_request_timeout_secs),
            Duration::from_secs(config.sequencer_connect_timeout_secs),
        );
        let mut circuit_breaker = CircuitBreaker::new(
            config.circuit_breaker_failure_threshold,
            config.circuit_breaker_reset_timeout_secs,
        );
        circuit_breaker.half_open_success_threshold = config.circuit_breaker_half_open_success_threshold;

        Self {
            config,
            sequencer_client,
            stats: health_state.stats.clone(),
            health_state: Some(health_state),
            circuit_breaker: Arc::new(RwLock::new(circuit_breaker)),
        }
    }

    /// Get shared stats reference (for health server)
    pub fn stats_ref(&self) -> Arc<RwLock<AnchorStats>> {
        Arc::clone(&self.stats)
    }

    async fn record_error(&self, error: AnchorError) {
        if let Some(ref health) = self.health_state {
            health.record_error(&error).await;
        }
    }

    async fn update_circuit_breaker_state(&self, state: CircuitBreakerState) {
        let mut stats = self.stats.write().await;
        stats.circuit_breaker_state = state;
    }

    async fn record_success(&self, commitment: &BatchCommitment, anchor_time_ms: u64) {
        let state = {
            let mut breaker = self.circuit_breaker.write().await;
            breaker.record_success();
            breaker.state
        };

        let mut stats = self.stats.write().await;
        stats.record_success(anchor_time_ms);
        stats.total_events_anchored += commitment.event_count as u64;
        stats.last_batch_id = Some(commitment.batch_id);
        stats.circuit_breaker_state = state;
    }

    async fn record_failure(&self, error_type: ErrorType) {
        let consecutive_failures = {
            let mut stats = self.stats.write().await;
            stats.record_failure(error_type);
            stats.consecutive_failures
        };

        let state = {
            let mut breaker = self.circuit_breaker.write().await;
            breaker.record_failure(consecutive_failures);
            breaker.state
        };

        let mut stats = self.stats.write().await;
        stats.circuit_breaker_state = state;
    }

    /// Run the anchor service loop
    pub async fn run(&self) -> Result<()> {
        info!(
            l2_rpc = %self.config.l2_rpc_url,
            registry = %self.config.set_registry_address,
            interval = self.config.anchor_interval_secs,
            "Starting Set Chain anchor service"
        );

        {
            let mut stats = self.stats.write().await;
            if stats.service_started.is_none() {
                stats.service_started = Some(Utc::now());
            }
        }

        // Create provider and registry client
        let provider = match create_provider(
            &self.config.l2_rpc_url,
            &self.config.sequencer_private_key,
        ).await {
            Ok(provider) => provider,
            Err(e) => {
                self.record_error(AnchorError::Config(ConfigError::InvalidValue {
                    field: "provider".to_string(),
                    message: e.to_string(),
                })).await;
                return Err(e);
            }
        };

        let chain_id = match provider.get_chain_id().await {
            Ok(chain_id) => chain_id,
            Err(e) => {
                self.record_error(AnchorError::L2Connection(L2Error::RpcError(e.to_string()))).await;
                self.record_failure(ErrorType::L2Connection).await;
                return Err(e.into());
            }
        };

        if self.config.expected_l2_chain_id > 0 && chain_id != self.config.expected_l2_chain_id {
            self.record_error(AnchorError::L2Connection(L2Error::ChainIdMismatch {
                expected: self.config.expected_l2_chain_id,
                actual: chain_id,
            })).await;
            self.record_failure(ErrorType::L2Connection).await;
            anyhow::bail!(
                "L2 chain ID mismatch: expected {}, got {}",
                self.config.expected_l2_chain_id,
                chain_id
            );
        }
        info!(chain_id = chain_id, "Connected to Set Chain");

        let registry_address: Address = self.config.set_registry_address.parse()?;
        let registry = RegistryClient::new(registry_address, provider, chain_id);

        // Verify sequencer authorization
        let signer_address = self.get_signer_address()?;
        let is_authorized = match registry.is_authorized(signer_address).await {
            Ok(is_authorized) => is_authorized,
            Err(e) => {
                self.record_error(AnchorError::Authorization(AuthorizationError::CheckFailed(
                    e.to_string(),
                ))).await;
                return Err(e);
            }
        };

        if !is_authorized {
            self.record_error(AnchorError::Authorization(AuthorizationError::NotAuthorized {
                address: format!("{:?}", signer_address),
            })).await;
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

        // Mark as ready and L2 healthy
        if let Some(ref health) = self.health_state {
            health.set_ready(true).await;
            health.mark_l2_healthy().await;
        }
        {
            let mut stats = self.stats.write().await;
            stats.mark_l2_healthy();
        }

        // Main loop
        loop {
            {
                let mut stats = self.stats.write().await;
                stats.total_cycles += 1;
            }

            let (allow_request, breaker_state) = {
                let mut breaker = self.circuit_breaker.write().await;
                let allow = breaker.allow_request();
                (allow, breaker.state)
            };

            if !allow_request {
                {
                    let mut stats = self.stats.write().await;
                    stats.circuit_breaker_state = breaker_state;
                    stats.circuit_breaker_open_skips += 1;
                }
                warn!(
                    state = breaker_state.as_str(),
                    "Circuit breaker open; skipping anchor cycle"
                );
                tokio::time::sleep(Duration::from_secs(self.config.anchor_interval_secs)).await;
                continue;
            }

            self.update_circuit_breaker_state(breaker_state).await;

            match self.anchor_pending(&registry).await {
                Ok(results) => {
                    // Mark L2 as healthy on successful cycle
                    if let Some(ref health) = self.health_state {
                        health.mark_l2_healthy().await;
                    }
                    {
                        let mut stats = self.stats.write().await;
                        stats.mark_l2_healthy();
                    }

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
                    self.record_error(AnchorError::Internal(format!(
                        "Anchor cycle failed: {}",
                        e
                    ))).await;
                    self.record_failure(ErrorType::Other).await;
                    error!(error = %e, "Anchor cycle failed");
                }
            }

            tokio::time::sleep(Duration::from_secs(self.config.anchor_interval_secs)).await;
        }
    }

    /// Anchor all pending commitments
    async fn anchor_pending<P: Provider<HttpTransport> + Clone>(
        &self,
        registry: &RegistryClient<P>,
    ) -> Result<Vec<AnchorResult>> {
        if self.config.max_gas_price_gwei > 0 {
            let gas_price = match registry.gas_price().await {
                Ok(gas_price) => gas_price,
                Err(e) => {
                    self.record_error(AnchorError::L2Connection(L2Error::GasPriceError(
                        e.to_string(),
                    ))).await;
                    self.record_failure(ErrorType::L2Connection).await;
                    warn!(error = %e, "Failed to fetch gas price");
                    return Ok(vec![]);
                }
            };
            let max_gas_price = U256::from(self.config.max_gas_price_gwei)
                * U256::from(1_000_000_000u64);

            if gas_price > max_gas_price {
                {
                    let mut stats = self.stats.write().await;
                    stats.record_gas_skip();
                }
                warn!(
                    gas_price = %gas_price,
                    max_gas_price = %max_gas_price,
                    "Skipping anchor cycle: gas price above configured maximum"
                );
                return Ok(vec![]);
            }
        }

        // Fetch pending commitments from sequencer
        let mut commitments = match self.sequencer_client.get_pending_commitments().await {
            Ok(c) => {
                // Mark sequencer as healthy on successful fetch
                if let Some(ref health) = self.health_state {
                    health.mark_sequencer_healthy().await;
                }
                {
                    let mut stats = self.stats.write().await;
                    stats.mark_sequencer_healthy();
                }
                c
            }
            Err(e) => {
                self.record_failure(ErrorType::SequencerApi).await;
                self.record_error(AnchorError::SequencerApi(
                    SequencerApiError::ConnectionFailed {
                        url: self.config.sequencer_api_url.clone(),
                        message: e.to_string(),
                    },
                )).await;
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

        if self.config.max_commitments_per_cycle > 0 {
            let limit = self.config.max_commitments_per_cycle as usize;
            if commitments.len() > limit {
                info!(
                    limit = limit,
                    total = commitments.len(),
                    "Limiting commitments to max per cycle"
                );
                commitments.truncate(limit);
            }
        }

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
    async fn anchor_with_retry<P: Provider<HttpTransport> + Clone>(
        &self,
        registry: &RegistryClient<P>,
        commitment: &BatchCommitment,
    ) -> AnchorResult {
        let mut last_error = None;

        for attempt in 1..=self.config.max_retries {
            let start = std::time::Instant::now();
            match self.anchor_commitment(registry, commitment).await {
                Ok(result) => {
                    self.record_success(commitment, start.elapsed().as_millis() as u64).await;

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
        self.record_failure(ErrorType::Transaction).await;

        let error_message = last_error.unwrap_or_else(|| "unknown error".to_string());
        self.record_error(AnchorError::Transaction(TransactionError::SubmissionFailed(
            error_message.clone(),
        ))).await;

        AnchorResult {
            batch_id: commitment.batch_id,
            tx_hash: String::new(),
            block_number: 0,
            gas_used: 0,
            success: false,
            error: Some(error_message),
        }
    }

    /// Anchor a single commitment
    async fn anchor_commitment<P: Provider<HttpTransport> + Clone>(
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
            {
                let mut stats = self.stats.write().await;
                stats.sequencer_api_failures += 1;
            }
            self.record_error(AnchorError::SequencerApi(
                SequencerApiError::NotificationFailed(e.to_string()),
            ))
            .await;
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
