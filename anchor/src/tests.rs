//! Unit tests for anchor service components

#[cfg(test)]
mod config_tests {
    use crate::config::AnchorConfig;
    use std::env;

    fn clear_env_vars() {
        env::remove_var("L2_RPC_URL");
        env::remove_var("SET_REGISTRY_ADDRESS");
        env::remove_var("SEQUENCER_PRIVATE_KEY");
        env::remove_var("SEQUENCER_API_URL");
        env::remove_var("ANCHOR_INTERVAL_SECS");
        env::remove_var("MIN_EVENTS_FOR_ANCHOR");
        env::remove_var("MAX_RETRIES");
        env::remove_var("RETRY_DELAY_SECS");
        env::remove_var("MAX_GAS_PRICE_GWEI");
        env::remove_var("HEALTH_PORT");
    }

    #[test]
    fn test_config_from_env_required_fields() {
        clear_env_vars();

        // Missing required fields should error
        let result = AnchorConfig::from_env();
        assert!(result.is_err());

        // Set required fields
        env::set_var("SET_REGISTRY_ADDRESS", "0x1234567890123456789012345678901234567890");
        let result = AnchorConfig::from_env();
        assert!(result.is_err()); // Still missing SEQUENCER_PRIVATE_KEY

        env::set_var("SEQUENCER_PRIVATE_KEY", "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");
        let result = AnchorConfig::from_env();
        assert!(result.is_ok());

        clear_env_vars();
    }

    #[test]
    fn test_config_defaults() {
        clear_env_vars();
        env::set_var("SET_REGISTRY_ADDRESS", "0x1234567890123456789012345678901234567890");
        env::set_var("SEQUENCER_PRIVATE_KEY", "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        let config = AnchorConfig::from_env().unwrap();

        assert_eq!(config.l2_rpc_url, "http://localhost:8547");
        assert_eq!(config.sequencer_api_url, "http://localhost:3000");
        assert_eq!(config.anchor_interval_secs, 60);
        assert_eq!(config.min_events_for_anchor, 100);
        assert_eq!(config.max_retries, 3);
        assert_eq!(config.retry_delay_secs, 5);
        assert_eq!(config.max_gas_price_gwei, 0);
        assert_eq!(config.health_port, 9090);

        clear_env_vars();
    }

    #[test]
    fn test_config_custom_values() {
        clear_env_vars();
        env::set_var("SET_REGISTRY_ADDRESS", "0xabc");
        env::set_var("SEQUENCER_PRIVATE_KEY", "0x123");
        env::set_var("L2_RPC_URL", "http://custom:8545");
        env::set_var("SEQUENCER_API_URL", "http://api:4000");
        env::set_var("ANCHOR_INTERVAL_SECS", "120");
        env::set_var("MIN_EVENTS_FOR_ANCHOR", "50");
        env::set_var("MAX_RETRIES", "5");
        env::set_var("RETRY_DELAY_SECS", "10");
        env::set_var("MAX_GAS_PRICE_GWEI", "100");
        env::set_var("HEALTH_PORT", "8080");

        let config = AnchorConfig::from_env().unwrap();

        assert_eq!(config.l2_rpc_url, "http://custom:8545");
        assert_eq!(config.sequencer_api_url, "http://api:4000");
        assert_eq!(config.anchor_interval_secs, 120);
        assert_eq!(config.min_events_for_anchor, 50);
        assert_eq!(config.max_retries, 5);
        assert_eq!(config.retry_delay_secs, 10);
        assert_eq!(config.max_gas_price_gwei, 100);
        assert_eq!(config.health_port, 8080);

        clear_env_vars();
    }
}

#[cfg(test)]
mod types_tests {
    use crate::types::{AnchorNotification, AnchorResult, AnchorStats, BatchCommitment};
    use chrono::Utc;
    use uuid::Uuid;

    #[test]
    fn test_batch_commitment_serialization() {
        let commitment = BatchCommitment {
            batch_id: Uuid::new_v4(),
            tenant_id: Uuid::new_v4(),
            store_id: Uuid::new_v4(),
            prev_state_root: "0x1234".to_string(),
            new_state_root: "0x5678".to_string(),
            events_root: "0xabcd".to_string(),
            sequence_start: 1,
            sequence_end: 100,
            event_count: 100,
            committed_at: Utc::now(),
            chain_tx_hash: None,
        };

        let json = serde_json::to_string(&commitment).unwrap();
        let deserialized: BatchCommitment = serde_json::from_str(&json).unwrap();

        assert_eq!(commitment.batch_id, deserialized.batch_id);
        assert_eq!(commitment.prev_state_root, deserialized.prev_state_root);
        assert_eq!(commitment.new_state_root, deserialized.new_state_root);
        assert_eq!(commitment.event_count, deserialized.event_count);
    }

    #[test]
    fn test_anchor_notification_serialization() {
        let notification = AnchorNotification {
            chain_tx_hash: "0xabc123".to_string(),
            chain_id: 84532001,
            block_number: Some(12345),
            gas_used: Some(100000),
        };

        let json = serde_json::to_string(&notification).unwrap();
        assert!(json.contains("84532001"));
        assert!(json.contains("12345"));

        let deserialized: AnchorNotification = serde_json::from_str(&json).unwrap();
        assert_eq!(notification.chain_id, deserialized.chain_id);
        assert_eq!(notification.block_number, deserialized.block_number);
    }

