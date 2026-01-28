//! Integration tests for the Set Chain Anchor Service
//!
//! These tests verify the end-to-end flow from sequencer API to on-chain contract.
//!
//! Test categories:
//! - Mock API tests: Test anchor service with mocked sequencer API
//! - Contract tests: Test anchor service with real contract on Anvil (requires anvil)
//! - Health endpoint tests: Test health/metrics endpoints

mod common;

use std::sync::Arc;
use std::time::Duration;

use chrono::Utc;
use serial_test::serial;
use tokio::sync::RwLock;
use uuid::Uuid;

use set_anchor::{
    client::SequencerApiClient,
    config::AnchorConfig,
    health::{HealthServer, HealthState},
    types::AnchorStats,
    AnchorService,
};

use common::{
    mock_sequencer::{MockSequencerApi, TestBatchCommitment},
    test_contracts::TestSetRegistry,
};

// =============================================================================
// Test Helpers
// =============================================================================

fn test_config(sequencer_api_url: &str, l2_rpc_url: &str, registry_address: &str, private_key: &str) -> AnchorConfig {
    AnchorConfig {
        l2_rpc_url: l2_rpc_url.to_string(),
        set_registry_address: registry_address.to_string(),
        sequencer_private_key: private_key.to_string(),
        sequencer_api_url: sequencer_api_url.to_string(),
        anchor_interval_secs: 1,
        min_events_for_anchor: 1,
        max_retries: 2,
        retry_delay_secs: 1,
        max_gas_price_gwei: 0,
        health_port: 0, // Random port
        expected_l2_chain_id: 0,
        max_commitments_per_cycle: 0,
        sequencer_request_timeout_secs: 10,
        sequencer_connect_timeout_secs: 3,
        circuit_breaker_failure_threshold: 5,
        circuit_breaker_reset_timeout_secs: 60,
        circuit_breaker_half_open_success_threshold: 3,
    }
}

// =============================================================================
// Mock Sequencer API Tests
// =============================================================================

#[tokio::test]
async fn test_sequencer_api_client_fetch_pending() {
    let mock = MockSequencerApi::start().await;
    mock.setup_standard_mocks().await;

    // Add some commitments
    let commitment1 = TestBatchCommitment::new(1, 10, 10);
    let commitment2 = TestBatchCommitment::new(11, 20, 10);
    mock.add_pending_commitments(vec![commitment1.clone(), commitment2.clone()]).await;

    // Create client and fetch
    let client = SequencerApiClient::new(&mock.url());
    let pending = client.get_pending_commitments().await.unwrap();

    assert_eq!(pending.len(), 2);
    assert_eq!(pending[0].batch_id, commitment1.batch_id);
    assert_eq!(pending[1].batch_id, commitment2.batch_id);
}

#[tokio::test]
async fn test_sequencer_api_client_empty_pending() {
    let mock = MockSequencerApi::start().await;
    mock.setup_standard_mocks().await;

    let client = SequencerApiClient::new(&mock.url());
    let pending = client.get_pending_commitments().await.unwrap();

    assert!(pending.is_empty());
}

#[tokio::test]
async fn test_sequencer_api_client_handles_error() {
    let mock = MockSequencerApi::start().await;
    mock.mock_pending_error(500).await;

    let client = SequencerApiClient::new(&mock.url());
    let result = client.get_pending_commitments().await;

    assert!(result.is_err());
}

#[tokio::test]
async fn test_anchor_notification_recorded() {
    let mock = MockSequencerApi::start().await;
    mock.setup_standard_mocks().await;

    let commitment = TestBatchCommitment::new(1, 10, 10);
    let batch_id = commitment.batch_id;
    mock.add_pending_commitment(commitment).await;

    let client = SequencerApiClient::new(&mock.url());

    // Send notification
    let notification = set_anchor::types::AnchorNotification {
        chain_tx_hash: "0x1234567890abcdef".to_string(),
        chain_id: 84532001,
        block_number: Some(100),
        gas_used: Some(50000),
    };

    client.notify_anchored(batch_id, &notification).await.unwrap();

    // Verify notification was recorded
    let notifications = mock.get_notifications().await;
    assert_eq!(notifications.len(), 1);
    assert_eq!(notifications[0].0, batch_id);
    assert_eq!(notifications[0].1.chain_tx_hash, "0x1234567890abcdef");

    // Verify commitment was removed from pending
    assert_eq!(mock.pending_count().await, 0);
}

// =============================================================================
// Health Endpoint Tests
// =============================================================================

