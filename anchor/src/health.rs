//! Health check and metrics HTTP server
//!
//! Provides endpoints for Kubernetes probes and monitoring:
//! - GET /health - Liveness probe (always returns 200 if server is running)
//! - GET /ready - Readiness probe (checks L2 and sequencer connectivity)
//! - GET /metrics - Prometheus-compatible metrics
//! - GET /stats - JSON anchor statistics
//! - GET /errors - Error statistics by category

use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Instant;

use axum::{
    extract::State,
    http::StatusCode,
    response::{IntoResponse, Response},
    routing::get,
    Json, Router,
};
use serde::Serialize;
use tokio::sync::RwLock;
use tracing::info;

use crate::config::AnchorConfig;
use crate::error::ErrorSeverity;
use crate::types::AnchorStats;

/// Error counts by category for monitoring
#[derive(Debug, Default, Clone, Serialize)]
pub struct ErrorCounts {
    pub config_errors: u64,
    pub l2_connection_errors: u64,
    pub sequencer_api_errors: u64,
    pub transaction_errors: u64,
    pub authorization_errors: u64,
    pub internal_errors: u64,
    pub last_error_time: Option<String>,
    pub last_error_message: Option<String>,
    pub last_error_code: Option<String>,
}

/// Health server state shared across handlers
pub struct HealthState {
    /// Service start time for uptime calculation
    pub start_time: Instant,

    /// Anchor statistics
    pub stats: Arc<RwLock<AnchorStats>>,

    /// Configuration for connectivity checks
    pub config: AnchorConfig,

    /// Last successful L2 check timestamp
    pub last_l2_check: RwLock<Option<Instant>>,

    /// Last successful sequencer check timestamp
    pub last_sequencer_check: RwLock<Option<Instant>>,

    /// Whether the service is ready to anchor
    pub is_ready: RwLock<bool>,

    /// Error counts by category
    pub error_counts: RwLock<ErrorCounts>,

    /// Recent errors (circular buffer)
    pub recent_errors: RwLock<Vec<ErrorRecord>>,
}

/// Record of a recent error
#[derive(Debug, Clone, Serialize)]
pub struct ErrorRecord {
    pub timestamp: String,
    pub error_code: String,
    pub message: String,
    pub severity: String,
    pub is_retryable: bool,
}

impl HealthState {
    /// Maximum number of recent errors to keep
    const MAX_RECENT_ERRORS: usize = 100;

    pub fn new(config: AnchorConfig, stats: Arc<RwLock<AnchorStats>>) -> Self {
        Self {
            start_time: Instant::now(),
            stats,
            config,
            last_l2_check: RwLock::new(None),
            last_sequencer_check: RwLock::new(None),
            is_ready: RwLock::new(false),
            error_counts: RwLock::new(ErrorCounts::default()),
            recent_errors: RwLock::new(Vec::with_capacity(Self::MAX_RECENT_ERRORS)),
        }
    }

    /// Update readiness status
    pub async fn set_ready(&self, ready: bool) {
        *self.is_ready.write().await = ready;
    }

    /// Update L2 check timestamp
    pub async fn mark_l2_healthy(&self) {
        *self.last_l2_check.write().await = Some(Instant::now());
    }

    /// Update sequencer check timestamp
    pub async fn mark_sequencer_healthy(&self) {
        *self.last_sequencer_check.write().await = Some(Instant::now());
    }

    /// Record an error for tracking
    pub async fn record_error(&self, error: &crate::error::AnchorError) {
        use chrono::Utc;

        let timestamp = Utc::now().to_rfc3339();
        let error_code = error.error_code().to_string();
        let message = error.to_string();
        let severity = error.severity();
        let is_retryable = error.is_retryable();

        // Update counts
        {
            let mut counts = self.error_counts.write().await;
            match error {
                crate::error::AnchorError::Config(_) => counts.config_errors += 1,
                crate::error::AnchorError::L2Connection(_) => counts.l2_connection_errors += 1,
                crate::error::AnchorError::SequencerApi(_) => counts.sequencer_api_errors += 1,
                crate::error::AnchorError::Transaction(_) => counts.transaction_errors += 1,
                crate::error::AnchorError::Authorization(_) => counts.authorization_errors += 1,
                crate::error::AnchorError::Internal(_) => counts.internal_errors += 1,
            }
            counts.last_error_time = Some(timestamp.clone());
            counts.last_error_message = Some(message.clone());
            counts.last_error_code = Some(error_code.clone());
        }

        // Add to recent errors (circular buffer)
        {
            let mut recent = self.recent_errors.write().await;
            if recent.len() >= Self::MAX_RECENT_ERRORS {
                recent.remove(0);
            }
            recent.push(ErrorRecord {
                timestamp,
                error_code,
                message,
                severity: format!("{:?}", severity),
                is_retryable,
            });
        }
    }

