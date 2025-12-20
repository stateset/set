# Anchor Service Integration Tests

## Running Tests

### Unit Tests (no external dependencies)
```bash
cargo test --lib
```

### Integration Tests (mock API only)
```bash
cargo test --test integration
```

### Full Integration Tests (requires Anvil)
```bash
# Install Anvil (part of Foundry)
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Run all tests including contract tests
cargo test --test integration -- --ignored
```

## Test Categories

### Mock Sequencer API Tests
Tests the anchor service's interaction with the sequencer API using a mock server:
- `test_sequencer_api_client_fetch_pending` - Fetching pending commitments
- `test_sequencer_api_client_empty_pending` - Handling empty response
- `test_sequencer_api_client_handles_error` - Error handling
- `test_anchor_notification_recorded` - Anchor notifications

### Health Endpoint Tests
Tests the health/metrics HTTP endpoints:
- `test_health_endpoint_returns_ok` - Liveness probe
- `test_ready_endpoint_not_ready_initially` - Initial readiness state
- `test_ready_endpoint_becomes_ready` - Ready after initialization
- `test_metrics_endpoint_format` - Prometheus metrics format
- `test_stats_endpoint_json` - JSON statistics

### Contract Integration Tests (requires Anvil)
Full end-to-end tests with real contract deployment:
- `test_full_anchor_flow_with_anvil` - Complete anchor cycle
- `test_multiple_commitments_anchored_sequentially` - Sequential anchoring
- `test_unauthorized_sequencer_fails` - Authorization checks

## Test Fixtures

The `fixtures/` directory contains:
- `SetRegistry.bin` - Compiled contract bytecode (placeholder)

To use real contract bytecode:
```bash
cd ../contracts
forge build
cp out/SetRegistry.sol/SetRegistry.bin ../anchor/tests/fixtures/
```

## CI Integration

For CI environments, run:
```bash
# Skip Anvil-dependent tests in CI without Anvil
cargo test --test integration 2>&1 | grep -v "ignored"

# Or with Anvil installed
cargo test --test integration -- --include-ignored
```