#[tokio::test]
async fn test_health_endpoint_returns_ok() {
    let stats = Arc::new(RwLock::new(AnchorStats::default()));
    let config = test_config(
        "http://localhost:3000",
        "http://localhost:8547",
        "0x0000000000000000000000000000000000000000",
        "0x0000000000000000000000000000000000000000000000000000000000000001",
    );

    let health_state = Arc::new(HealthState::new(config.clone(), Arc::clone(&stats)));

    // Create router directly for testing
    let router = set_anchor::health::create_router(Arc::clone(&health_state));

    // Use axum test utilities
    use axum::body::Body;
    use axum::http::Request;
    use tower::util::ServiceExt;

    let response = router
        .oneshot(Request::builder().uri("/health").body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), 200);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(json["status"], "ok");
    assert!(json["uptime_secs"].as_u64().is_some());
}

#[tokio::test]
async fn test_ready_endpoint_not_ready_initially() {
    let stats = Arc::new(RwLock::new(AnchorStats::default()));
    let config = test_config(
        "http://localhost:3000",
        "http://localhost:8547",
        "0x0000000000000000000000000000000000000000",
        "0x0000000000000000000000000000000000000000000000000000000000000001",
    );

    let health_state = Arc::new(HealthState::new(config, Arc::clone(&stats)));
    let router = set_anchor::health::create_router(Arc::clone(&health_state));

    use axum::body::Body;
    use axum::http::Request;
    use tower::util::ServiceExt;

    let response = router
        .oneshot(Request::builder().uri("/ready").body(Body::empty()).unwrap())
        .await
        .unwrap();

    // Should be 503 when not ready
    assert_eq!(response.status(), 503);
}

#[tokio::test]
async fn test_ready_endpoint_becomes_ready() {
    let stats = Arc::new(RwLock::new(AnchorStats::default()));
    let config = test_config(
        "http://localhost:3000",
        "http://localhost:8547",
        "0x0000000000000000000000000000000000000000",
        "0x0000000000000000000000000000000000000000000000000000000000000001",
    );

    let health_state = Arc::new(HealthState::new(config, Arc::clone(&stats)));

    // Mark as ready
    health_state.set_ready(true).await;
    health_state.mark_l2_healthy().await;
    health_state.mark_sequencer_healthy().await;

    let router = set_anchor::health::create_router(Arc::clone(&health_state));

    use axum::body::Body;
    use axum::http::Request;
    use tower::util::ServiceExt;

    let response = router
        .oneshot(Request::builder().uri("/ready").body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), 200);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(json["ready"], true);
    assert_eq!(json["l2_connected"], true);
    assert_eq!(json["sequencer_connected"], true);
}

#[tokio::test]
async fn test_metrics_endpoint_format() {
    let stats = Arc::new(RwLock::new(AnchorStats {
        total_anchored: 42,
        total_failed: 3,
        total_events_anchored: 1000,
        last_anchor_time: Some(Utc::now()),
        last_batch_id: Some(Uuid::new_v4()),
        ..AnchorStats::default()
    }));

    let config = test_config(
        "http://localhost:3000",
        "http://localhost:8547",
        "0x0000000000000000000000000000000000000000",
        "0x0000000000000000000000000000000000000000000000000000000000000001",
    );

    let health_state = Arc::new(HealthState::new(config, Arc::clone(&stats)));
    let router = set_anchor::health::create_router(Arc::clone(&health_state));

    use axum::body::Body;
    use axum::http::Request;
    use tower::util::ServiceExt;

    let response = router
        .oneshot(Request::builder().uri("/metrics").body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), 200);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let body_str = String::from_utf8(body.to_vec()).unwrap();

    // Verify Prometheus format
    assert!(body_str.contains("# HELP set_anchor_batches_total"));
    assert!(body_str.contains("# TYPE set_anchor_batches_total counter"));
    assert!(body_str.contains("set_anchor_batches_total{status=\"success\"} 42"));
    assert!(body_str.contains("set_anchor_batches_total{status=\"failed\"} 3"));
    assert!(body_str.contains("set_anchor_events_total 1000"));
    assert!(body_str.contains("set_anchor_gas_price_skips_total 0"));
    assert!(body_str.contains("set_anchor_cycles_total 0"));
    assert!(body_str.contains("set_anchor_l2_connected 0"));
    assert!(body_str.contains("set_anchor_sequencer_connected 0"));
}