    /// Get error counts
    pub async fn get_error_counts(&self) -> ErrorCounts {
        self.error_counts.read().await.clone()
    }

    /// Get recent errors
    pub async fn get_recent_errors(&self, limit: usize) -> Vec<ErrorRecord> {
        let errors = self.recent_errors.read().await;
        let start = if errors.len() > limit {
            errors.len() - limit
        } else {
            0
        };
        errors[start..].to_vec()
    }

    /// Clear error counts (for testing/reset)
    pub async fn clear_errors(&self) {
        *self.error_counts.write().await = ErrorCounts::default();
        self.recent_errors.write().await.clear();
    }
}

/// Liveness response
#[derive(Debug, Serialize)]
pub struct HealthResponse {
    pub status: &'static str,
    pub version: &'static str,
    pub uptime_secs: u64,
}

/// Readiness response
#[derive(Debug, Serialize)]
pub struct ReadyResponse {
    pub ready: bool,
    pub l2_connected: bool,
    pub sequencer_connected: bool,
    pub last_l2_check_secs_ago: Option<u64>,
    pub last_sequencer_check_secs_ago: Option<u64>,
}

/// Stats response
#[derive(Debug, Serialize)]
pub struct StatsResponse {
    pub total_anchored: u64,
    pub total_failed: u64,
    pub total_events_anchored: u64,
    pub success_rate: f64,
    pub last_anchor_time: Option<String>,
    pub last_batch_id: Option<String>,
    pub consecutive_failures: u64,
    pub l2_connection_failures: u64,
    pub sequencer_api_failures: u64,
    pub gas_price_skips: u64,
    pub avg_anchor_time_ms: u64,
    pub last_l2_healthy: Option<String>,
    pub last_sequencer_healthy: Option<String>,
    pub total_cycles: u64,
    pub service_started: Option<String>,
    pub uptime_secs: u64,
}

/// Errors response
#[derive(Debug, Serialize)]
pub struct ErrorsResponse {
    pub counts: ErrorCounts,
    pub recent_errors: Vec<ErrorRecord>,
}

/// Health check handler - liveness probe
async fn health_handler(State(state): State<Arc<HealthState>>) -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "ok",
        version: env!("CARGO_PKG_VERSION"),
        uptime_secs: state.start_time.elapsed().as_secs(),
    })
}

/// Readiness check handler - readiness probe
async fn ready_handler(State(state): State<Arc<HealthState>>) -> Response {
    let is_ready = *state.is_ready.read().await;

    let last_l2 = state.last_l2_check.read().await;
    let last_seq = state.last_sequencer_check.read().await;

    // Consider healthy if checked within last 60 seconds
    let l2_healthy = last_l2
        .map(|t| t.elapsed().as_secs() < 60)
        .unwrap_or(false);
    let seq_healthy = last_seq
        .map(|t| t.elapsed().as_secs() < 60)
        .unwrap_or(false);

    let response = ReadyResponse {
        ready: is_ready && l2_healthy && seq_healthy,
        l2_connected: l2_healthy,
        sequencer_connected: seq_healthy,
        last_l2_check_secs_ago: last_l2.map(|t| t.elapsed().as_secs()),
        last_sequencer_check_secs_ago: last_seq.map(|t| t.elapsed().as_secs()),
    };

    if response.ready {
        (StatusCode::OK, Json(response)).into_response()
    } else {
        (StatusCode::SERVICE_UNAVAILABLE, Json(response)).into_response()
    }
}

