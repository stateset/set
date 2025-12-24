# Monitoring Guide

Monitor Set Chain contracts and system health.

## Key Metrics

### System Health

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| NAV Staleness | Time since last NAV update | > 12 hours |
| Total TVL | Total value locked in ssUSD | Sudden drop > 10% |
| Collateral Utilization | Current deposits vs caps | > 90% |
| Pending Redemptions | Queued redemption value | > 5% TVL |
| Gas Prices | L2 gas costs | > 10x baseline |

### Contract Health

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| Batch Submission Rate | Batches per hour | < 1/hour |
| Failed Transactions | Reverted tx rate | > 1% |
| Upgrade Proposals | Pending timelocked operations | Any new |
| Admin Actions | Role changes, pauses | Any |

## Monitoring Setup

### Event Listeners

```typescript
import { Contract, JsonRpcProvider, WebSocketProvider } from "ethers";

// Use WebSocket for real-time events
const wsProvider = new WebSocketProvider("wss://ws.testnet.setchain.io");

// NAV Oracle monitoring
const navOracle = new Contract(NAV_ORACLE_ADDRESS, NAVOracleABI, wsProvider);

navOracle.on("NAVUpdated", (reportId, nav, totalAssets, totalShares, timestamp) => {
    console.log(`NAV Updated: $${formatUnits(nav, 18)}`);
    console.log(`Total Assets: $${formatUnits(totalAssets, 18)}`);
    console.log(`Report ID: ${reportId}`);

    // Send to monitoring system
    metrics.gauge("nav.value", Number(formatUnits(nav, 18)));
    metrics.gauge("nav.total_assets", Number(formatUnits(totalAssets, 18)));
});

// Treasury monitoring
const treasury = new Contract(TREASURY_ADDRESS, TreasuryVaultABI, wsProvider);

treasury.on("Deposit", (user, token, amount, ssUSDMinted) => {
    console.log(`Deposit: ${formatUnits(amount, 6)} ${token}`);
    metrics.increment("treasury.deposits");
    metrics.gauge("treasury.deposit_amount", Number(formatUnits(amount, 6)));
});

treasury.on("Redemption", (user, token, ssUSDBurned, amountRedeemed) => {
    console.log(`Redemption: ${formatUnits(ssUSDBurned, 18)} ssUSD`);
    metrics.increment("treasury.redemptions");
    metrics.gauge("treasury.redemption_amount", Number(formatUnits(ssUSDBurned, 18)));
});

treasury.on("DepositsPaused", (by) => {
    console.error(`ALERT: Deposits paused by ${by}`);
    alerting.critical("Deposits Paused", { pausedBy: by });
});

treasury.on("RedemptionsPaused", (by) => {
    console.error(`ALERT: Redemptions paused by ${by}`);
    alerting.critical("Redemptions Paused", { pausedBy: by });
});

// Timelock monitoring
const timelock = new Contract(TIMELOCK_ADDRESS, SetTimelockABI, wsProvider);

timelock.on("OperationScheduled", (opId, target, value, data, delay, readyAt) => {
    console.log(`New operation scheduled: ${opId}`);
    console.log(`Target: ${target}`);
    console.log(`Ready at: ${new Date(Number(readyAt) * 1000)}`);

    alerting.warning("Timelock Operation Scheduled", {
        operationId: opId,
        target,
        readyAt: Number(readyAt)
    });
});
```

### Health Check Endpoint

