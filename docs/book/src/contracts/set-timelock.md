# SetTimelock

The governance timelock contract enforcing delays on administrative actions and upgrades.

## Overview

SetTimelock provides time-delayed execution for sensitive operations:

- Contract upgrades require 48-hour delay
- Parameter changes require 24-hour delay
- Emergency actions can bypass delays (with multi-sig)
- All pending operations are publicly visible

## Contract Interface

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISetTimelock {
    // Events
    event OperationScheduled(
        bytes32 indexed operationId,
        address indexed target,
        uint256 value,
        bytes data,
        uint256 delay,
        uint256 readyTimestamp
    );
    event OperationExecuted(bytes32 indexed operationId);
    event OperationCancelled(bytes32 indexed operationId);
    event DelayUpdated(OperationType opType, uint256 oldDelay, uint256 newDelay);
    event GuardianUpdated(address oldGuardian, address newGuardian);

    // Enums
    enum OperationType {
        UPGRADE,        // Contract upgrades (48h)
        PARAMETER,      // Parameter changes (24h)
        ROLE,           // Role changes (24h)
        EMERGENCY       // Emergency actions (0h with guardian)
    }

    enum OperationState {
        UNSET,
        PENDING,
        READY,
        EXECUTED,
        CANCELLED
    }

    // Schedule Operations
    function schedule(
        address target,
        uint256 value,
        bytes calldata data,
        OperationType opType
    ) external returns (bytes32 operationId);

    function scheduleBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas,
        OperationType opType
    ) external returns (bytes32 operationId);

    // Execute Operations
    function execute(bytes32 operationId) external payable;
    function executeBatch(bytes32 operationId) external payable;

    // Cancel Operations
    function cancel(bytes32 operationId) external;

    // Emergency
    function emergencyExecute(
        address target,
        uint256 value,
        bytes calldata data,
        bytes[] calldata signatures
    ) external payable;

    // Queries
    function getOperation(bytes32 operationId) external view returns (Operation memory);
    function getOperationState(bytes32 operationId) external view returns (OperationState);
    function isOperationReady(bytes32 operationId) external view returns (bool);
    function getDelay(OperationType opType) external view returns (uint256);
    function getPendingOperations() external view returns (bytes32[] memory);

    // Admin
    function setDelay(OperationType opType, uint256 newDelay) external;
    function setGuardian(address newGuardian) external;
}

struct Operation {
    address target;
    uint256 value;
    bytes data;
    OperationType opType;
    uint256 scheduledAt;
    uint256 readyAt;
    OperationState state;
    address proposer;
}
```

## Default Delays

| Operation Type | Default Delay | Minimum | Maximum |
|---------------|---------------|---------|---------|
| UPGRADE | 48 hours | 24 hours | 7 days |
| PARAMETER | 24 hours | 12 hours | 7 days |
| ROLE | 24 hours | 12 hours | 7 days |
| EMERGENCY | 0 (multi-sig) | 0 | 0 |

## Functions

### schedule

Schedule an operation for delayed execution.

```solidity
function schedule(
    address target,
    uint256 value,
    bytes calldata data,
    OperationType opType
) external returns (bytes32 operationId);
```

**Parameters:**
- `target`: Contract to call
- `value`: ETH to send
- `data`: Encoded function call
- `opType`: Type of operation (determines delay)

**Returns:** Operation ID (keccak256 hash)

**Requirements:**
- Caller must have PROPOSER_ROLE
- Operation must not already exist

**Example:**
```typescript
// Schedule a parameter update
const calldata = registry.interface.encodeFunctionData(
    "setMaxBatchSize",
    [2000]
);

const tx = await timelock.schedule(
    registryAddress,
    0n,
    calldata,
    1 // OperationType.PARAMETER
);

