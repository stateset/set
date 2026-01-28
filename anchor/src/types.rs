//! Types for the anchor service

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Batch commitment from stateset-sequencer
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BatchCommitment {
    /// Unique batch identifier
    pub batch_id: Uuid,

    /// Tenant identifier
    pub tenant_id: Uuid,

    /// Store identifier
    pub store_id: Uuid,

    /// State root before applying this batch
    pub prev_state_root: String,

    /// State root after applying this batch
    pub new_state_root: String,

    /// Merkle root of events in this batch
    pub events_root: String,

    /// First sequence number in batch
    pub sequence_start: u64,

    /// Last sequence number in batch
    pub sequence_end: u64,

    /// Number of events in batch
    pub event_count: u32,

    /// When this commitment was created
    pub committed_at: DateTime<Utc>,

    /// On-chain transaction hash (if anchored)
    pub chain_tx_hash: Option<String>,
}

/// Response from sequencer API listing pending commitments
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PendingCommitmentsResponse {
    pub commitments: Vec<BatchCommitment>,
    pub total: usize,
}

/// Request to notify sequencer of successful anchoring
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnchorNotification {
    pub chain_tx_hash: String,
    pub chain_id: u64,
    pub block_number: Option<u64>,
    pub gas_used: Option<u64>,
}

/// Result of an anchor operation
#[derive(Debug, Clone)]
pub struct AnchorResult {
    pub batch_id: Uuid,
    pub tx_hash: String,
    pub block_number: u64,
    pub gas_used: u64,
    pub success: bool,
    pub error: Option<String>,
}

/// Anchor service statistics
#[derive(Debug, Clone, Default)]
pub struct AnchorStats {
    pub total_anchored: u64,
    pub total_failed: u64,
    pub total_events_anchored: u64,
    pub last_anchor_time: Option<DateTime<Utc>>,
    pub last_batch_id: Option<Uuid>,
    /// Consecutive failures (resets on success)
    pub consecutive_failures: u64,
    /// Total L2 connection failures
    pub l2_connection_failures: u64,
    /// Total sequencer API failures
    pub sequencer_api_failures: u64,
    /// Total gas-related skips
    pub gas_price_skips: u64,
    /// Average anchor time in milliseconds
    pub avg_anchor_time_ms: u64,
    /// Last successful L2 connection time
    pub last_l2_healthy: Option<DateTime<Utc>>,
    /// Last successful sequencer connection time
    pub last_sequencer_healthy: Option<DateTime<Utc>>,
    /// Service start time
    pub service_started: Option<DateTime<Utc>>,
    /// Total cycles completed
    pub total_cycles: u64,
    /// Circuit breaker state
    pub circuit_breaker_state: CircuitBreakerState,
    /// Total cycles skipped due to open circuit breaker
    pub circuit_breaker_open_skips: u64,
}

impl AnchorStats {
    /// Record a successful anchor
    pub fn record_success(&mut self, anchor_time_ms: u64) {
        self.total_anchored += 1;
        self.consecutive_failures = 0;
        self.last_anchor_time = Some(Utc::now());

        // Update running average
        if self.total_anchored == 1 {
            self.avg_anchor_time_ms = anchor_time_ms;
        } else {
            // Exponential moving average (weight new samples more)
            self.avg_anchor_time_ms = (self.avg_anchor_time_ms * 9 + anchor_time_ms) / 10;
        }
    }

    /// Record a failed anchor
    pub fn record_failure(&mut self, error_type: ErrorType) {
        self.total_failed += 1;
        self.consecutive_failures += 1;

        match error_type {
            ErrorType::L2Connection => self.l2_connection_failures += 1,
            ErrorType::SequencerApi => self.sequencer_api_failures += 1,
            ErrorType::Transaction => {}
            ErrorType::Other => {}
        }
    }

    /// Record a gas price skip
    pub fn record_gas_skip(&mut self) {
        self.gas_price_skips += 1;
    }

    /// Mark L2 as healthy
    pub fn mark_l2_healthy(&mut self) {
        self.last_l2_healthy = Some(Utc::now());
    }

    /// Mark sequencer as healthy
    pub fn mark_sequencer_healthy(&mut self) {
        self.last_sequencer_healthy = Some(Utc::now());
    }

    /// Get uptime percentage
    pub fn uptime_percent(&self) -> f64 {
        if self.total_cycles == 0 {
            return 100.0;
        }
        let successful = self.total_cycles - self.total_failed;
        (successful as f64 / self.total_cycles as f64) * 100.0
    }

