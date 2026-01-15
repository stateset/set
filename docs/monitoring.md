# Set Chain Monitoring and SLOs

## SLO Targets
- L2 block production: 99.9% of intervals <= 3 seconds.
- Batch submission: no more than 30 minutes between L1 submissions.
- Anchor service availability: 99.9% uptime with success rate >= 0.99.
- Anchor lag: commitments anchored within 15 minutes of creation.

## Key Metrics

### OP Stack
- L2 block time and gaps (op-geth/op-node logs).
- Safe head lag and sync status (`optimism_syncStatus`).
- Batch submission interval (op-batcher logs).
- Output submission interval (op-proposer logs).

### Anchor Service
Prometheus metrics from `GET /metrics`:
- `set_anchor_batches_total{status="success"}`
- `set_anchor_batches_total{status="failed"}`
- `set_anchor_events_total`
- `set_anchor_gas_price_skips_total`
- `set_anchor_consecutive_failures`
- `set_anchor_avg_anchor_time_ms`
- `set_anchor_cycles_total`
- `set_anchor_l2_connected`
- `set_anchor_sequencer_connected`
- `set_anchor_l2_connection_failures_total`
- `set_anchor_sequencer_api_failures_total`
- `set_anchor_success_rate`
- `set_anchor_uptime_seconds`
- `set_anchor_ready`
- `set_anchor_errors_total{category="config|l2_connection|sequencer_api|transaction|authorization|internal"}`
- `set_anchor_errors_total_sum`

Additional endpoints:
- `GET /stats` (JSON stats for anchors, cycles, health timestamps)
- `GET /errors` (recent errors with categories and retryability)

## Alert Suggestions
- L2 block gap > 10 seconds (warn) or > 60 seconds (critical).
- Batch submission gap > 30 minutes.
- Anchor success rate < 0.98 over 15 minutes.
- `set_anchor_ready` == 0 for > 60 seconds.
  - Ready requires recent L2 + sequencer health checks.

## Local Monitoring Stack (Docker)
Start Prometheus and Grafana with the included compose file:

```bash
docker compose -f docker/docker-compose.monitoring.yml up -d
```

- Prometheus: http://localhost:9095
- Grafana: http://localhost:3000 (admin/admin)

The Prometheus config scrapes `host.docker.internal:9090` by default. If your
anchor service runs on a different `HEALTH_PORT`, update
`docker/monitoring/prometheus.yml`.

## Log Sources
- `logs/op-geth.log`
- `logs/op-node.log`
- `logs/op-batcher.log`
- `logs/op-proposer.log`
- Anchor service logs (`/tmp/set-anchor.log` for devnet)

## Validation Commands

```bash
# Anchor metrics (HEALTH_PORT, default 9090)
curl http://localhost:9090/metrics

# Anchor health
curl http://localhost:9090/health
curl http://localhost:9090/ready

# L2 sync status
curl -s http://localhost:9545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"optimism_syncStatus","params":[],"id":1}' | jq
```