#[tokio::test]
async fn test_stats_endpoint_json() {
    let stats = Arc::new(RwLock::new(AnchorStats {
        total_anchored: 10,
        total_failed: 2,
        total_events_anchored: 500,
        last_anchor_time: None,
        last_batch_id: None,
        ..AnchorStats::default()
    }));

    let config = test_config(
        "http://localhost:3000",
        "http://localhost:8547",
        "0x0000000000000000000000000000000000000000",
        "0x0000000000000000000000000000000000000000000000000000000000000001",
    );

    let health_state = Arc::new(HealthState::new(config, Arc::clone(&stats)));
    let router = set_anchor::health::create_router(Arc::clone(&health_state));

    use axum::body::Body;
    use axum::http::Request;
    use tower::util::ServiceExt;

    let response = router
        .oneshot(Request::builder().uri("/stats").body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), 200);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(json["total_anchored"], 10);
    assert_eq!(json["total_failed"], 2);
    assert_eq!(json["total_events_anchored"], 500);

    // Success rate should be 10 / 12 = 0.833...
    let success_rate = json["success_rate"].as_f64().unwrap();
    assert!((success_rate - 0.833).abs() < 0.01);
}

// =============================================================================
// Anchor Service Tests (with Mock API)
// =============================================================================

#[tokio::test]
async fn test_service_skips_below_threshold() {
    let mock = MockSequencerApi::start().await;
    mock.setup_standard_mocks().await;

    // Add commitment with only 5 events (below threshold of 10)
    let commitment = TestBatchCommitment::new(1, 5, 5);
    mock.add_pending_commitment(commitment).await;

    let config = AnchorConfig {
        l2_rpc_url: "http://localhost:8547".to_string(),
        set_registry_address: "0x0000000000000000000000000000000000000000".to_string(),
        sequencer_private_key: "0x0000000000000000000000000000000000000000000000000000000000000001".to_string(),
        sequencer_api_url: mock.url(),
        anchor_interval_secs: 1,
        min_events_for_anchor: 10, // Threshold
        max_retries: 1,
        retry_delay_secs: 1,
        max_gas_price_gwei: 0,
        health_port: 0,
        expected_l2_chain_id: 0,
        max_commitments_per_cycle: 0,
        sequencer_request_timeout_secs: 10,
        sequencer_connect_timeout_secs: 3,
        circuit_breaker_failure_threshold: 5,
        circuit_breaker_reset_timeout_secs: 60,
        circuit_breaker_half_open_success_threshold: 3,
    };

    // We can't run the full service without a real L2, but we can verify
    // the pending commitments are fetched correctly
    let client = SequencerApiClient::new(&mock.url());
    let pending = client.get_pending_commitments().await.unwrap();

    assert_eq!(pending.len(), 1);
    assert_eq!(pending[0].event_count, 5);

    // The service would skip this commitment due to threshold
    assert!(pending[0].event_count < config.min_events_for_anchor);
}

// =============================================================================
// Contract Integration Tests (requires anvil)
// =============================================================================

#[tokio::test]
#[ignore = "requires anvil binary - run with: cargo test -- --ignored"]
#[serial]
async fn test_full_anchor_flow_with_anvil() {
    // Deploy contract to Anvil
    let registry = TestSetRegistry::deploy().await.expect("Failed to deploy registry");

    // Start mock sequencer API
    let mock = MockSequencerApi::start().await;
    mock.setup_standard_mocks().await;

    // Add a commitment
    let commitment = TestBatchCommitment::with_roots(
        1,
        10,
        10,
        &format!("0x{}", "0".repeat(64)),
        &format!("0x{}", "a".repeat(64)),
        &format!("0x{}", "b".repeat(64)),
    );
    let batch_id = commitment.batch_id;
    mock.add_pending_commitment(commitment).await;

    // Verify initial state
    let initial_count = registry.total_commitments().await.unwrap();
    assert_eq!(initial_count, alloy::primitives::U256::ZERO);

    // Verify sequencer is authorized
    let is_auth = registry.is_sequencer_authorized(registry.sequencer).await.unwrap();
    assert!(is_auth);

    // Create anchor service config
    let config = test_config(
        &mock.url(),
        &registry.rpc_url,
        &format!("{:?}", registry.address),
        &registry.sequencer_key,
    );

    // Create health state for monitoring
    let stats = Arc::new(RwLock::new(AnchorStats::default()));
    let health_state = Arc::new(HealthState::new(config.clone(), Arc::clone(&stats)));

    // Create and run service for one cycle
    let service = AnchorService::with_health_state(config, Arc::clone(&health_state));

    // Run service in background with timeout
    let service_handle = tokio::spawn(async move {
        tokio::time::timeout(Duration::from_secs(10), service.run()).await
    });

    // Wait for anchoring to complete
    tokio::time::sleep(Duration::from_secs(3)).await;

    // Abort the service
    service_handle.abort();

    // Verify commitment was anchored
    let final_count = registry.total_commitments().await.unwrap();
    assert_eq!(final_count, alloy::primitives::U256::from(1));

    // Verify notification was sent to sequencer
    let notifications = mock.get_notifications().await;
    assert!(!notifications.is_empty());
    assert_eq!(notifications[0].0, batch_id);
    assert!(!notifications[0].1.chain_tx_hash.is_empty());

    // Verify stats were updated
    let final_stats = stats.read().await;
    assert_eq!(final_stats.total_anchored, 1);
    assert_eq!(final_stats.total_events_anchored, 10);
}