    /// Check if circuit breaker should trip
    pub fn should_trip_circuit_breaker(&self, threshold: u64) -> bool {
        self.consecutive_failures >= threshold
    }
}

/// Type of error for categorization
#[derive(Debug, Clone, Copy)]
pub enum ErrorType {
    L2Connection,
    SequencerApi,
    Transaction,
    Other,
}

/// Circuit breaker state
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum CircuitBreakerState {
    /// Normal operation
    #[default]
    Closed,
    /// Testing if service is recovered
    HalfOpen,
    /// Blocking operations
    Open,
}

impl CircuitBreakerState {
    /// String representation for logs and JSON output
    pub fn as_str(&self) -> &'static str {
        match self {
            CircuitBreakerState::Closed => "closed",
            CircuitBreakerState::HalfOpen => "half-open",
            CircuitBreakerState::Open => "open",
        }
    }

    /// Metric representation for Prometheus (0=closed, 1=half-open, 2=open)
    pub fn as_metric(&self) -> u64 {
        match self {
            CircuitBreakerState::Closed => 0,
            CircuitBreakerState::HalfOpen => 1,
            CircuitBreakerState::Open => 2,
        }
    }
}

/// Circuit breaker for resilience
#[derive(Debug, Clone)]
pub struct CircuitBreaker {
    pub state: CircuitBreakerState,
    pub failure_threshold: u64,
    pub reset_timeout_secs: u64,
    pub last_failure_time: Option<DateTime<Utc>>,
    pub half_open_success_count: u64,
    pub half_open_success_threshold: u64,
}

impl Default for CircuitBreaker {
    fn default() -> Self {
        Self {
            state: CircuitBreakerState::Closed,
            failure_threshold: 5,
            reset_timeout_secs: 60,
            last_failure_time: None,
            half_open_success_count: 0,
            half_open_success_threshold: 3,
        }
    }
}

impl CircuitBreaker {
    /// Create a new circuit breaker with custom settings
    pub fn new(failure_threshold: u64, reset_timeout_secs: u64) -> Self {
        Self {
            failure_threshold,
            reset_timeout_secs,
            ..Default::default()
        }
    }

    /// Check if operations should be allowed
    pub fn allow_request(&mut self) -> bool {
        match self.state {
            CircuitBreakerState::Closed => true,
            CircuitBreakerState::Open => {
                // Check if we should transition to half-open
                if let Some(last_failure) = self.last_failure_time {
                    let elapsed = Utc::now().signed_duration_since(last_failure);
                    if elapsed.num_seconds() >= self.reset_timeout_secs as i64 {
                        self.state = CircuitBreakerState::HalfOpen;
                        self.half_open_success_count = 0;
                        return true;
                    }
                }
                false
            }
            CircuitBreakerState::HalfOpen => true,
        }
    }

    /// Record a successful operation
    pub fn record_success(&mut self) {
        match self.state {
            CircuitBreakerState::HalfOpen => {
                self.half_open_success_count += 1;
                if self.half_open_success_count >= self.half_open_success_threshold {
                    self.state = CircuitBreakerState::Closed;
                    self.half_open_success_count = 0;
                }
            }
            CircuitBreakerState::Closed => {}
            CircuitBreakerState::Open => {
                // Should not happen, but reset to closed
                self.state = CircuitBreakerState::Closed;
            }
        }
    }

    /// Record a failed operation
    pub fn record_failure(&mut self, consecutive_failures: u64) {
        self.last_failure_time = Some(Utc::now());

        match self.state {
            CircuitBreakerState::Closed => {
                if consecutive_failures >= self.failure_threshold {
                    self.state = CircuitBreakerState::Open;
                }
            }
            CircuitBreakerState::HalfOpen => {
                // Any failure in half-open goes back to open
                self.state = CircuitBreakerState::Open;
                self.half_open_success_count = 0;
            }
            CircuitBreakerState::Open => {}
        }
    }

    /// Get the current state
    pub fn is_open(&self) -> bool {
        matches!(self.state, CircuitBreakerState::Open)
    }

    /// Get state name for logging
    pub fn state_name(&self) -> &'static str {
        match self.state {
            CircuitBreakerState::Closed => "closed",
            CircuitBreakerState::HalfOpen => "half-open",
            CircuitBreakerState::Open => "open",
        }
    }
}
