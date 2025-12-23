# Bridge and Onramp Support

Set Chain uses the OP Stack Standard Bridge for asset transfers between L1
(Ethereum) and L2 (Set Chain).

## Overview

```
┌─────────────────┐                    ┌─────────────────┐
│   Ethereum L1   │                    │   Set Chain L2  │
│                 │                    │                 │
│  StandardBridge │ ◄── Deposits ────► │  StandardBridge │
│  CrossDomainMsg │ ◄── Messages ────► │  CrossDomainMsg │
│  OptimismPortal │ ◄── Withdrawals ── │                 │
└─────────────────┘                    └─────────────────┘
```

## Contract Addresses

After L1 deployment, these addresses are set in `config/sepolia.env`:

| Contract | L1 Address | L2 Address |
|----------|------------|------------|
| StandardBridge | `$L1_STANDARD_BRIDGE_ADDRESS` | `0x4200000000000000000000000000000000000010` |
| CrossDomainMessenger | `$L1_CROSS_DOMAIN_MESSENGER_ADDRESS` | `0x4200000000000000000000000000000000000007` |
| OptimismPortal | `$OPTIMISM_PORTAL_ADDRESS` | N/A |

## Deposits (L1 → L2)

### Deposit ETH

```bash
# Using cast
cast send $L1_STANDARD_BRIDGE_ADDRESS \
  "depositETH(uint32,bytes)" 200000 "0x" \
  --value 0.1ether \
  --private-key $PRIVATE_KEY \
  --rpc-url $L1_RPC_URL
```

### Deposit ERC20

```bash
# 1. Approve bridge
cast send $TOKEN_ADDRESS \
  "approve(address,uint256)" $L1_STANDARD_BRIDGE_ADDRESS $AMOUNT \
  --private-key $PRIVATE_KEY \
  --rpc-url $L1_RPC_URL

# 2. Bridge tokens
cast send $L1_STANDARD_BRIDGE_ADDRESS \
  "depositERC20(address,address,uint256,uint32,bytes)" \
  $L1_TOKEN $L2_TOKEN $AMOUNT 200000 "0x" \
  --private-key $PRIVATE_KEY \
  --rpc-url $L1_RPC_URL
```

### Deposit Timeline

| Step | Time | Description |
|------|------|-------------|
| L1 Tx confirmed | ~15 sec | Transaction on Ethereum |
| L2 deposit relayed | ~2-5 min | Funds appear on L2 |

## Withdrawals (L2 → L1)

Withdrawals have a 7-day challenge period for security.

### Initiate Withdrawal

```bash
# On L2: Initiate withdrawal
cast send 0x4200000000000000000000000000000000000010 \
  "withdraw(address,uint256,uint32,bytes)" \
  0x0000000000000000000000000000000000000000 \
  $AMOUNT 200000 "0x" \
  --private-key $PRIVATE_KEY \
  --rpc-url $L2_RPC_URL
```

### Prove Withdrawal (after state root published)

```bash
# Using op SDK or custom script
# Wait for state root to be published to L1 (~1 hour on Sepolia)

cast send $OPTIMISM_PORTAL_ADDRESS \
  "proveWithdrawalTransaction(...)" \
  --private-key $PRIVATE_KEY \
  --rpc-url $L1_RPC_URL
```

### Finalize Withdrawal (after challenge period)

```bash
# After 7 days (or shorter on testnet)
cast send $OPTIMISM_PORTAL_ADDRESS \
  "finalizeWithdrawalTransaction(...)" \
  --private-key $PRIVATE_KEY \
  --rpc-url $L1_RPC_URL
```

### Withdrawal Timeline

| Step | Time | Description |
|------|------|-------------|
| L2 Tx confirmed | ~2 sec | Initiate on L2 |
| State root published | ~1 hour | L2 state posted to L1 |
| Prove withdrawal | ~15 sec | Submit proof to L1 |
| Challenge period | 7 days | Security window |
| Finalize | ~15 sec | Claim funds on L1 |

## Bridge UI Options

### 1. Superbridge (Recommended)

Deploy the Superbridge UI for a polished user experience:

```bash
# Clone and configure
git clone https://github.com/superbridgeapp/superbridge-app
cd superbridge-app

# Configure for Set Chain
cat > .env << EOF
NEXT_PUBLIC_L1_CHAIN_ID=11155111
NEXT_PUBLIC_L2_CHAIN_ID=84532001
NEXT_PUBLIC_L1_RPC_URL=$L1_RPC_URL
NEXT_PUBLIC_L2_RPC_URL=$L2_RPC_URL
EOF

# Run
npm install && npm run dev
```

### 2. OP Bridge SDK

For programmatic bridge interactions:

```typescript
import { createPublicClient, http } from 'viem'
import { sepolia } from 'viem/chains'
import { publicActionsL1, publicActionsL2 } from 'viem/op-stack'

const l1Client = createPublicClient({
  chain: sepolia,
  transport: http(process.env.L1_RPC_URL),
}).extend(publicActionsL1())

const l2Client = createPublicClient({
  chain: setChain,
  transport: http(process.env.L2_RPC_URL),
}).extend(publicActionsL2())

// Get deposit status
const status = await l1Client.getDepositStatus({
  l2Hash: '0x...',
})
```

### 3. Blockscout Bridge Widget

Enable in Blockscout frontend with:

```bash
NEXT_PUBLIC_ROLLUP_L2_WITHDRAWAL_URL=https://bridge.setchain.io
```

## Supported Assets

| Asset | L1 Address | L2 Address | Bridgeable |
|-------|------------|------------|------------|
| ETH | Native | Native | Yes |
| USDC | 0x... | 0x... | Pending |
| USDT | 0x... | 0x... | Pending |

## Onramp Options

### 1. Direct ETH Bridge
Users bridge ETH from Ethereum mainnet/Sepolia.

### 2. Fiat Onramps (Future)
- MoonPay integration
- Transak integration
- Coinbase Onramp

## Security Considerations

1. **Challenge Period**: 7-day withdrawal delay protects against invalid state roots
2. **Bridge Limits**: Consider implementing deposit/withdrawal limits
3. **Monitoring**: Track large deposits/withdrawals
4. **Upgrades**: Monitor OP Stack security advisories

## Bridge Scripts

```bash
# Check bridge balances
./scripts/check-bridge-balance.sh

# Monitor pending withdrawals
./scripts/monitor-withdrawals.sh
```

## Monitoring

### Metrics to Track

- Deposit volume (daily/weekly)
- Withdrawal volume
- Average deposit confirmation time
- Pending withdrawals count
- Bridge TVL

### Alerts

- Large single deposit (> 100 ETH)
- Unusual deposit pattern
- Bridge contract upgrade detected
- Withdrawal proving failures

## Troubleshooting

### Deposit not appearing on L2

1. Check L1 transaction was successful
2. Wait 5-10 minutes for sequencer to include
3. Verify deposit event was emitted
4. Check sequencer is syncing properly

### Withdrawal stuck at "prove" step

1. Ensure state root is published to L1
2. Verify you're using correct withdrawal proof
3. Check L1 gas price isn't too high

## Evidence

Record in `docs/operations-history.md`:
- Bridge deployment date
- Contract addresses
- Supported assets
- Bridge UI URL
- Any incidents