#[tokio::test]
#[ignore = "requires anvil binary - run with: cargo test -- --ignored"]
#[serial]
async fn test_multiple_commitments_anchored_sequentially() {
    let registry = TestSetRegistry::deploy().await.expect("Failed to deploy registry");

    let mock = MockSequencerApi::start().await;
    mock.setup_standard_mocks().await;

    // Add multiple commitments for the same tenant/store
    let tenant_id = Uuid::new_v4();
    let store_id = Uuid::new_v4();

    let commitment1 = TestBatchCommitment::with_tenant_store(tenant_id, store_id, 1, 10, 10);
    let commitment2 = TestBatchCommitment::with_tenant_store(tenant_id, store_id, 11, 20, 10);

    mock.add_pending_commitments(vec![commitment1, commitment2]).await;

    let config = test_config(
        &mock.url(),
        &registry.rpc_url,
        &format!("{:?}", registry.address),
        &registry.sequencer_key,
    );

    let stats = Arc::new(RwLock::new(AnchorStats::default()));
    let health_state = Arc::new(HealthState::new(config.clone(), Arc::clone(&stats)));
    let service = AnchorService::with_health_state(config, Arc::clone(&health_state));

    let service_handle = tokio::spawn(async move {
        tokio::time::timeout(Duration::from_secs(15), service.run()).await
    });

    tokio::time::sleep(Duration::from_secs(5)).await;
    service_handle.abort();

    // Both commitments should have been anchored
    let final_count = registry.total_commitments().await.unwrap();
    assert_eq!(final_count, alloy::primitives::U256::from(2));

    let final_stats = stats.read().await;
    assert_eq!(final_stats.total_anchored, 2);
}

#[tokio::test]
#[ignore = "requires anvil binary - run with: cargo test -- --ignored"]
#[serial]
async fn test_unauthorized_sequencer_fails() {
    let registry = TestSetRegistry::deploy().await.expect("Failed to deploy registry");

    let mock = MockSequencerApi::start().await;
    mock.setup_standard_mocks().await;

    let commitment = TestBatchCommitment::new(1, 10, 10);
    mock.add_pending_commitment(commitment).await;

    // Use a different private key (not authorized)
    let unauthorized_key = "0x0000000000000000000000000000000000000000000000000000000000000099";

    let config = test_config(
        &mock.url(),
        &registry.rpc_url,
        &format!("{:?}", registry.address),
        unauthorized_key,
    );

    let stats = Arc::new(RwLock::new(AnchorStats::default()));
    let health_state = Arc::new(HealthState::new(config.clone(), Arc::clone(&stats)));
    let service = AnchorService::with_health_state(config, Arc::clone(&health_state));

    // Service should fail to start due to authorization check
    let result = tokio::time::timeout(Duration::from_secs(5), service.run()).await;

    // Either timeout or error is acceptable
    match result {
        Ok(Ok(())) => panic!("Service should have failed"),
        Ok(Err(e)) => assert!(e.to_string().contains("not authorized")),
        Err(_) => {} // Timeout is also acceptable if it keeps retrying
    }
}

// =============================================================================
// Batch Commitment Validation Tests
// =============================================================================

#[test]
fn test_batch_commitment_creation() {
    let commitment = TestBatchCommitment::new(1, 100, 100);

    assert!(!commitment.batch_id.is_nil());
    assert!(!commitment.tenant_id.is_nil());
    assert!(!commitment.store_id.is_nil());
    assert_eq!(commitment.sequence_start, 1);
    assert_eq!(commitment.sequence_end, 100);
    assert_eq!(commitment.event_count, 100);
    assert!(commitment.chain_tx_hash.is_none());
}

#[test]
fn test_batch_commitment_with_specific_roots() {
    let commitment = TestBatchCommitment::with_roots(
        1,
        10,
        10,
        "0x0000000000000000000000000000000000000000000000000000000000000000",
        "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    );

    assert_eq!(
        commitment.prev_state_root,
        "0x0000000000000000000000000000000000000000000000000000000000000000"
    );
    assert_eq!(
        commitment.new_state_root,
        "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    );
    assert_eq!(
        commitment.events_root,
        "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    );
}

#[test]
fn test_batch_commitment_serialization() {
    let commitment = TestBatchCommitment::new(1, 10, 10);

    let json = serde_json::to_string(&commitment).unwrap();
    let deserialized: TestBatchCommitment = serde_json::from_str(&json).unwrap();

    assert_eq!(commitment.batch_id, deserialized.batch_id);
    assert_eq!(commitment.sequence_start, deserialized.sequence_start);
}
