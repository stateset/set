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
}
