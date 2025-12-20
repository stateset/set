//! Set Chain Anchor Service
//!
//! Bridges stateset-sequencer batch commitments to on-chain SetRegistry.

use std::sync::Arc;

use anyhow::Result;
use tokio::sync::RwLock;
use tracing::{error, info};
use tracing_subscriber::{fmt, EnvFilter};

use set_anchor::{AnchorConfig, AnchorService, AnchorStats, HealthServer, HealthState};

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
        health_port = config.health_port,
        "Configuration loaded"
    );

    // Create shared stats
    let stats = Arc::new(RwLock::new(AnchorStats::default()));

    // Create health state
    let health_state = Arc::new(HealthState::new(config.clone(), Arc::clone(&stats)));

    // Create anchor service with health state
    let service = AnchorService::with_health_state(config.clone(), Arc::clone(&health_state));

    // Create health server
    let health_server = HealthServer::new(config.clone(), Arc::clone(&stats), config.health_port);

    // Run both services concurrently
    tokio::select! {
        result = service.run() => {
            if let Err(e) = result {
                error!(error = %e, "Anchor service failed");
                return Err(e);
            }
        }
        result = health_server.run() => {
            if let Err(e) = result {
                error!(error = %e, "Health server failed");
                return Err(e);
            }
        }
        _ = tokio::signal::ctrl_c() => {
            info!("Received shutdown signal");
        }
    }

    info!("Anchor service stopped");
    Ok(())
}
