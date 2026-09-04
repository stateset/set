//! Reserve Attestor Service
//!
//! Periodically reads the off-chain Treasury reserve portfolio value from a feed
//! (a local file or an HTTP endpoint serving a signed custodian statement), binds it to a
//! keccak256 hash of the exact statement bytes, and submits it on-chain to `ProofOfReservesV2`.
//!
//! This is the operational counterpart to the on-chain proof-of-reserves layer: the contract can
//! verify coverage, but only if something keeps attesting the off-chain mark. This service is that
//! something. It uses a key holding `ATTESTOR_ROLE` — deliberately distinct from the NAV oracle key,
//! so a single compromised signer cannot both move the share price and fake the reserves behind it.
//!
//! Env configuration:
//!   RPC_URL                 L2 RPC (default http://localhost:8547)
//!   POR_CONTRACT_ADDRESS    ProofOfReservesV2 address (required)
//!   ATTESTOR_PRIVATE_KEY    signer holding ATTESTOR_ROLE (required)
//!   RESERVE_FEED_URL        file://path or http(s):// returning the reserve JSON (required)
//!   ATTEST_INTERVAL_SECS    seconds between attestations (default 3600)
//!   HEALTH_PORT             health/stats server port (default 9091)
//!   EXPECTED_CHAIN_ID       optional chain-id guard (0 = disabled)
//!   TX_CONFIRMATION_TIMEOUT_SECS  receipt wait (default 60)

use std::sync::Arc;
use std::time::Duration;

use alloy::{
    network::EthereumWallet,
    primitives::{keccak256, Address, FixedBytes, U256},
    providers::{Provider, ProviderBuilder},
    signers::local::PrivateKeySigner,
    sol,
    transports::http::Http,
};
use anyhow::{anyhow, Context, Result};
use axum::{extract::State, http::StatusCode, routing::get, Json, Router};
use serde::Deserialize;
use serde_json::json;
use tokio::sync::RwLock;
use tokio::time::{interval, timeout};
use tracing::{error, info};
use tracing_subscriber::{fmt, EnvFilter};

type HttpTransport = Http<reqwest::Client>;
const MAX_FEED_BYTES: usize = 1_048_576;

// On-chain ProofOfReservesV2 surface used by this service.
sol!(
    #[allow(missing_docs)]
    #[sol(rpc)]
    ProofOfReserves,
    r#"[
        {
            "type": "function",
            "name": "submitAttestation",
            "inputs": [
                {"name": "reserveValue", "type": "uint256"},
                {"name": "portfolioHash", "type": "bytes32"},
                {"name": "newEpoch", "type": "uint64"}
            ],
            "outputs": [],
            "stateMutability": "nonpayable"
        },
        {
            "type": "function",
            "name": "latest",
            "inputs": [],
            "outputs": [
                {"name": "reserveValue", "type": "uint256"},
                {"name": "portfolioHash", "type": "bytes32"},
                {"name": "epoch", "type": "uint64"},
                {"name": "timestamp", "type": "uint40"},
                {"name": "attestor", "type": "address"}
            ],
            "stateMutability": "view"
        },
        {
            "type": "function",
            "name": "coverageRatioBps",
            "inputs": [],
            "outputs": [{"type": "uint256"}],
            "stateMutability": "view"
        }
    ]"#
);

/// Service configuration loaded from the environment.
#[derive(Debug, Clone)]
struct Config {
    rpc_url: String,
    por_address: Address,
    private_key: String,
    feed_url: String,
    interval_secs: u64,
    health_port: u16,
    expected_chain_id: u64,
    tx_confirmation_timeout_secs: u64,
}

impl Config {
    fn from_env() -> Result<Self> {
        let por_address = std::env::var("POR_CONTRACT_ADDRESS")
            .context("POR_CONTRACT_ADDRESS not set")?
            .parse::<Address>()
            .context("POR_CONTRACT_ADDRESS is not a valid address")?;
        let private_key =
            std::env::var("ATTESTOR_PRIVATE_KEY").context("ATTESTOR_PRIVATE_KEY not set")?;
        let feed_url = std::env::var("RESERVE_FEED_URL").context("RESERVE_FEED_URL not set")?;

        let interval_secs = parse_env_u64("ATTEST_INTERVAL_SECS", 3600)?;
        if interval_secs == 0 {
            anyhow::bail!("ATTEST_INTERVAL_SECS must be > 0");
        }

        let health_port = parse_env_u64("HEALTH_PORT", 9091)?;
        let health_port = u16::try_from(health_port)
            .map_err(|_| anyhow!("HEALTH_PORT must be between 0 and 65535"))?;
        let tx_confirmation_timeout_secs = parse_env_u64("TX_CONFIRMATION_TIMEOUT_SECS", 60)?;
        if tx_confirmation_timeout_secs == 0 {
            anyhow::bail!("TX_CONFIRMATION_TIMEOUT_SECS must be > 0");
        }
        if por_address == Address::ZERO {
            anyhow::bail!("POR_CONTRACT_ADDRESS must not be the zero address");
        }
        if !(feed_url.starts_with("file://")
            || feed_url.starts_with("http://")
            || feed_url.starts_with("https://"))
        {
            anyhow::bail!("RESERVE_FEED_URL must use file://, http://, or https://");
        }

        Ok(Self {
            rpc_url: std::env::var("RPC_URL")
                .unwrap_or_else(|_| "http://localhost:8547".to_string()),
            por_address,
            private_key,
            feed_url,
            interval_secs,
            health_port,
            expected_chain_id: parse_env_u64("EXPECTED_CHAIN_ID", 0)?,
            tx_confirmation_timeout_secs,
        })
    }
}

