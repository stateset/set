# Operations Runbook

Procedures for common operational scenarios.

## Quick Reference

| Scenario | Severity | Time to Resolve | Page |
|----------|----------|-----------------|------|
| NAV Oracle Stale | P2 | < 1 hour | [Link](#nav-oracle-stale) |
| Deposits Paused | P1 | < 30 min | [Link](#deposits-paused) |
| Sequencer Down | P0 | Immediate | [Link](#sequencer-down) |
| High Gas Prices | P3 | Monitor | [Link](#high-gas-prices) |
| Contract Upgrade | P3 | 48+ hours | [Link](#contract-upgrade) |
| Security Incident | P0 | Immediate | [Link](#security-incident) |

## NAV Oracle Stale

### Symptoms
- NAV hasn't updated in >12 hours
- Deposits failing with "StaleNAV" error
- Dashboard showing stale warning

### Investigation

```bash
# Check last NAV update
cast call $NAV_ORACLE "lastUpdateTimestamp()" --rpc-url $RPC_URL

# Check if stale
cast call $NAV_ORACLE "isStale()" --rpc-url $RPC_URL

# Get latest report
cast call $NAV_ORACLE "getLatestReport()" --rpc-url $RPC_URL
```

### Resolution

1. **Check Attestor Status**
   ```bash
   # Check attestor balance (for gas)
   cast balance $ATTESTOR_ADDRESS --rpc-url $RPC_URL

   # Check attestor service health
   curl https://attestor.setchain.io/health
   ```

2. **If Attestor Service Down**
   - Restart attestor service
   - Check logs for errors
   - Verify T-Bill data feed

3. **If Attestor Out of Gas**
   ```bash
   # Send ETH to attestor
   cast send $ATTESTOR_ADDRESS --value 0.1ether --private-key $ADMIN_KEY
   ```

4. **Emergency NAV Update** (requires guardians)
   ```bash
   # Only if attestor cannot be recovered
   # Requires 3-of-5 guardian signatures
   ./scripts/emergency-nav-update.sh
   ```

### Post-Resolution
- Verify NAV updated
- Check deposits working
- Monitor for recurrence

---

## Deposits Paused

### Symptoms
- Users cannot deposit
- Error: "DepositsPaused"
- Dashboard shows paused status

### Investigation

```bash
# Check pause status
cast call $TREASURY "depositsPaused()" --rpc-url $RPC_URL

# Find pause event
cast logs $TREASURY "DepositsPaused(address)" --from-block -1000 --rpc-url $RPC_URL
```

### Resolution

1. **If Planned Maintenance**
   - Verify maintenance is complete
   - Unpause when ready

2. **If Unplanned**
   - Investigate why paused
   - Check recent transactions
   - Review system health

3. **Unpause Deposits**
   ```bash
   # Via admin multisig
   cast send $TREASURY "unpauseDeposits()" \
     --private-key $PAUSER_KEY \
     --rpc-url $RPC_URL
   ```

### Post-Resolution
- Verify deposits working
- Notify users via status page
- Document incident

---

## Sequencer Down

### Symptoms
- No new L2 blocks
- Transactions not confirming
- RPC endpoints returning errors

### Immediate Actions

1. **Notify Team**
   ```bash
   ./scripts/alert-team.sh "CRITICAL: Sequencer Down"
   ```

2. **Check Sequencer Status**
   ```bash
   # Check sequencer health
   curl https://sequencer.setchain.io/health

   # Check latest block
   cast block-number --rpc-url $RPC_URL
   ```

3. **Enable Forced Inclusion** (inform users)
   - Update status page: "Use forced inclusion via L1"
   - Post announcement with instructions

### Resolution

1. **Restart Sequencer**
   ```bash
   ssh sequencer.setchain.io
   sudo systemctl restart op-node
   sudo systemctl restart op-geth
   ```

2. **Verify Recovery**
   ```bash
   # Monitor block production
   watch -n 2 "cast block-number --rpc-url $RPC_URL"
   ```

3. **Process Pending Forced Inclusions**
   - Check for forced transactions
   - Ensure they're included

### Post-Resolution
- Update status page
- Review logs for root cause
- Document in incident report

---

## High Gas Prices

### Symptoms
- Unusually high gas costs
- Users complaining about fees
- Potential spam attack

### Investigation

```bash
# Check current gas price
cast gas-price --rpc-url $RPC_URL

# Check pending transactions
cast pending-count --rpc-url $RPC_URL

# Check block gas usage
cast block latest --field gasUsed --rpc-url $RPC_URL
```

### Resolution

1. **If Spam Attack**
   - Identify spammer addresses
   - Consider rate limiting at RPC level
   - Monitor mempool

2. **If Legitimate High Demand**
   - No action needed
   - Consider increasing gas limit (via governance)

3. **Notify Users**
   - Update status page
   - Recommend waiting if possible

### Monitoring
- Track gas prices over time
- Set up alerts for sustained high prices

---

## Contract Upgrade

### Pre-Upgrade Checklist

- [ ] New implementation audited
- [ ] Tests passing
- [ ] Testnet deployment tested
- [ ] Team notified
- [ ] Community notified (48h+ notice)
- [ ] Rollback plan ready

### Upgrade Procedure

1. **Deploy New Implementation**
   ```bash
   forge script scripts/UpgradeRegistry.s.sol:DeployNewImpl \
     --rpc-url $RPC_URL \
     --broadcast \
     --verify
   ```

2. **Schedule Upgrade**
   ```bash
   # Via admin multisig
   cast send $TIMELOCK "schedule(address,uint256,bytes,uint8)" \
     $REGISTRY_PROXY \
     0 \
     $(cast calldata "upgradeToAndCall(address,bytes)" $NEW_IMPL "0x") \
     0 \
     --private-key $ADMIN_KEY
   ```

3. **Wait for Timelock** (48 hours)
   - Monitor for community feedback
   - Be ready to cancel if issues found

4. **Execute Upgrade**
   ```bash
   cast send $TIMELOCK "execute(bytes32)" $OPERATION_ID \
     --private-key $EXECUTOR_KEY
   ```

5. **Verify Upgrade**
   ```bash
   # Check implementation
   cast storage $REGISTRY_PROXY 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc --rpc-url $RPC_URL
   ```

### Rollback Procedure

If issues discovered after upgrade:

1. **Pause Affected Functions**
   ```bash
   cast send $REGISTRY "pause()" --private-key $ADMIN_KEY
   ```

2. **Schedule Rollback**
   ```bash
   # Deploy previous implementation or fix
   # Schedule via timelock
   ```

3. **Execute Rollback** (after timelock)

---

## Security Incident

### Immediate Response (< 5 minutes)

1. **Assess Severity**
   - Active exploit?
   - Funds at risk?
   - Vulnerability known?

2. **Emergency Pause** (if funds at risk)
   ```bash
   ./scripts/emergency-pause.sh
   ```

3. **Alert Team**
   ```bash
   ./scripts/alert-security.sh "CRITICAL: Security Incident"
   ```

### Investigation

1. **Collect Evidence**
   ```bash
   # Save transaction logs
   ./scripts/export-recent-txs.sh > incident-txs.json

   # Save contract state
   ./scripts/export-state.sh > incident-state.json
   ```

2. **Identify Attack Vector**
   - Review transactions
   - Check for unusual patterns
   - Analyze exploiter addresses

3. **Assess Damage**
   - Calculate funds affected
   - Identify affected users
   - Determine scope

### Containment

1. **Prevent Further Damage**
   - Pause relevant functions
   - Blocklist exploiter addresses (if applicable)
   - Disable affected features

2. **Communicate**
   - Update status page
   - Post brief incident notice
   - Do NOT disclose vulnerability details

### Recovery

1. **Develop Fix**
   - Code review by 2+ engineers
   - Test on fork
   - Prepare deployment

2. **Emergency Upgrade** (if needed)
   ```bash
   # Requires guardian signatures
   ./scripts/emergency-upgrade.sh $NEW_IMPL
   ```

3. **User Recovery** (if funds lost)
   - Document affected users
   - Develop compensation plan
   - Execute recovery

### Post-Incident

1. **Write Post-Mortem**
   - Timeline
   - Root cause
   - Impact
   - Actions taken
   - Preventive measures

2. **Publish Disclosure** (after fix deployed)
   - Responsible disclosure timeline
   - Technical details (redacted if needed)
   - User guidance

---

## Common Commands

### Check System Health

```bash
# All-in-one health check
./scripts/health-check.sh

# Individual checks
cast call $NAV_ORACLE "isStale()" --rpc-url $RPC_URL
cast call $TREASURY "depositsPaused()" --rpc-url $RPC_URL
cast call $TREASURY "redemptionsPaused()" --rpc-url $RPC_URL
cast call $TREASURY "getTotalCollateralValue()" --rpc-url $RPC_URL
```

### Check User Balances

```bash
# ssUSD balance
cast call $SSUSD "balanceOf(address)" $USER_ADDRESS --rpc-url $RPC_URL

# ssUSD shares
cast call $SSUSD "sharesOf(address)" $USER_ADDRESS --rpc-url $RPC_URL

# wssUSD balance
cast call $WSSUSD "balanceOf(address)" $USER_ADDRESS --rpc-url $RPC_URL
```

### Emergency Contacts

| Role | Contact | When to Contact |
|------|---------|-----------------|
| On-Call Engineer | Slack #on-call | Any P0/P1 |
| Security Lead | security@setchain.io | Security incidents |
| Guardian Committee | Signal group | Emergency actions |
| Community Manager | Slack #community | User communications |

---

## Maintenance Windows

### Scheduled Maintenance

1. **Announce 48h+ in advance**
   - Status page
   - Twitter
   - Discord

2. **Pre-Maintenance**
   - Pause deposits (if needed)
   - Alert users of downtime

3. **During Maintenance**
   - Update status page
   - Monitor progress

4. **Post-Maintenance**
   - Verify all systems
   - Unpause
   - Announce completion

### Expected Maintenance Schedule

| Task | Frequency | Duration |
|------|-----------|----------|
| Software updates | Monthly | 15-30 min |
| Infrastructure | Quarterly | 1-2 hours |
| Key rotation | Quarterly | 30 min |
| Security patches | As needed | Varies |

## Related

- [Security Operations](./security.md)
- [Monitoring Guide](./monitoring.md)
- [Deployment Guide](./deployment.md)
