# Fault Proof Exercise Log

This document records fault proof exercises conducted on Set Chain to validate
the dispute resolution mechanism.

## Prerequisites

Before running a fault proof exercise:

1. **Deploy OP Stack with Fault Proofs enabled**
   ```bash
   # Ensure these contracts are deployed on L1:
   # - DisputeGameFactory
   # - AnchorStateRegistry
   # - MIPS (for Cannon)
   ```

2. **Configure op-challenger**
   ```bash
   docker compose -f docker/docker-compose.yml --profile challenger up
   ```

3. **Have test ETH on L1** for dispute bonds

## Running an Exercise

Use the fault proof exercise script:

```bash
# Check prerequisites
./scripts/fault-proof-exercise.sh check

# View current L2 state
./scripts/fault-proof-exercise.sh state

# List active disputes
./scripts/fault-proof-exercise.sh list

# Run full exercise walkthrough
./scripts/fault-proof-exercise.sh exercise

# Generate report template
./scripts/fault-proof-exercise.sh report
```

---

## Exercise Log

### Exercise 1: [DATE]

**Environment:**
- Date:
- L1 RPC:
- L2 RPC:
- Challenger version:
- Network: Sepolia

**Dispute Game Details:**
- Game Address:
- Game Type: CANNON (0)
- Root Claim:
- Created At:
- Resolved At:
- Outcome: Challenger Wins / Defender Wins

**Steps Performed:**
1. [ ] Verified op-challenger was running and connected
2. [ ] Submitted fraudulent L2 output to L2OutputOracle
3. [ ] Observed op-challenger detect the bad output
4. [ ] Monitored dispute game progress
5. [ ] Verified honest state prevailed after resolution

**Observations:**
- Time to detect:
- Time to resolve:
- Gas costs:
- Any issues:

**Evidence:**
- L1 Tx (bad output):
- L1 Tx (dispute created):
- L1 Tx (dispute resolved):
- Logs: `reports/fault-proof-exercise-YYYYMMDD.log`
- Screenshots: `reports/screenshots/`

**Lessons Learned:**
-

---

## Checklist for Production Readiness

- [ ] Successfully run fault proof exercise on Sepolia
- [ ] Documented all dispute game addresses and outcomes
- [ ] Verified challenger can detect and dispute bad outputs
- [ ] Tested with multiple dispute scenarios
- [ ] Confirmed bond economics are appropriate
- [ ] Trained operations team on dispute monitoring
- [ ] Set up alerting for dispute games
- [ ] Documented recovery procedures

## References

- [OP Stack Fault Proofs](https://docs.optimism.io/stack/fault-proofs/overview)
- [Cannon FPVM](https://docs.optimism.io/stack/fault-proofs/cannon)
- [Dispute Game Interface](https://github.com/ethereum-optimism/optimism/tree/develop/packages/contracts-bedrock/src/dispute)