fn parse_env_u64(var: &str, default: u64) -> Result<u64> {
    match std::env::var(var) {
        Ok(v) => v
            .parse::<u64>()
            .map_err(|e| anyhow!("{var} is invalid: {e}")),
        Err(_) => Ok(default),
    }
}

/// The off-chain reserve statement. `reserve_value` is in settlement-asset smallest units
/// (USDC, 6 decimals) so it lines up with the vault's accounting.
#[derive(Debug, Deserialize)]
struct ReserveFeed {
    reserve_value: String,
    #[serde(default)]
    as_of: Option<String>,
}

/// Shared state surfaced by the health server.
#[derive(Debug, Default)]
struct AttestorState {
    last_epoch: u64,
    last_reserve_value: u128,
    last_coverage_bps: u64,
    last_tx_hash: Option<String>,
    last_error: Option<String>,
    attestations: u64,
    failures: u64,
}

type SharedState = Arc<RwLock<AttestorState>>;

/// Fetch the reserve feed and return (value, keccak256 of the exact statement bytes).
async fn fetch_feed(feed_url: &str) -> Result<(U256, FixedBytes<32>, Option<String>)> {
    let bytes = if let Some(path) = feed_url.strip_prefix("file://") {
        tokio::fs::read(path)
            .await
            .with_context(|| format!("reading reserve feed file {path}"))?
    } else {
        let response = reqwest::get(feed_url)
            .await
            .context("fetching reserve feed")?
            .error_for_status()
            .context("reserve feed returned an unsuccessful HTTP status")?;
        if response
            .content_length()
            .is_some_and(|length| length > MAX_FEED_BYTES as u64)
        {
            anyhow::bail!("reserve feed exceeds {MAX_FEED_BYTES} bytes");
        }
        response
            .bytes()
            .await
            .context("reading reserve feed body")?
            .to_vec()
    };
    if bytes.len() > MAX_FEED_BYTES {
        anyhow::bail!("reserve feed exceeds {MAX_FEED_BYTES} bytes");
    }

    // Hash the exact bytes so the on-chain commitment binds to this precise statement.
    let portfolio_hash = keccak256(&bytes);

    let feed: ReserveFeed = serde_json::from_slice(&bytes).context("parsing reserve feed JSON")?;
    let value: u128 = feed
        .reserve_value
        .trim()
        .parse()
        .map_err(|e| anyhow!("reserve_value is not a valid integer: {e}"))?;

    Ok((U256::from(value), portfolio_hash, feed.as_of))
}

/// Perform one attestation cycle.
async fn attest_once<P: Provider<HttpTransport> + Clone>(
    contract: &ProofOfReserves::ProofOfReservesInstance<HttpTransport, P>,
    cfg: &Config,
    state: &SharedState,
) -> Result<()> {
    let (reserve_value, portfolio_hash, as_of) = fetch_feed(&cfg.feed_url).await?;

    // Next epoch must strictly exceed the current on-chain epoch.
    let current = contract
        .latest()
        .call()
        .await
        .context("reading latest attestation")?;
    let next_epoch = next_epoch(current.epoch)?;

    info!(
        next_epoch,
        reserve_value = %reserve_value,
        as_of = as_of.as_deref().unwrap_or("n/a"),
        portfolio_hash = %portfolio_hash,
        "Submitting reserve attestation"
    );

    let pending = contract
        .submitAttestation(reserve_value, portfolio_hash, next_epoch)
        .send()
        .await
        .context("sending submitAttestation")?;

    let receipt = timeout(
        Duration::from_secs(cfg.tx_confirmation_timeout_secs),
        pending.get_receipt(),
    )
    .await
    .map_err(|_| anyhow!("timed out waiting for attestation receipt"))?
    .context("attestation receipt")?;

    if !receipt.status() {
        return Err(anyhow!("attestation transaction reverted"));
    }

    let coverage = contract
        .coverageRatioBps()
        .call()
        .await
        .map(|r| r._0.try_into().unwrap_or(u64::MAX))
        .unwrap_or(0);

    let tx_hash = format!("{:#x}", receipt.transaction_hash);
    info!(epoch = next_epoch, coverage_bps = coverage, tx_hash = %tx_hash, "Attestation confirmed");

    let mut s = state.write().await;
    s.last_epoch = next_epoch;
    s.last_reserve_value = reserve_value.try_into().unwrap_or(u128::MAX);
    s.last_coverage_bps = coverage;
    s.last_tx_hash = Some(tx_hash);
    s.last_error = None;
    s.attestations += 1;
    Ok(())
}

