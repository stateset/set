//! Configuration for the anchor service

use serde::Deserialize;

/// Anchor service configuration
#[derive(Debug, Clone, Deserialize)]
pub struct AnchorConfig {
    /// Set Chain L2 RPC URL
    #[serde(default = "default_l2_rpc")]
    pub l2_rpc_url: String,

    /// SetRegistry contract address on L2
    pub set_registry_address: String,

    /// Private key for submitting transactions
    pub sequencer_private_key: String,

    /// Stateset sequencer API URL
    #[serde(default = "default_sequencer_api")]
    pub sequencer_api_url: String,

    /// Anchor interval in seconds
    #[serde(default = "default_interval")]
    pub anchor_interval_secs: u64,

    /// Minimum events before anchoring
    #[serde(default = "default_min_events")]
    pub min_events_for_anchor: u32,

    /// Maximum retries for failed anchoring
    #[serde(default = "default_max_retries")]
    pub max_retries: u32,

    /// Retry delay in seconds
    #[serde(default = "default_retry_delay")]
    pub retry_delay_secs: u64,

    /// Gas price limit in gwei (0 = auto)
    #[serde(default)]
    pub max_gas_price_gwei: u64,

    /// Health server port
    #[serde(default = "default_health_port")]
    pub health_port: u16,

    /// Expected L2 chain ID (0 = disable check)
    #[serde(default)]
    pub expected_l2_chain_id: u64,

    /// Maximum commitments to anchor per cycle (0 = unlimited)
    #[serde(default = "default_max_commitments_per_cycle")]
    pub max_commitments_per_cycle: u32,

    /// Sequencer API request timeout in seconds
    #[serde(default = "default_sequencer_request_timeout_secs")]
    pub sequencer_request_timeout_secs: u64,

    /// Sequencer API connect timeout in seconds
    #[serde(default = "default_sequencer_connect_timeout_secs")]
    pub sequencer_connect_timeout_secs: u64,

    /// Circuit breaker failure threshold (consecutive failures)
    #[serde(default = "default_circuit_breaker_failure_threshold")]
    pub circuit_breaker_failure_threshold: u64,

    /// Circuit breaker reset timeout in seconds
    #[serde(default = "default_circuit_breaker_reset_timeout_secs")]
    pub circuit_breaker_reset_timeout_secs: u64,

    /// Circuit breaker successes required to close after half-open
    #[serde(default = "default_circuit_breaker_half_open_success_threshold")]
    pub circuit_breaker_half_open_success_threshold: u64,
}

fn default_health_port() -> u16 {
    9090
}

fn default_l2_rpc() -> String {
    "http://localhost:8547".to_string()
}

fn default_sequencer_api() -> String {
    "http://localhost:3000".to_string()
}

fn default_interval() -> u64 {
    60
}

fn default_min_events() -> u32 {
    100
}

fn default_max_retries() -> u32 {
    3
}

fn default_retry_delay() -> u64 {
    5
}

fn default_max_commitments_per_cycle() -> u32 {
    0
}

fn default_sequencer_request_timeout_secs() -> u64 {
    10
}

fn default_sequencer_connect_timeout_secs() -> u64 {
    3
}

fn default_circuit_breaker_failure_threshold() -> u64 {
    5
}

fn default_circuit_breaker_reset_timeout_secs() -> u64 {
    60
}

fn default_circuit_breaker_half_open_success_threshold() -> u64 {
    3
}

impl AnchorConfig {
    /// Load configuration from environment variables
    pub fn from_env() -> anyhow::Result<Self> {
        Ok(Self {
            l2_rpc_url: std::env::var("L2_RPC_URL")
                .unwrap_or_else(|_| default_l2_rpc()),
            set_registry_address: std::env::var("SET_REGISTRY_ADDRESS")
                .map_err(|_| anyhow::anyhow!("SET_REGISTRY_ADDRESS not set"))?,
            sequencer_private_key: std::env::var("SEQUENCER_PRIVATE_KEY")
                .map_err(|_| anyhow::anyhow!("SEQUENCER_PRIVATE_KEY not set"))?,
            sequencer_api_url: std::env::var("SEQUENCER_API_URL")
                .unwrap_or_else(|_| default_sequencer_api()),
            anchor_interval_secs: std::env::var("ANCHOR_INTERVAL_SECS")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or_else(default_interval),
            min_events_for_anchor: std::env::var("MIN_EVENTS_FOR_ANCHOR")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or_else(default_min_events),
            max_retries: std::env::var("MAX_RETRIES")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or_else(default_max_retries),
            retry_delay_secs: std::env::var("RETRY_DELAY_SECS")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or_else(default_retry_delay),
            max_gas_price_gwei: std::env::var("MAX_GAS_PRICE_GWEI")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(0),
            health_port: std::env::var("HEALTH_PORT")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or_else(default_health_port),
            expected_l2_chain_id: std::env::var("EXPECTED_L2_CHAIN_ID")
                .ok()
                .or_else(|| std::env::var("L2_CHAIN_ID").ok())
                .and_then(|s| s.parse().ok())
                .unwrap_or(0),
            max_commitments_per_cycle: std::env::var("MAX_COMMITMENTS_PER_CYCLE")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or_else(default_max_commitments_per_cycle),
            sequencer_request_timeout_secs: std::env::var("SEQUENCER_REQUEST_TIMEOUT_SECS")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or_else(default_sequencer_request_timeout_secs),
            sequencer_connect_timeout_secs: std::env::var("SEQUENCER_CONNECT_TIMEOUT_SECS")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or_else(default_sequencer_connect_timeout_secs),
            circuit_breaker_failure_threshold: std::env::var("CIRCUIT_BREAKER_FAILURE_THRESHOLD")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or_else(default_circuit_breaker_failure_threshold),
            circuit_breaker_reset_timeout_secs: std::env::var("CIRCUIT_BREAKER_RESET_TIMEOUT_SECS")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or_else(default_circuit_breaker_reset_timeout_secs),
            circuit_breaker_half_open_success_threshold: std::env::var("CIRCUIT_BREAKER_HALF_OPEN_SUCCESS_THRESHOLD")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or_else(default_circuit_breaker_half_open_success_threshold),
        })
    }
}