/// Metrics handler - Prometheus format
async fn metrics_handler(State(state): State<Arc<HealthState>>) -> String {
    let stats = state.stats.read().await;
    let error_counts = state.error_counts.read().await;
    let uptime = state.start_time.elapsed().as_secs();
    let last_l2 = state.last_l2_check.read().await;
    let last_seq = state.last_sequencer_check.read().await;

    let total = stats.total_anchored + stats.total_failed;
    let success_rate = if total > 0 {
        stats.total_anchored as f64 / total as f64
    } else {
        1.0
    };

    let is_ready = *state.is_ready.read().await;
    let l2_healthy = last_l2
        .map(|t| t.elapsed().as_secs() < 60)
        .unwrap_or(false);
    let seq_healthy = last_seq
        .map(|t| t.elapsed().as_secs() < 60)
        .unwrap_or(false);
    let is_ready = if is_ready && l2_healthy && seq_healthy { 1 } else { 0 };
    let l2_connected = if l2_healthy { 1 } else { 0 };
    let sequencer_connected = if seq_healthy { 1 } else { 0 };

    let total_errors = error_counts.config_errors
        + error_counts.l2_connection_errors
        + error_counts.sequencer_api_errors
        + error_counts.transaction_errors
        + error_counts.authorization_errors
        + error_counts.internal_errors;

    format!(
        r#"# HELP set_anchor_batches_total Total number of batches processed
# TYPE set_anchor_batches_total counter
set_anchor_batches_total{{status="success"}} {}
set_anchor_batches_total{{status="failed"}} {}

# HELP set_anchor_events_total Total number of events anchored
# TYPE set_anchor_events_total counter
set_anchor_events_total {}

# HELP set_anchor_gas_price_skips_total Total number of gas price skips
# TYPE set_anchor_gas_price_skips_total counter
set_anchor_gas_price_skips_total {}

# HELP set_anchor_consecutive_failures Consecutive failed anchors
# TYPE set_anchor_consecutive_failures gauge
set_anchor_consecutive_failures {}

# HELP set_anchor_avg_anchor_time_ms Average anchor time in milliseconds
# TYPE set_anchor_avg_anchor_time_ms gauge
set_anchor_avg_anchor_time_ms {}

# HELP set_anchor_cycles_total Total anchor cycles completed
# TYPE set_anchor_cycles_total counter
set_anchor_cycles_total {}

# HELP set_anchor_l2_connected Whether L2 is reachable
# TYPE set_anchor_l2_connected gauge
set_anchor_l2_connected {}

# HELP set_anchor_sequencer_connected Whether the sequencer API is reachable
# TYPE set_anchor_sequencer_connected gauge
set_anchor_sequencer_connected {}

# HELP set_anchor_l2_connection_failures_total Total L2 connection failures
# TYPE set_anchor_l2_connection_failures_total counter
set_anchor_l2_connection_failures_total {}

# HELP set_anchor_sequencer_api_failures_total Total sequencer API failures
# TYPE set_anchor_sequencer_api_failures_total counter
set_anchor_sequencer_api_failures_total {}

# HELP set_anchor_success_rate Ratio of successful anchors
# TYPE set_anchor_success_rate gauge
set_anchor_success_rate {}

# HELP set_anchor_uptime_seconds Service uptime in seconds
# TYPE set_anchor_uptime_seconds gauge
set_anchor_uptime_seconds {}

# HELP set_anchor_ready Whether the service is ready
# TYPE set_anchor_ready gauge
set_anchor_ready {}

# HELP set_anchor_errors_total Total errors by category
# TYPE set_anchor_errors_total counter
set_anchor_errors_total{{category="config"}} {}
set_anchor_errors_total{{category="l2_connection"}} {}
set_anchor_errors_total{{category="sequencer_api"}} {}
set_anchor_errors_total{{category="transaction"}} {}
set_anchor_errors_total{{category="authorization"}} {}
set_anchor_errors_total{{category="internal"}} {}

# HELP set_anchor_errors_total_sum Sum of all errors
# TYPE set_anchor_errors_total_sum counter
set_anchor_errors_total_sum {}
"#,
        stats.total_anchored,
        stats.total_failed,
        stats.total_events_anchored,
        stats.gas_price_skips,
        stats.consecutive_failures,
        stats.avg_anchor_time_ms,
        stats.total_cycles,
        l2_connected,
        sequencer_connected,
        stats.l2_connection_failures,
        stats.sequencer_api_failures,
        success_rate,
        uptime,
        is_ready,
        error_counts.config_errors,
        error_counts.l2_connection_errors,
        error_counts.sequencer_api_errors,
        error_counts.transaction_errors,
        error_counts.authorization_errors,
        error_counts.internal_errors,
        total_errors,
    )
}

