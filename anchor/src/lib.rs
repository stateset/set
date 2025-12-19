//! Set Chain Anchor Service
//!
//! Bridges stateset-sequencer batch commitments to on-chain SetRegistry.
//! Provides cryptographic anchoring of commerce events on Set Chain L2.

pub mod client;
pub mod config;
pub mod service;
pub mod types;

pub use config::AnchorConfig;
pub use service::AnchorService;
pub use types::*;
