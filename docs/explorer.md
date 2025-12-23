# Block Explorer and Indexing

Set Chain uses Blockscout as its block explorer, providing full transaction
history, contract verification, and API access.

## Quick Start

```bash
# Start the complete explorer stack
docker compose -f docker/docker-compose.explorer.yml up -d

# View logs
docker compose -f docker/docker-compose.explorer.yml logs -f
```

**Access Points:**
- Frontend: http://localhost:3000
- API: http://localhost:4000/api
- GraphQL: http://localhost:4000/graphiql
- Contract Verifier: http://localhost:8050

## Components

| Service | Image | Purpose |
|---------|-------|---------|
| blockscout-backend | blockscout/blockscout | Indexer and API |
| blockscout-frontend | ghcr.io/blockscout/frontend | Next.js UI |
| smart-contract-verifier | ghcr.io/blockscout/smart-contract-verifier | Solidity/Vyper verification |
| visualizer | ghcr.io/blockscout/visualizer | Contract diagrams |
| blockscout-db | postgres:16-alpine | Database |
| redis | redis:7-alpine | Caching |

## Configuration

### Environment Variables

```bash
# Required
L2_RPC_URL=http://localhost:8547      # L2 execution RPC
L2_WS_URL=ws://localhost:8548         # L2 websocket
L1_RPC_URL=http://localhost:8545      # L1 RPC for rollup data

# Optional
L1_EXPLORER_URL=https://sepolia.etherscan.io  # Link to L1 explorer
SECRET_KEY_BASE=<random-64-char-string>       # Session encryption
```

### Chain Configuration

The explorer is pre-configured for Set Chain:
- Chain ID: `84532001`
- Network Name: `Set Chain`
- Currency: ETH
- Chain Type: Optimism (L2)
- Block Time: 2 seconds

## Contract Verification

### Via UI

1. Navigate to the contract address
2. Click "Verify & Publish"
3. Select compiler version (0.8.20)
4. Paste source code or upload JSON

### Via API

```bash
curl -X POST http://localhost:4000/api/v2/smart-contracts/verification/via/standard-input \
  -H "Content-Type: application/json" \
  -d '{
    "address": "0x...",
    "compiler_version": "v0.8.20+commit.a1b79de6",
    "source_code": {...}
  }'
```

### Via Foundry

```bash
forge verify-contract \
  --chain-id 84532001 \
  --verifier blockscout \
  --verifier-url http://localhost:4000/api \
  <CONTRACT_ADDRESS> \
  src/SetRegistry.sol:SetRegistry
```

## API Reference

### REST API

```bash
# Get block by number
curl http://localhost:4000/api/v2/blocks/123

# Get transaction
curl http://localhost:4000/api/v2/transactions/0x...

# Get address info
curl http://localhost:4000/api/v2/addresses/0x...

# Search
curl "http://localhost:4000/api/v2/search?q=SetRegistry"
```

### GraphQL

```graphql
query {
  block(number: 123) {
    hash
    timestamp
    transactions {
      hash
      from
      to
      value
    }
  }
}
```

## Production Deployment

### Hardware Requirements

| Component | CPU | RAM | Storage |
|-----------|-----|-----|---------|
| Backend | 4 cores | 8 GB | 100 GB SSD |
| Database | 4 cores | 16 GB | 500 GB SSD |
| Frontend | 2 cores | 4 GB | 10 GB |

### High Availability

1. **Database**: Use managed PostgreSQL (RDS, Cloud SQL)
2. **Backend**: Run multiple replicas behind load balancer
3. **Frontend**: Deploy to CDN (Vercel, Cloudflare)
4. **Redis**: Use managed Redis (ElastiCache, Memorystore)

### Monitoring

Add to your Prometheus configuration:

```yaml
- job_name: 'blockscout'
  static_configs:
    - targets: ['blockscout-backend:4000']
  metrics_path: /metrics
```

Key metrics:
- `blockscout_block_number` - Latest indexed block
- `blockscout_pending_transactions_count` - Pending tx queue
- `blockscout_indexer_* ` - Indexer performance

## Operational Notes

- Run the explorer on separate hardware from sequencer components
- Monitor indexer lag (should be < 10 blocks behind chain head)
- Back up PostgreSQL database daily
- Set up alerting for indexer failures
- Consider read replicas for high API traffic

## Troubleshooting

### Indexer stuck

```bash
# Check indexer status
docker compose -f docker/docker-compose.explorer.yml logs blockscout-backend | grep -i error

# Reset indexer (WARNING: loses history)
docker compose -f docker/docker-compose.explorer.yml down -v
docker compose -f docker/docker-compose.explorer.yml up -d
```

### Contract verification fails

1. Ensure exact compiler version match
2. Check optimizer settings match deployment
3. Verify constructor arguments are correct
4. Try Sourcify verification as fallback

## Evidence

Record explorer deployment in `docs/operations-history.md`:
- Explorer URL
- Deployment date
- Version
- Any customizations