async fn run_attestor(cfg: Config, state: SharedState) -> Result<()> {
    let signer: PrivateKeySigner = cfg
        .private_key
        .parse()
        .context("ATTESTOR_PRIVATE_KEY is not a valid private key")?;
    let wallet = EthereumWallet::from(signer);
    let provider = ProviderBuilder::new()
        .with_recommended_fillers()
        .wallet(wallet)
        .on_http(cfg.rpc_url.parse().context("RPC_URL is not a valid URL")?);

    if cfg.expected_chain_id != 0 {
        let chain_id = provider.get_chain_id().await.context("querying chain id")?;
        if chain_id != cfg.expected_chain_id {
            anyhow::bail!(
                "chain id mismatch: connected to {chain_id}, expected {}",
                cfg.expected_chain_id
            );
        }
    }

    let contract = ProofOfReserves::new(cfg.por_address, provider);

    let mut ticker = interval(Duration::from_secs(cfg.interval_secs));
    loop {
        ticker.tick().await;
        if let Err(e) = attest_once(&contract, &cfg, &state).await {
            error!(error = %e, "Attestation cycle failed");
            let mut s = state.write().await;
            s.failures += 1;
            s.last_error = Some(e.to_string());
        }
    }
}

async fn health() -> &'static str {
    "ok"
}

fn next_epoch(current: u64) -> Result<u64> {
    current
        .checked_add(1)
        .ok_or_else(|| anyhow!("attestation epoch exhausted"))
}

async fn ready(State(state): State<SharedState>) -> (StatusCode, &'static str) {
    let state = state.read().await;
    if state.attestations > 0 && state.last_error.is_none() {
        (StatusCode::OK, "ready")
    } else {
        (StatusCode::SERVICE_UNAVAILABLE, "not ready")
    }
}

async fn stats(State(state): State<SharedState>) -> Json<serde_json::Value> {
    let s = state.read().await;
    Json(json!({
        "last_epoch": s.last_epoch,
        "last_reserve_value": s.last_reserve_value.to_string(),
        "last_coverage_bps": s.last_coverage_bps,
        "last_tx_hash": s.last_tx_hash,
        "last_error": s.last_error,
        "attestations": s.attestations,
        "failures": s.failures,
    }))
}