const receipt = await tx.wait();
const operationId = receipt.logs[0].args.operationId;
console.log(`Scheduled: ${operationId}`);
console.log(`Ready in 24 hours`);
```

### scheduleBatch

Schedule multiple operations as an atomic batch.

```solidity
function scheduleBatch(
    address[] calldata targets,
    uint256[] calldata values,
    bytes[] calldata datas,
    OperationType opType
) external returns (bytes32 operationId);
```

**Example:**
```typescript
// Schedule multiple parameter updates
const targets = [registryAddress, registryAddress];
const values = [0n, 0n];
const datas = [
    registry.interface.encodeFunctionData("setMaxBatchSize", [2000]),
    registry.interface.encodeFunctionData("setStrictMode", [true])
];

const tx = await timelock.scheduleBatch(targets, values, datas, 1);
```

### execute

Execute a ready operation.

```solidity
function execute(bytes32 operationId) external payable;
```

**Parameters:**
- `operationId`: ID of the operation to execute

**Requirements:**
- Caller must have EXECUTOR_ROLE
- Operation must be in READY state
- Current time >= readyAt timestamp

**Example:**
```typescript
// Check if ready
const isReady = await timelock.isOperationReady(operationId);

if (isReady) {
    const tx = await timelock.execute(operationId);
    await tx.wait();
    console.log("Operation executed");
}
```

### cancel

Cancel a pending operation.

```solidity
function cancel(bytes32 operationId) external;
```

**Parameters:**
- `operationId`: ID of the operation to cancel

**Requirements:**
- Caller must have CANCELLER_ROLE
- Operation must be in PENDING or READY state

**Example:**
```typescript
// Cancel if vulnerability found
const tx = await timelock.cancel(operationId);
await tx.wait();
console.log("Operation cancelled");
```

### emergencyExecute

Execute immediately with guardian multi-sig approval.

```solidity
function emergencyExecute(
    address target,
    uint256 value,
    bytes calldata data,
    bytes[] calldata signatures
) external payable;
```

**Parameters:**
- `target`: Contract to call
- `value`: ETH to send
- `data`: Encoded function call
- `signatures`: Guardian multi-sig signatures

**Requirements:**
- Signatures from threshold of guardians
- Only for critical security responses

**Example:**
```typescript
// Emergency pause (requires guardian signatures)
const pauseData = treasury.interface.encodeFunctionData("pause", []);

// Collect signatures from guardians
const signatures = await collectGuardianSignatures(
    treasuryAddress,
    0n,
    pauseData
);

const tx = await timelock.emergencyExecute(
    treasuryAddress,
    0n,
    pauseData,
    signatures
);
await tx.wait();
console.log("Emergency pause executed");
```

### getOperation

Get operation details.

```solidity
function getOperation(bytes32 operationId) external view returns (Operation memory);
```

**Returns:** Operation struct with full details

**Example:**
```typescript
const op = await timelock.getOperation(operationId);

console.log("Target:", op.target);
console.log("Scheduled:", new Date(Number(op.scheduledAt) * 1000));
console.log("Ready:", new Date(Number(op.readyAt) * 1000));
console.log("State:", ["Unset", "Pending", "Ready", "Executed", "Cancelled"][op.state]);
```

### getPendingOperations

Get all pending operation IDs.

```solidity
function getPendingOperations() external view returns (bytes32[] memory);
```

**Returns:** Array of pending operation IDs

**Example:**
```typescript
const pending = await timelock.getPendingOperations();

for (const opId of pending) {
    const op = await timelock.getOperation(opId);
    console.log(`${opId}: ${op.target} - ready at ${op.readyAt}`);
}
```

## Roles

| Role | Permissions |
|------|-------------|
| `PROPOSER_ROLE` | Schedule operations |
| `EXECUTOR_ROLE` | Execute ready operations |
| `CANCELLER_ROLE` | Cancel pending operations |
| `ADMIN_ROLE` | Update delays, manage roles |
| `GUARDIAN_ROLE` | Emergency execution |

## Governance Flow

### Standard Upgrade

```
Day 0: Propose upgrade
        │
        ▼