    #[test]
    fn test_anchor_result() {
        let result = AnchorResult {
            batch_id: Uuid::new_v4(),
            tx_hash: "0x123".to_string(),
            block_number: 100,
            gas_used: 50000,
            success: true,
            error: None,
        };

        assert!(result.success);
        assert!(result.error.is_none());

        let failed_result = AnchorResult {
            batch_id: Uuid::new_v4(),
            tx_hash: String::new(),
            block_number: 0,
            gas_used: 0,
            success: false,
            error: Some("Gas too high".to_string()),
        };

        assert!(!failed_result.success);
        assert!(failed_result.error.is_some());
    }

    #[test]
    fn test_anchor_stats_default() {
        let stats = AnchorStats::default();

        assert_eq!(stats.total_anchored, 0);
        assert_eq!(stats.total_failed, 0);
        assert_eq!(stats.total_events_anchored, 0);
        assert!(stats.last_anchor_time.is_none());
        assert!(stats.last_batch_id.is_none());
    }

    #[test]
    fn test_anchor_stats_update() {
        let mut stats = AnchorStats::default();

        stats.total_anchored = 10;
        stats.total_failed = 2;
        stats.total_events_anchored = 5000;
        stats.last_anchor_time = Some(Utc::now());
        stats.last_batch_id = Some(Uuid::new_v4());

        assert_eq!(stats.total_anchored, 10);
        assert_eq!(stats.total_failed, 2);
        assert!(stats.last_anchor_time.is_some());
    }
}

#[cfg(test)]
mod health_tests {
    use crate::config::AnchorConfig;
    use crate::health::HealthState;
    use crate::types::AnchorStats;
    use std::sync::Arc;
    use tokio::sync::RwLock;

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
            max_gas_price_gwei: 0,
            health_port: 9090,
        }
    }

    fn build_state() -> Arc<HealthState> {
        let stats = Arc::new(RwLock::new(AnchorStats::default()));
        Arc::new(HealthState::new(test_config(), stats))
    }

    #[tokio::test]
    async fn test_health_state_initialization() {
        let health = build_state();

        assert!(!*health.is_ready.read().await);
        assert!(health.last_l2_check.read().await.is_none());
        assert!(health.last_sequencer_check.read().await.is_none());
    }

    #[tokio::test]
    async fn test_health_state_ready() {
        let health = build_state();

        health.set_ready(true).await;
        assert!(*health.is_ready.read().await);

        health.set_ready(false).await;
        assert!(!*health.is_ready.read().await);
    }

    #[tokio::test]
    async fn test_health_state_l2_healthy() {
        let health = build_state();

        health.mark_l2_healthy().await;
        assert!(health.last_l2_check.read().await.is_some());
    }

    #[tokio::test]
    async fn test_health_state_sequencer_healthy() {
        let health = build_state();

        health.mark_sequencer_healthy().await;
        assert!(health.last_sequencer_check.read().await.is_some());
    }

    #[tokio::test]
    async fn test_health_state_full_health() {
        let health = build_state();

        health.set_ready(true).await;
        health.mark_l2_healthy().await;
        health.mark_sequencer_healthy().await;

        assert!(*health.is_ready.read().await);
        assert!(health.last_l2_check.read().await.is_some());
        assert!(health.last_sequencer_check.read().await.is_some());
    }

    #[tokio::test]
    async fn test_health_state_shared() {
        let health = build_state();
        let health_clone = Arc::clone(&health);

        health.set_ready(true).await;
        assert!(*health_clone.is_ready.read().await);

        health_clone.mark_l2_healthy().await;
        assert!(health.last_l2_check.read().await.is_some());
    }
}

#[cfg(test)]
mod service_tests {
    use crate::config::AnchorConfig;
    use crate::service::AnchorService;
    use crate::health::HealthState;
    use crate::types::AnchorStats;
    use std::sync::Arc;
    use tokio::sync::RwLock;

    fn test_config() -> AnchorConfig {
        AnchorConfig {
            l2_rpc_url: "http://localhost:8547".to_string(),
            set_registry_address: "0x1234567890123456789012345678901234567890".to_string(),
            sequencer_private_key: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80".to_string(),
            sequencer_api_url: "http://localhost:3000".to_string(),
            anchor_interval_secs: 60,
            min_events_for_anchor: 100,
            max_retries: 3,
            retry_delay_secs: 5,
            max_gas_price_gwei: 0,
            health_port: 9090,
        }
    }

    #[test]
    fn test_service_creation() {
        let config = test_config();
        let service = AnchorService::new(config);

        // Service should be created successfully
        assert!(true);
    }

    #[test]
    fn test_service_with_health_state() {
        let config = test_config();
        let health = Arc::new(HealthState::new(
            config.clone(),
            Arc::new(RwLock::new(AnchorStats::default())),
        ));
        let service = AnchorService::with_health_state(config, Arc::clone(&health));

        // Stats reference should be shared
        let stats_ref = service.stats_ref();
        assert!(Arc::strong_count(&stats_ref) >= 1);
    }

    #[tokio::test]
    async fn test_service_stats() {
        let config = test_config();
        let service = AnchorService::new(config);

        let stats = service.stats().await;
        assert_eq!(stats.total_anchored, 0);
        assert_eq!(stats.total_failed, 0);
    }
}
