//! Mock Sequencer API for integration testing
//!
//! Provides a wiremock-based mock server that simulates the stateset-sequencer API.

use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::sync::{Arc, RwLock};
use uuid::Uuid;
use wiremock::{
    matchers::{method, path, path_regex},
    Mock, MockServer, ResponseTemplate,
};

/// Batch commitment for testing
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TestBatchCommitment {
    pub batch_id: Uuid,
    pub tenant_id: Uuid,
    pub store_id: Uuid,
    pub prev_state_root: String,
    pub new_state_root: String,
    pub events_root: String,
    pub sequence_start: u64,
    pub sequence_end: u64,
    pub event_count: u32,
    pub committed_at: String,
    pub chain_tx_hash: Option<String>,
}

impl TestBatchCommitment {
    /// Create a new test commitment with random IDs
    pub fn new(sequence_start: u64, sequence_end: u64, event_count: u32) -> Self {
        Self {
            batch_id: Uuid::new_v4(),
            tenant_id: Uuid::new_v4(),
            store_id: Uuid::new_v4(),
            prev_state_root: format!("0x{}", "0".repeat(64)),
            new_state_root: format!("0x{}", hex::encode(Uuid::new_v4().as_bytes()).repeat(2)[..64].to_string()),
            events_root: format!("0x{}", hex::encode(Uuid::new_v4().as_bytes()).repeat(2)[..64].to_string()),
            sequence_start,
            sequence_end,
            event_count,
            committed_at: Utc::now().to_rfc3339(),
            chain_tx_hash: None,
        }
    }

    /// Create with specific roots for testing state chain continuity
    pub fn with_roots(
        sequence_start: u64,
        sequence_end: u64,
        event_count: u32,
        prev_state_root: &str,
        new_state_root: &str,
        events_root: &str,
    ) -> Self {
        Self {
            batch_id: Uuid::new_v4(),
            tenant_id: Uuid::new_v4(),
            store_id: Uuid::new_v4(),
            prev_state_root: prev_state_root.to_string(),
            new_state_root: new_state_root.to_string(),
            events_root: events_root.to_string(),
            sequence_start,
            sequence_end,
            event_count,
            committed_at: Utc::now().to_rfc3339(),
            chain_tx_hash: None,
        }
    }

    /// Create with specific tenant/store for multi-tenant testing
    pub fn with_tenant_store(
        tenant_id: Uuid,
        store_id: Uuid,
        sequence_start: u64,
        sequence_end: u64,
        event_count: u32,
    ) -> Self {
        let mut commitment = Self::new(sequence_start, sequence_end, event_count);
        commitment.tenant_id = tenant_id;
        commitment.store_id = store_id;
        commitment
    }
}

/// Response for pending commitments endpoint
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PendingCommitmentsResponse {
    pub commitments: Vec<TestBatchCommitment>,
    pub total: usize,
}

/// Anchor notification request body
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnchorNotificationRequest {
    pub chain_tx_hash: String,
    pub chain_id: u64,
    pub block_number: Option<u64>,
    pub gas_used: Option<u64>,
}

/// Mock sequencer API state
#[derive(Debug, Default)]
pub struct MockSequencerState {
    /// Pending commitments to return
    pub pending_commitments: Vec<TestBatchCommitment>,
    /// Anchor notifications received
    pub anchor_notifications: Vec<(Uuid, AnchorNotificationRequest)>,
}

/// Mock sequencer API server
pub struct MockSequencerApi {
    server: MockServer,
    state: Arc<RwLock<MockSequencerState>>,
}

impl MockSequencerApi {
    /// Start a new mock sequencer API server
    pub async fn start() -> Self {
        let server = MockServer::start().await;
        let state = Arc::new(RwLock::new(MockSequencerState::default()));

        Self { server, state }
    }

    /// Get the server URL
    pub fn url(&self) -> String {
        self.server.uri()
    }

    /// Add pending commitments
    pub async fn add_pending_commitment(&self, commitment: TestBatchCommitment) {
        let mut state = self.state.write().unwrap();
        state.pending_commitments.push(commitment);
    }

    /// Add multiple pending commitments
    pub async fn add_pending_commitments(&self, commitments: Vec<TestBatchCommitment>) {
        let mut state = self.state.write().unwrap();
        state.pending_commitments.extend(commitments);
    }

