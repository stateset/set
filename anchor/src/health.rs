//! Health check and metrics HTTP server
//!
//! Provides endpoints for Kubernetes probes and monitoring:
//! - GET /health - Liveness probe (always returns 200 if server is running)
//! - GET /ready - Readiness probe (checks L2 and sequencer connectivity)
//! - GET /metrics - Prometheus-compatible metrics
//! - GET /stats - JSON anchor statistics

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
use tracing::{debug, error, info};

use crate::config::AnchorConfig;
use crate::types::AnchorStats;

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
}

impl HealthState {
    pub fn new(config: AnchorConfig, stats: Arc<RwLock<AnchorStats>>) -> Self {
        Self {
            start_time: Instant::now(),
            stats,
            config,
            last_l2_check: RwLock::new(None),
            last_sequencer_check: RwLock::new(None),
            is_ready: RwLock::new(false),
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
    pub uptime_secs: u64,
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
        ready: is_ready && l2_healthy,
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
    let uptime = state.start_time.elapsed().as_secs();

    let total = stats.total_anchored + stats.total_failed;
    let success_rate = if total > 0 {
        stats.total_anchored as f64 / total as f64
    } else {
        1.0
    };

    let is_ready = if *state.is_ready.read().await { 1 } else { 0 };

    format!(
        r#"# HELP set_anchor_batches_total Total number of batches processed
# TYPE set_anchor_batches_total counter
set_anchor_batches_total{{status="success"}} {}
set_anchor_batches_total{{status="failed"}} {}

# HELP set_anchor_events_total Total number of events anchored
# TYPE set_anchor_events_total counter
set_anchor_events_total {}

# HELP set_anchor_success_rate Ratio of successful anchors
# TYPE set_anchor_success_rate gauge
set_anchor_success_rate {}

# HELP set_anchor_uptime_seconds Service uptime in seconds
# TYPE set_anchor_uptime_seconds gauge
set_anchor_uptime_seconds {}

# HELP set_anchor_ready Whether the service is ready
# TYPE set_anchor_ready gauge
set_anchor_ready {}
"#,
        stats.total_anchored,
        stats.total_failed,
        stats.total_events_anchored,
        success_rate,
        uptime,
        is_ready,
    )
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
    async fn test_ready_endpoint_ready() {
        let stats = Arc::new(RwLock::new(AnchorStats::default()));
        let state = Arc::new(HealthState::new(test_config(), stats));

        // Mark as ready
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

        assert_eq!(response.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn test_metrics_endpoint() {
        let stats = Arc::new(RwLock::new(AnchorStats {
            total_anchored: 10,
            total_failed: 2,
            total_events_anchored: 500,
            last_anchor_time: None,
            last_batch_id: None,
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
}