```typescript
import express from "express";
import { Contract, JsonRpcProvider } from "ethers";

const app = express();
const provider = new JsonRpcProvider(L2_RPC_URL);

app.get("/health", async (req, res) => {
    try {
        const checks = await runHealthChecks();

        const healthy = checks.every(c => c.status === "ok");

        res.status(healthy ? 200 : 503).json({
            status: healthy ? "healthy" : "degraded",
            timestamp: new Date().toISOString(),
            checks
        });
    } catch (error) {
        res.status(500).json({
            status: "error",
            error: error.message
        });
    }
});

async function runHealthChecks() {
    const checks = [];

    // 1. RPC connectivity
    try {
        const blockNumber = await provider.getBlockNumber();
        checks.push({
            name: "rpc_connectivity",
            status: "ok",
            blockNumber
        });
    } catch (error) {
        checks.push({
            name: "rpc_connectivity",
            status: "error",
            error: error.message
        });
    }

    // 2. NAV staleness
    try {
        const navOracle = new Contract(NAV_ORACLE_ADDRESS, NAVOracleABI, provider);
        const isStale = await navOracle.isStale();
        const lastUpdate = await navOracle.lastUpdateTimestamp();

        checks.push({
            name: "nav_freshness",
            status: isStale ? "warning" : "ok",
            lastUpdate: Number(lastUpdate),
            isStale
        });
    } catch (error) {
        checks.push({
            name: "nav_freshness",
            status: "error",
            error: error.message
        });
    }

    // 3. Deposits/Redemptions status
    try {
        const treasury = new Contract(TREASURY_ADDRESS, TreasuryVaultABI, provider);
        const depositsPaused = await treasury.depositsPaused();
        const redemptionsPaused = await treasury.redemptionsPaused();

        checks.push({
            name: "treasury_status",
            status: (depositsPaused || redemptionsPaused) ? "warning" : "ok",
            depositsPaused,
            redemptionsPaused
        });
    } catch (error) {
        checks.push({
            name: "treasury_status",
            status: "error",
            error: error.message
        });
    }

    // 4. Collateral levels
    try {
        const treasury = new Contract(TREASURY_ADDRESS, TreasuryVaultABI, provider);
        const totalValue = await treasury.getTotalCollateralValue();
        const ssUSD = new Contract(SSUSD_ADDRESS, ssUSDABI, provider);
        const totalSupply = await ssUSD.totalSupply();

        const backingRatio = totalValue * 100n / totalSupply;

        checks.push({
            name: "collateral_backing",
            status: backingRatio >= 100n ? "ok" : "critical",
            totalValue: formatUnits(totalValue, 18),
            totalSupply: formatUnits(totalSupply, 18),
            backingRatio: Number(backingRatio)
        });
    } catch (error) {
        checks.push({
            name: "collateral_backing",
            status: "error",
            error: error.message
        });
    }

    return checks;
}

app.listen(3000, () => {
    console.log("Health check server on port 3000");
});
```

### Prometheus Metrics

```typescript
import { Registry, Gauge, Counter } from "prom-client";

const register = new Registry();

// NAV metrics
const navGauge = new Gauge({
    name: "setchain_nav_value",
    help: "Current NAV per share",
    registers: [register]
});

const navLastUpdate = new Gauge({
    name: "setchain_nav_last_update_timestamp",
    help: "Timestamp of last NAV update",
    registers: [register]
});

// TVL metrics
const tvlGauge = new Gauge({
    name: "setchain_tvl_usd",
    help: "Total value locked in USD",
    registers: [register]
});

const ssUSDSupply = new Gauge({
    name: "setchain_ssusd_total_supply",
    help: "Total ssUSD supply",
    registers: [register]
});

// Transaction counters
const depositsCounter = new Counter({
    name: "setchain_deposits_total",
    help: "Total number of deposits",
    registers: [register]
});

const redemptionsCounter = new Counter({
    name: "setchain_redemptions_total",
    help: "Total number of redemptions",
    registers: [register]
});

// Update metrics periodically
async function updateMetrics() {
    const navOracle = new Contract(NAV_ORACLE_ADDRESS, NAVOracleABI, provider);
    const treasury = new Contract(TREASURY_ADDRESS, TreasuryVaultABI, provider);
    const ssUSD = new Contract(SSUSD_ADDRESS, ssUSDABI, provider);

    const nav = await navOracle.currentNAV();
    const lastUpdate = await navOracle.lastUpdateTimestamp();
    const tvl = await treasury.getTotalCollateralValue();
    const supply = await ssUSD.totalSupply();

    navGauge.set(Number(formatUnits(nav, 18)));
    navLastUpdate.set(Number(lastUpdate));
    tvlGauge.set(Number(formatUnits(tvl, 18)));
    ssUSDSupply.set(Number(formatUnits(supply, 18)));
}

// Run every 30 seconds
setInterval(updateMetrics, 30000);
```

## Alerting Rules