    /// Clear all pending commitments
    pub async fn clear_pending(&self) {
        let mut state = self.state.write().unwrap();
        state.pending_commitments.clear();
    }

    /// Get received anchor notifications
    pub async fn get_notifications(&self) -> Vec<(Uuid, AnchorNotificationRequest)> {
        self.state.read().unwrap().anchor_notifications.clone()
    }

    /// Clear anchor notifications
    pub async fn clear_notifications(&self) {
        let mut state = self.state.write().unwrap();
        state.anchor_notifications.clear();
    }

    /// Set up mock for GET /v1/commitments/pending
    pub async fn mock_pending_commitments(&self) {
        let state = Arc::clone(&self.state);

        Mock::given(method("GET"))
            .and(path("/v1/commitments/pending"))
            .respond_with(move |_req: &wiremock::Request| {
                let commitments = state.read().unwrap().pending_commitments.clone();

                let response = PendingCommitmentsResponse {
                    total: commitments.len(),
                    commitments,
                };

                ResponseTemplate::new(200).set_body_json(response)
            })
            .mount(&self.server)
            .await;
    }

    /// Set up mock for POST /v1/commitments/{batch_id}/anchored
    pub async fn mock_anchor_notification(&self) {
        let state = Arc::clone(&self.state);

        Mock::given(method("POST"))
            .and(path_regex(r"/v1/commitments/[0-9a-f-]+/anchored"))
            .respond_with(move |req: &wiremock::Request| {
                // Extract batch_id from path
                let path = req.url.path();
                let batch_id_str = path
                    .strip_prefix("/v1/commitments/")
                    .and_then(|s| s.strip_suffix("/anchored"))
                    .unwrap_or("");

                let batch_id = match Uuid::parse_str(batch_id_str) {
                    Ok(id) => id,
                    Err(_) => return ResponseTemplate::new(400),
                };

                // Parse notification body
                let notification: AnchorNotificationRequest = match req.body_json() {
                    Ok(n) => n,
                    Err(_) => return ResponseTemplate::new(400),
                };

                // Record the notification
                let mut state = state.write().unwrap();
                state.anchor_notifications.push((batch_id, notification));

                // Remove from pending
                state.pending_commitments.retain(|c| c.batch_id != batch_id);

                ResponseTemplate::new(200).set_body_json(serde_json::json!({
                    "status": "ok"
                }))
            })
            .mount(&self.server)
            .await;
    }

    /// Set up all standard mocks
    pub async fn setup_standard_mocks(&self) {
        self.mock_pending_commitments().await;
        self.mock_anchor_notification().await;
    }

    /// Mock an error response for pending commitments
    pub async fn mock_pending_error(&self, status_code: u16) {
        Mock::given(method("GET"))
            .and(path("/v1/commitments/pending"))
            .respond_with(ResponseTemplate::new(status_code))
            .mount(&self.server)
            .await;
    }

    /// Get number of pending commitments
    pub async fn pending_count(&self) -> usize {
        self.state.read().unwrap().pending_commitments.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_mock_server_starts() {
        let mock = MockSequencerApi::start().await;
        assert!(!mock.url().is_empty());
    }

    #[tokio::test]
    async fn test_add_pending_commitment() {
        let mock = MockSequencerApi::start().await;

        let commitment = TestBatchCommitment::new(1, 10, 10);
        mock.add_pending_commitment(commitment).await;

        assert_eq!(mock.pending_count().await, 1);
    }

    #[tokio::test]
    async fn test_pending_commitments_endpoint() {
        let mock = MockSequencerApi::start().await;
        mock.setup_standard_mocks().await;

        let commitment = TestBatchCommitment::new(1, 10, 10);
        mock.add_pending_commitment(commitment).await;

        // Make HTTP request
        let client = reqwest::Client::new();
        let response = client
            .get(format!("{}/v1/commitments/pending", mock.url()))
            .send()
            .await
            .unwrap();

        assert_eq!(response.status(), 200);

        let body: PendingCommitmentsResponse = response.json().await.unwrap();
        assert_eq!(body.commitments.len(), 1);
        assert_eq!(body.total, 1);
    }
}