#[tokio::main]
async fn main() -> Result<()> {
    dotenvy::dotenv().ok();

    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("info,reserve_attestor=debug"));
    fmt().with_env_filter(filter).with_target(true).init();

    info!(
        version = env!("CARGO_PKG_VERSION"),
        "Reserve Attestor Service starting"
    );

    let cfg = Config::from_env()?;
    info!(
        rpc = %cfg.rpc_url,
        contract = %cfg.por_address,
        feed = %cfg.feed_url,
        interval = cfg.interval_secs,
        health_port = cfg.health_port,
        "Configuration loaded"
    );

    let state: SharedState = Arc::new(RwLock::new(AttestorState::default()));

    let app = Router::new()
        .route("/health", get(health))
        .route("/ready", get(ready))
        .route("/stats", get(stats))
        .with_state(Arc::clone(&state));
    let listener = tokio::net::TcpListener::bind(("0.0.0.0", cfg.health_port))
        .await
        .context("binding health server")?;

    tokio::select! {
        result = run_attestor(cfg.clone(), Arc::clone(&state)) => {
            if let Err(e) = result {
                error!(error = %e, "Attestor loop failed");
                return Err(e);
            }
        }
        result = axum::serve(listener, app) => {
            if let Err(e) = result {
                error!(error = %e, "Health server failed");
                return Err(anyhow!("health server error: {e}"));
            }
        }
        _ = tokio::signal::ctrl_c() => {
            info!("Received shutdown signal, exiting");
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_feed_path(tag: &str) -> std::path::PathBuf {
        std::env::temp_dir().join(format!(
            "set_reserve_feed_{}_{}.json",
            std::process::id(),
            tag
        ))
    }

    /// Value parses to settlement-asset units and the hash binds the exact file bytes.
    #[tokio::test]
    async fn fetch_feed_parses_value_and_binds_hash() {
        let path = temp_feed_path("ok");
        let body = br#"{"reserve_value":"600000000","as_of":"2026-06-16T00:00:00Z"}"#;
        std::fs::write(&path, body).unwrap();

        let (value, hash, as_of) = fetch_feed(&format!("file://{}", path.display()))
            .await
            .expect("feed should parse");

        assert_eq!(value, U256::from(600_000_000u64));
        // Hash must be keccak256 over the EXACT bytes on disk, not the re-serialized struct.
        assert_eq!(hash, keccak256(body));
        assert_eq!(as_of.as_deref(), Some("2026-06-16T00:00:00Z"));

        std::fs::remove_file(&path).ok();
    }

    /// Different statements hash differently; identical bytes hash identically (determinism).
    #[tokio::test]
    async fn fetch_feed_hash_is_deterministic_and_content_bound() {
        let p1 = temp_feed_path("a");
        let p2 = temp_feed_path("b");
        std::fs::write(&p1, br#"{"reserve_value":"100"}"#).unwrap();
        std::fs::write(&p2, br#"{"reserve_value":"101"}"#).unwrap();

        let (_, h1, _) = fetch_feed(&format!("file://{}", p1.display()))
            .await
            .unwrap();
        let (_, h1_again, _) = fetch_feed(&format!("file://{}", p1.display()))
            .await
            .unwrap();
        let (_, h2, _) = fetch_feed(&format!("file://{}", p2.display()))
            .await
            .unwrap();

        assert_eq!(h1, h1_again, "same bytes must hash identically");
        assert_ne!(h1, h2, "different statements must hash differently");

        std::fs::remove_file(&p1).ok();
        std::fs::remove_file(&p2).ok();
    }

    /// A non-numeric reserve value must be rejected, never silently coerced.
    #[tokio::test]
    async fn fetch_feed_rejects_non_numeric_value() {
        let path = temp_feed_path("badval");
        std::fs::write(&path, br#"{"reserve_value":"not-a-number"}"#).unwrap();

        let err = fetch_feed(&format!("file://{}", path.display()))
            .await
            .unwrap_err();
        assert!(err.to_string().contains("reserve_value"), "got: {err}");

        std::fs::remove_file(&path).ok();
    }

    /// Malformed JSON must error rather than attest garbage.
    #[tokio::test]
    async fn fetch_feed_rejects_malformed_json() {
        let path = temp_feed_path("badjson");
        std::fs::write(&path, b"this is not json").unwrap();

        assert!(fetch_feed(&format!("file://{}", path.display()))
            .await
            .is_err());

        std::fs::remove_file(&path).ok();
    }

    /// A missing file surfaces an error (not a panic, not a zero value).
    #[tokio::test]
    async fn fetch_feed_missing_file_errors() {
        let path = temp_feed_path("missing");
        std::fs::remove_file(&path).ok(); // ensure absent
        assert!(fetch_feed(&format!("file://{}", path.display()))
            .await
            .is_err());
    }

    #[tokio::test]
    async fn fetch_feed_rejects_oversized_statements() {
        let path = temp_feed_path("oversized");
        std::fs::write(&path, vec![b' '; MAX_FEED_BYTES + 1]).unwrap();

        let error = fetch_feed(&format!("file://{}", path.display()))
            .await
            .unwrap_err();
        assert!(error.to_string().contains("exceeds"), "got: {error}");

        std::fs::remove_file(&path).ok();
    }

    #[test]
    fn epoch_increment_is_checked() {
        assert_eq!(next_epoch(41).unwrap(), 42);
        assert!(next_epoch(u64::MAX).is_err());
    }

    #[tokio::test]
    async fn readiness_requires_a_successful_current_attestation() {
        let state = Arc::new(RwLock::new(AttestorState::default()));
        assert_eq!(
            ready(State(Arc::clone(&state))).await.0,
            StatusCode::SERVICE_UNAVAILABLE
        );

        {
            let mut snapshot = state.write().await;
            snapshot.attestations = 1;
        }
        assert_eq!(ready(State(Arc::clone(&state))).await.0, StatusCode::OK);

        state.write().await.last_error = Some("feed unavailable".to_string());
        assert_eq!(ready(State(state)).await.0, StatusCode::SERVICE_UNAVAILABLE);
    }
}
