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

    /// Maximum seconds to wait for transaction confirmation
    #[serde(default = "default_tx_confirmation_timeout_secs")]
    pub tx_confirmation_timeout_secs: u64,
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

fn default_tx_confirmation_timeout_secs() -> u64 {
    60
}

fn parse_optional_u64(var: &str, default: u64) -> anyhow::Result<u64> {
    match std::env::var(var) {
        Ok(value) => value
            .parse::<u64>()
            .map_err(|e| anyhow::anyhow!("{} is invalid: {}", var, e)),
        Err(_) => Ok(default),
    }
}

fn parse_optional_u32(var: &str, default: u32) -> anyhow::Result<u32> {
    match std::env::var(var) {
        Ok(value) => value
            .parse::<u32>()
            .map_err(|e| anyhow::anyhow!("{} is invalid: {}", var, e)),
        Err(_) => Ok(default),
    }
}

fn parse_optional_u16(var: &str, default: u16) -> anyhow::Result<u16> {
    match std::env::var(var) {
        Ok(value) => value
            .parse::<u16>()
            .map_err(|e| anyhow::anyhow!("{} is invalid: {}", var, e)),
        Err(_) => Ok(default),
    }
}

impl AnchorConfig {
    /// Validate configuration values after loading
    pub fn validate(&self) -> anyhow::Result<()> {
        // Validate Ethereum address format (0x + 40 hex chars)
        if !self.set_registry_address.starts_with("0x")
            || self.set_registry_address.len() != 42
            || !self.set_registry_address[2..].chars().all(|c| c.is_ascii_hexdigit())
        {
            anyhow::bail!(
                "SET_REGISTRY_ADDRESS must be a valid Ethereum address (0x + 40 hex chars), got: {}",
                self.set_registry_address
            );
        }

        // Validate private key format (0x + 64 hex chars)
        let key = self.sequencer_private_key.strip_prefix("0x")
            .unwrap_or(&self.sequencer_private_key);
        if key.len() != 64 || !key.chars().all(|c| c.is_ascii_hexdigit()) {
            anyhow::bail!("SEQUENCER_PRIVATE_KEY must be 64 hex characters (with optional 0x prefix)");
        }

        // Validate URL formats
        if !self.l2_rpc_url.starts_with("http://") && !self.l2_rpc_url.starts_with("https://") {
            anyhow::bail!("L2_RPC_URL must start with http:// or https://, got: {}", self.l2_rpc_url);
        }
        if !self.sequencer_api_url.starts_with("http://") && !self.sequencer_api_url.starts_with("https://") {
            anyhow::bail!("SEQUENCER_API_URL must start with http:// or https://, got: {}", self.sequencer_api_url);
        }

        // Validate timeouts are not zero
        if self.anchor_interval_secs == 0 {
            anyhow::bail!("ANCHOR_INTERVAL_SECS must be > 0");
        }
        if self.sequencer_request_timeout_secs == 0 {
            anyhow::bail!("SEQUENCER_REQUEST_TIMEOUT_SECS must be > 0");
        }
        if self.sequencer_connect_timeout_secs == 0 {
            anyhow::bail!("SEQUENCER_CONNECT_TIMEOUT_SECS must be > 0");
        }
        if self.tx_confirmation_timeout_secs == 0 {
            anyhow::bail!("TX_CONFIRMATION_TIMEOUT_SECS must be > 0");
        }
        if self.retry_delay_secs == 0 {
            anyhow::bail!("RETRY_DELAY_SECS must be > 0");
        }

        // Validate circuit breaker settings
        if self.circuit_breaker_failure_threshold == 0 {
            anyhow::bail!("CIRCUIT_BREAKER_FAILURE_THRESHOLD must be > 0");
        }
        if self.circuit_breaker_reset_timeout_secs == 0 {
            anyhow::bail!("CIRCUIT_BREAKER_RESET_TIMEOUT_SECS must be > 0");
        }
        if self.circuit_breaker_half_open_success_threshold == 0 {
            anyhow::bail!("CIRCUIT_BREAKER_HALF_OPEN_SUCCESS_THRESHOLD must be > 0");
        }

        Ok(())
    }

    /// Load configuration from environment variables
    pub fn from_env() -> anyhow::Result<Self> {
        let expected_l2_chain_id = if let Ok(v) = std::env::var("EXPECTED_L2_CHAIN_ID") {
            v.parse::<u64>()
                .map_err(|e| anyhow::anyhow!("EXPECTED_L2_CHAIN_ID is invalid: {}", e))?
        } else if let Ok(v) = std::env::var("L2_CHAIN_ID") {
            v.parse::<u64>()
                .map_err(|e| anyhow::anyhow!("L2_CHAIN_ID is invalid: {}", e))?
        } else {
            0
        };

        Ok(Self {
            l2_rpc_url: std::env::var("L2_RPC_URL")
                .unwrap_or_else(|_| default_l2_rpc()),
            set_registry_address: std::env::var("SET_REGISTRY_ADDRESS")
                .map_err(|_| anyhow::anyhow!("SET_REGISTRY_ADDRESS not set"))?,
            sequencer_private_key: std::env::var("SEQUENCER_PRIVATE_KEY")
                .map_err(|_| anyhow::anyhow!("SEQUENCER_PRIVATE_KEY not set"))?,
            sequencer_api_url: std::env::var("SEQUENCER_API_URL")
                .unwrap_or_else(|_| default_sequencer_api()),
            anchor_interval_secs: parse_optional_u64("ANCHOR_INTERVAL_SECS", default_interval())?,
            min_events_for_anchor: parse_optional_u32("MIN_EVENTS_FOR_ANCHOR", default_min_events())?,
            max_retries: parse_optional_u32("MAX_RETRIES", default_max_retries())?,
            retry_delay_secs: parse_optional_u64("RETRY_DELAY_SECS", default_retry_delay())?,
            max_gas_price_gwei: parse_optional_u64("MAX_GAS_PRICE_GWEI", 0)?,
            health_port: parse_optional_u16("HEALTH_PORT", default_health_port())?,
            expected_l2_chain_id,
            max_commitments_per_cycle: parse_optional_u32(
                "MAX_COMMITMENTS_PER_CYCLE",
                default_max_commitments_per_cycle(),
            )?,
            sequencer_request_timeout_secs: parse_optional_u64(
                "SEQUENCER_REQUEST_TIMEOUT_SECS",
                default_sequencer_request_timeout_secs(),
            )?,
            sequencer_connect_timeout_secs: parse_optional_u64(
                "SEQUENCER_CONNECT_TIMEOUT_SECS",
                default_sequencer_connect_timeout_secs(),
            )?,
            circuit_breaker_failure_threshold: parse_optional_u64(
                "CIRCUIT_BREAKER_FAILURE_THRESHOLD",
                default_circuit_breaker_failure_threshold(),
            )?,
            circuit_breaker_reset_timeout_secs: parse_optional_u64(
                "CIRCUIT_BREAKER_RESET_TIMEOUT_SECS",
                default_circuit_breaker_reset_timeout_secs(),
            )?,
            circuit_breaker_half_open_success_threshold: parse_optional_u64(
                "CIRCUIT_BREAKER_HALF_OPEN_SUCCESS_THRESHOLD",
                default_circuit_breaker_half_open_success_threshold(),
            )?,
            tx_confirmation_timeout_secs: parse_optional_u64(
                "TX_CONFIRMATION_TIMEOUT_SECS",
                default_tx_confirmation_timeout_secs(),
            )?,
        })
    }
}