/// Errors handler - error statistics
async fn errors_handler(State(state): State<Arc<HealthState>>) -> Json<ErrorsResponse> {
    let counts = state.get_error_counts().await;
    let recent_errors = state.get_recent_errors(20).await;

    Json(ErrorsResponse {
        counts,
        recent_errors,
    })
}

/// Stats handler - JSON statistics
async fn stats_handler(State(state): State<Arc<HealthState>>) -> Json<StatsResponse> {
    let stats = state.stats.read().await;
    let uptime = state.start_time.elapsed().as_secs();

    let total = stats.total_anchored + stats.total_failed;
    let success_rate = if total > 0 {
        stats.total_anchored as f64 / total as f64
    } else {
        1.0
    };

    Json(StatsResponse {
        total_anchored: stats.total_anchored,
        total_failed: stats.total_failed,
        total_events_anchored: stats.total_events_anchored,
        success_rate,
        last_anchor_time: stats.last_anchor_time.map(|t| t.to_rfc3339()),
        last_batch_id: stats.last_batch_id.map(|id| id.to_string()),
        consecutive_failures: stats.consecutive_failures,
        l2_connection_failures: stats.l2_connection_failures,
        sequencer_api_failures: stats.sequencer_api_failures,
        gas_price_skips: stats.gas_price_skips,
        avg_anchor_time_ms: stats.avg_anchor_time_ms,
        last_l2_healthy: stats.last_l2_healthy.map(|t| t.to_rfc3339()),
        last_sequencer_healthy: stats.last_sequencer_healthy.map(|t| t.to_rfc3339()),
        total_cycles: stats.total_cycles,
        service_started: stats.service_started.map(|t| t.to_rfc3339()),
        uptime_secs: uptime,
    })
}

/// Create the health server router
pub fn create_router(state: Arc<HealthState>) -> Router {
    Router::new()
        .route("/health", get(health_handler))
        .route("/ready", get(ready_handler))
        .route("/metrics", get(metrics_handler))
        .route("/stats", get(stats_handler))
        .route("/errors", get(errors_handler))
        .with_state(state)
}

/// Health server that runs alongside the anchor service
pub struct HealthServer {
    state: Arc<HealthState>,
    port: u16,
}

impl HealthServer {
    /// Create a new health server
    pub fn new(config: AnchorConfig, stats: Arc<RwLock<AnchorStats>>, port: u16) -> Self {
        let state = Arc::new(HealthState::new(config, stats));
        Self { state, port }
    }

    /// Create a health server with an existing shared state
    pub fn with_state(state: Arc<HealthState>, port: u16) -> Self {
        Self { state, port }
    }

    /// Get shared state for updates from anchor service
    pub fn state(&self) -> Arc<HealthState> {
        Arc::clone(&self.state)
    }

