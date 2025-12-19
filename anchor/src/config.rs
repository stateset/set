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
        })
    }
}