### Critical Alerts

```yaml
# prometheus/alerts.yml
groups:
  - name: setchain_critical
    rules:
      - alert: NAVStale
        expr: time() - setchain_nav_last_update_timestamp > 43200  # 12 hours
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "NAV data is stale"
          description: "NAV has not been updated in {{ $value | humanizeDuration }}"

      - alert: CollateralUnderbacked
        expr: setchain_tvl_usd / setchain_ssusd_total_supply < 0.99
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "ssUSD is underbacked"
          description: "Backing ratio is {{ $value | printf \"%.2f\" }}"

      - alert: DepositsPaused
        expr: setchain_deposits_paused == 1
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "Deposits are paused"

      - alert: RedemptionsPaused
        expr: setchain_redemptions_paused == 1
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "Redemptions are paused"
```

### Warning Alerts

```yaml
  - name: setchain_warnings
    rules:
      - alert: HighCollateralUtilization
        expr: setchain_collateral_utilization > 90
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High collateral utilization"
          description: "{{ $labels.token }} utilization is {{ $value }}%"

      - alert: LargeRedemption
        expr: increase(setchain_redemptions_volume_usd[5m]) > 1000000
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "Large redemption activity"
          description: "${{ $value | humanize }} redeemed in 5 minutes"

      - alert: TimelockOperationPending
        expr: setchain_timelock_pending_operations > 0
        for: 1m
        labels:
          severity: info
        annotations:
          summary: "Timelock operation pending"
          description: "{{ $value }} operation(s) awaiting execution"
```

## Dashboard

### Grafana Dashboard JSON

```json
{
  "title": "Set Chain Monitoring",
  "panels": [
    {
      "title": "NAV Value",
      "type": "stat",
      "targets": [
        {
          "expr": "setchain_nav_value",
          "legendFormat": "NAV"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "unit": "currencyUSD",
          "decimals": 6
        }
      }
    },
    {
      "title": "Total Value Locked",
      "type": "stat",
      "targets": [
        {
          "expr": "setchain_tvl_usd",
          "legendFormat": "TVL"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "unit": "currencyUSD"
        }
      }
    },
    {
      "title": "ssUSD Supply Over Time",
      "type": "graph",
      "targets": [
        {
          "expr": "setchain_ssusd_total_supply",
          "legendFormat": "Supply"
        }
      ]
    },
    {
      "title": "Deposit/Redemption Rate",
      "type": "graph",
      "targets": [
        {
          "expr": "rate(setchain_deposits_total[5m])",
          "legendFormat": "Deposits"
        },
        {
          "expr": "rate(setchain_redemptions_total[5m])",
          "legendFormat": "Redemptions"
        }
      ]
    }
  ]
}
```

## Log Aggregation

### Structured Logging

```typescript
import pino from "pino";

const logger = pino({
    level: "info",
    formatters: {
        level: (label) => ({ level: label })
    }
});

// Log events with structured data
navOracle.on("NAVUpdated", (reportId, nav, totalAssets, totalShares, timestamp) => {
    logger.info({
        event: "nav_updated",
        reportId: reportId.toString(),
        nav: formatUnits(nav, 18),
        totalAssets: formatUnits(totalAssets, 18),
        totalShares: totalShares.toString(),
        timestamp: Number(timestamp)
    }, "NAV updated");
});

treasury.on("Deposit", (user, token, amount, ssUSDMinted) => {
    logger.info({
        event: "deposit",
        user,
        token,
        amount: formatUnits(amount, 6),
        ssUSDMinted: formatUnits(ssUSDMinted, 18)
    }, "Deposit processed");
});
```

## Incident Response

### Runbook: NAV Stale

1. Check NAV Oracle attestor status
2. Verify attestor has ETH for gas
3. Check if attestor service is running
4. If attestor healthy, check NAVOracle contract
5. Consider emergency NAV update if critical

### Runbook: Deposits Paused

1. Check pause event for context
2. Verify if planned maintenance
3. If unplanned, investigate cause
4. Notify users via status page
5. Coordinate unpause when safe

## Related

- [Deployment Guide](./deployment.md)
- [Security Operations](./security.md)
- [Runbook](./runbook.md)