    /// Run the health server
    pub async fn run(&self) -> anyhow::Result<()> {
        let addr = SocketAddr::from(([0, 0, 0, 0], self.port));
        let router = create_router(Arc::clone(&self.state));

        info!(port = self.port, "Health server starting");

        let listener = tokio::net::TcpListener::bind(addr).await?;
        axum::serve(listener, router).await?;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::error::{AnchorError, L2Error};
    use axum::body::Body;
    use axum::http::Request;
    use tower::ServiceExt;

    fn test_config() -> AnchorConfig {
        AnchorConfig {
            l2_rpc_url: "http://localhost:8547".to_string(),
            set_registry_address: "0x0000000000000000000000000000000000000000".to_string(),
            sequencer_private_key: "0x0000000000000000000000000000000000000000000000000000000000000001".to_string(),
            sequencer_api_url: "http://localhost:8080".to_string(),
            anchor_interval_secs: 30,
            min_events_for_anchor: 1,
            max_retries: 3,
            retry_delay_secs: 5,
            health_port: 9090,
            max_gas_price_gwei: 0,
        }
    }

    #[tokio::test]
    async fn test_health_endpoint() {
        let stats = Arc::new(RwLock::new(AnchorStats::default()));
        let state = Arc::new(HealthState::new(test_config(), stats));
        let router = create_router(state);

        let response = router
            .oneshot(
                Request::builder()
                    .uri("/health")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn test_ready_endpoint_not_ready() {
        let stats = Arc::new(RwLock::new(AnchorStats::default()));
        let state = Arc::new(HealthState::new(test_config(), stats));
        let router = create_router(state);

        let response = router
            .oneshot(
                Request::builder()
                    .uri("/ready")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        // Should be 503 when not ready
        assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
    }

    #[tokio::test]
    async fn test_ready_endpoint_requires_sequencer() {
        let stats = Arc::new(RwLock::new(AnchorStats::default()));
        let state = Arc::new(HealthState::new(test_config(), stats));

        state.set_ready(true).await;
        state.mark_l2_healthy().await;

        let router = create_router(state);

        let response = router
            .oneshot(
                Request::builder()
                    .uri("/ready")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
    }

    #[tokio::test]
    async fn test_ready_endpoint_ready() {
        let stats = Arc::new(RwLock::new(AnchorStats::default()));
        let state = Arc::new(HealthState::new(test_config(), stats));

        // Mark as ready
        state.set_ready(true).await;
        state.mark_l2_healthy().await;
        state.mark_sequencer_healthy().await;

        let router = create_router(state);

        let response = router
            .oneshot(
                Request::builder()
                    .uri("/ready")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(json["sequencer_connected"], true);
    }

    #[tokio::test]
    async fn test_metrics_endpoint() {
        let stats = Arc::new(RwLock::new(AnchorStats {
            total_anchored: 10,
            total_failed: 2,
            total_events_anchored: 500,
            last_anchor_time: None,
            last_batch_id: None,
            ..AnchorStats::default()
        }));
        let state = Arc::new(HealthState::new(test_config(), stats));
        let router = create_router(state);

        let response = router
            .oneshot(
                Request::builder()
                    .uri("/metrics")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let body_str = String::from_utf8(body.to_vec()).unwrap();

        assert!(body_str.contains("set_anchor_batches_total{status=\"success\"} 10"));
        assert!(body_str.contains("set_anchor_batches_total{status=\"failed\"} 2"));
        assert!(body_str.contains("set_anchor_events_total 500"));
        assert!(body_str.contains("set_anchor_gas_price_skips_total 0"));
        assert!(body_str.contains("set_anchor_cycles_total 0"));
        assert!(body_str.contains("set_anchor_l2_connected 0"));
        assert!(body_str.contains("set_anchor_sequencer_connected 0"));
        assert!(body_str.contains("set_anchor_errors_total{category=\"l2_connection\"} 0"));
    }

    #[tokio::test]
    async fn test_stats_endpoint() {
        let stats = Arc::new(RwLock::new(AnchorStats::default()));
        let state = Arc::new(HealthState::new(test_config(), stats));
        let router = create_router(state);

        let response = router
            .oneshot(
                Request::builder()
                    .uri("/stats")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn test_errors_endpoint() {
        let stats = Arc::new(RwLock::new(AnchorStats::default()));
        let state = Arc::new(HealthState::new(test_config(), stats));

        // Record some errors
        let error = AnchorError::L2Connection(L2Error::Timeout { seconds: 30 });
        state.record_error(&error).await;

        let router = create_router(state);

        let response = router
            .oneshot(
                Request::builder()
                    .uri("/errors")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let body_str = String::from_utf8(body.to_vec()).unwrap();

        assert!(body_str.contains("l2_connection_errors"));
    }

    #[tokio::test]
    async fn test_record_error() {
        let stats = Arc::new(RwLock::new(AnchorStats::default()));
        let state = Arc::new(HealthState::new(test_config(), stats));

        let error = AnchorError::L2Connection(L2Error::ConnectionFailed {
            url: "http://localhost:8547".to_string(),
            message: "Connection refused".to_string(),
        });

        state.record_error(&error).await;

        let counts = state.get_error_counts().await;
        assert_eq!(counts.l2_connection_errors, 1);
        assert!(counts.last_error_code.is_some());
        assert_eq!(counts.last_error_code.unwrap(), "L2_CONNECTION_ERROR");

        let recent = state.get_recent_errors(10).await;
        assert_eq!(recent.len(), 1);
        assert!(recent[0].is_retryable);
    }
}
