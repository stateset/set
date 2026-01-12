//! Set Chain Anchor Service
//!
//! Bridges stateset-sequencer batch commitments to on-chain SetRegistry.
//! Provides cryptographic anchoring of commerce events on Set Chain L2.

pub mod client;
pub mod config;
pub mod error;
pub mod health;
pub mod service;
pub mod types;

#[cfg(test)]
mod tests;

pub use config::AnchorConfig;
pub use error::{AnchorError, ErrorSeverity};
pub use health::{HealthServer, HealthState};
pub use service::AnchorService;
pub use types::{
    AnchorNotification, AnchorResult, AnchorStats, BatchCommitment,
    CircuitBreaker, CircuitBreakerState, ErrorType, PendingCommitmentsResponse,
};
