//! Set Chain Anchor Service
//!
//! Bridges stateset-sequencer batch commitments to on-chain SetRegistry.

use anyhow::Result;
use tracing::{info, Level};
use tracing_subscriber::{fmt, EnvFilter};

use set_anchor::{AnchorConfig, AnchorService};

#[tokio::main]
async fn main() -> Result<()> {
    // Load .env file if present
    dotenvy::dotenv().ok();

    // Initialize logging
    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("info,set_anchor=debug"));

    fmt()
        .with_env_filter(filter)
        .with_target(true)
        .with_level(true)
        .with_ansi(true)
        .init();

    info!(
        version = env!("CARGO_PKG_VERSION"),
        "Set Chain Anchor Service starting"
    );

    // Load configuration
    let config = AnchorConfig::from_env()?;

    info!(
        l2_rpc = %config.l2_rpc_url,
        registry = %config.set_registry_address,
        sequencer_api = %config.sequencer_api_url,
        interval = config.anchor_interval_secs,
        min_events = config.min_events_for_anchor,
        "Configuration loaded"
    );

    // Create and run service
    let service = AnchorService::new(config);

    // Handle shutdown gracefully
    tokio::select! {
        result = service.run() => {
            result?;
        }
        _ = tokio::signal::ctrl_c() => {
            info!("Received shutdown signal");
        }
    }

    info!("Anchor service stopped");
    Ok(())
}