┌─────────────────────┐
│ schedule(           │
│   impl,             │
│   0,                │
│   upgradeCall,      │
│   UPGRADE           │
│ )                   │
└─────────┬───────────┘
          │
          ▼
    48-hour delay
    (publicly visible)
          │
          ▼
┌─────────────────────┐
│ Community review    │
│ Security analysis   │
│ Cancel if issues    │
└─────────┬───────────┘
          │
          ▼
Day 2: Execute upgrade
        │
        ▼
┌─────────────────────┐
│ execute(operationId)│
└─────────────────────┘
```

### Emergency Response

```
Security incident detected
          │
          ▼
┌─────────────────────┐
│ Guardian committee  │
│ reviews and signs   │
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│ emergencyExecute(   │
│   target,           │
│   0,                │
│   pauseCall,        │
│   guardianSigs      │
│ )                   │
└─────────┬───────────┘
          │
          ▼
    Immediate execution
```

## Monitoring Pending Operations

### On-Chain Monitoring

```typescript
import { Contract } from "ethers";
import { SetTimelockABI } from "@setchain/sdk";

const timelock = new Contract(TIMELOCK_ADDRESS, SetTimelockABI, provider);

// Listen for scheduled operations
timelock.on("OperationScheduled", (opId, target, value, data, delay, readyAt) => {
    console.log(`New operation scheduled: ${opId}`);
    console.log(`Target: ${target}`);
    console.log(`Ready at: ${new Date(Number(readyAt) * 1000)}`);

    // Decode the call
    const iface = new Interface(targetABI);
    const decoded = iface.parseTransaction({ data });
    console.log(`Function: ${decoded.name}`);
    console.log(`Args: ${decoded.args}`);
});

// Monitor executions
timelock.on("OperationExecuted", (opId) => {
    console.log(`Operation executed: ${opId}`);
});

// Monitor cancellations
timelock.on("OperationCancelled", (opId) => {
    console.log(`Operation cancelled: ${opId}`);
});
```

### Dashboard Query

```typescript
async function getGovernanceStatus() {
    const pending = await timelock.getPendingOperations();

    const operations = await Promise.all(
        pending.map(async (opId) => {
            const op = await timelock.getOperation(opId);
            const isReady = await timelock.isOperationReady(opId);

            return {
                id: opId,
                target: op.target,
                type: ["Upgrade", "Parameter", "Role", "Emergency"][op.opType],
                scheduledAt: new Date(Number(op.scheduledAt) * 1000),
                readyAt: new Date(Number(op.readyAt) * 1000),
                isReady,
                proposer: op.proposer
            };
        })
    );

    return operations;
}
```

## Security Considerations

### Delay Minimums

Delays cannot be reduced below minimums:
- Upgrades: 24 hours minimum
- Parameters: 12 hours minimum

This ensures sufficient time for community review.

### Guardian Multi-Sig

Emergency execution requires:
- 3-of-5 guardian signatures
- Only for security incidents
- All emergency actions are logged

### Operation Visibility

All pending operations are publicly queryable, enabling:
- Community monitoring
- Security researcher review
- Automated alerting systems

## Error Codes

| Error | Description |
|-------|-------------|
| `OperationAlreadyScheduled()` | Operation ID already exists |
| `OperationNotFound()` | Operation ID doesn't exist |
| `OperationNotReady()` | Delay period not elapsed |
| `OperationAlreadyExecuted()` | Operation already executed |
| `OperationCancelled()` | Operation was cancelled |
| `InvalidSignatures()` | Guardian signatures invalid |
| `DelayTooShort()` | Delay below minimum |
| `DelayTooLong()` | Delay above maximum |
| `Unauthorized()` | Caller lacks required role |

## Related

- [SetRegistry](./set-registry.md) - Core registry contract
- [SetPaymaster](./set-paymaster.md) - Gas sponsorship
- [Security Operations](../operations/security.md) - Security procedures
