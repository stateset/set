# Error Codes Reference

Complete reference of error codes returned by Set Chain contracts and SDK.

## Contract Errors

### SetRegistry Errors

| Error | Signature | Description |
|-------|-----------|-------------|
| `UnauthorizedSubmitter` | `0x...` | Caller not authorized to submit for tenant |
| `TenantNotFound` | `0x...` | Tenant ID doesn't exist |
| `StoreNotFound` | `0x...` | Store ID doesn't exist |
| `InvalidMerkleRoot` | `0x...` | Merkle root is zero |
| `InvalidSequence` | `0x...` | Sequence numbers invalid |
| `SequenceGap` | `0x...` | Gap in sequence numbers (strict mode) |
| `StateRootMismatch` | `0x...` | Previous state root doesn't match |
| `BatchSizeTooLarge` | `0x...` | Exceeds max batch size |
| `InvalidProof` | `0x...` | Merkle proof verification failed |

```solidity
// Error definitions
error UnauthorizedSubmitter(address submitter, bytes32 tenantId);
error TenantNotFound(bytes32 tenantId);
error StoreNotFound(bytes32 tenantId, bytes32 storeId);
error InvalidMerkleRoot();
error InvalidSequence(uint64 expected, uint64 actual);
error SequenceGap(uint64 headSequence, uint64 startSequence);
error StateRootMismatch(bytes32 expected, bytes32 actual);
error BatchSizeTooLarge(uint32 size, uint32 maxSize);
error InvalidProof();
```

### SetPaymaster Errors

| Error | Description |
|-------|-------------|
| `NotRegistered` | Caller not a registered merchant |
| `AlreadyRegistered` | Merchant already registered |
| `InsufficientDeposit` | Deposit below minimum requirement |
| `InsufficientBalance` | Not enough balance for operation |
| `PolicyViolation` | Transaction violates policy |
| `DailyLimitExceeded` | User or total daily limit reached |
| `InvalidTarget` | Target contract not whitelisted |
| `InvalidSelector` | Function selector not whitelisted |

```solidity
error NotRegistered(address merchant);
error AlreadyRegistered(address merchant);
error InsufficientDeposit(uint256 provided, uint256 required);
error InsufficientBalance(uint256 requested, uint256 available);
error PolicyViolation(string reason);
error DailyLimitExceeded(address user, uint256 used, uint256 limit);
error InvalidTarget(address target);
error InvalidSelector(bytes4 selector);
```

### SetTimelock Errors

| Error | Description |
|-------|-------------|
| `OperationAlreadyScheduled` | Operation ID already exists |
| `OperationNotFound` | Operation ID doesn't exist |
| `OperationNotReady` | Delay period not elapsed |
| `OperationAlreadyExecuted` | Operation was already executed |
| `OperationCancelled` | Operation was cancelled |
| `InvalidSignatures` | Guardian signatures invalid |
| `DelayTooShort` | Delay below minimum |
| `DelayTooLong` | Delay above maximum |
| `Unauthorized` | Caller lacks required role |

```solidity
error OperationAlreadyScheduled(bytes32 operationId);
error OperationNotFound(bytes32 operationId);
error OperationNotReady(bytes32 operationId, uint256 readyAt);
error OperationAlreadyExecuted(bytes32 operationId);
error OperationCancelled(bytes32 operationId);
error InvalidSignatures(uint256 provided, uint256 required);
error DelayTooShort(uint256 provided, uint256 minimum);
error DelayTooLong(uint256 provided, uint256 maximum);
error Unauthorized(address caller, bytes32 role);
```

### Stablecoin System Errors

#### TokenRegistry

| Error | Description |
|-------|-------------|
| `TokenNotRegistered` | Token not in approved list |
| `TokenAlreadyRegistered` | Token already exists |
| `DepositCapExceeded` | Would exceed deposit cap |
| `DepositsDisabled` | Deposits disabled for token |
| `RedemptionsDisabled` | Redemptions disabled for token |

```solidity
error TokenNotRegistered(address token);
error TokenAlreadyRegistered(address token);
error DepositCapExceeded(address token, uint256 current, uint256 cap);
error DepositsDisabled(address token);
error RedemptionsDisabled(address token);
```

#### NAVOracle

| Error | Description |
|-------|-------------|
| `StaleNAV` | NAV data too old |
| `InvalidSignature` | Attestor signature invalid |
| `InvalidReportId` | Report ID not sequential |
| `ReportTooOld` | Report timestamp older than current |
| `NAVChangeTooLarge` | NAV change exceeds limit |

```solidity
error StaleNAV(uint256 lastUpdate, uint256 threshold);
error InvalidSignature(address recovered, address expected);
error InvalidReportId(uint256 provided, uint256 expected);
error ReportTooOld(uint256 reportTime, uint256 lastTime);
error NAVChangeTooLarge(uint256 oldNAV, uint256 newNAV, uint256 maxChange);
```

#### ssUSD

| Error | Description |
|-------|-------------|
| `OnlyTreasury` | Only treasury can mint/burn |
| `ZeroShares` | Cannot mint/burn zero shares |
| `TransferToZero` | Cannot transfer to zero address |

```solidity
error OnlyTreasury(address caller, address treasury);
error ZeroShares();
error TransferToZero();
```

#### TreasuryVault

| Error | Description |
|-------|-------------|
| `DepositsPaused` | Deposits are currently paused |
| `RedemptionsPaused` | Redemptions are currently paused |
| `SlippageExceeded` | Output below minimum |
| `InsufficientCollateral` | Not enough collateral to redeem |
| `ZeroAmount` | Cannot deposit/redeem zero |

```solidity
error DepositsPaused();
error RedemptionsPaused();
error SlippageExceeded(uint256 expected, uint256 actual, uint256 minimum);
error InsufficientCollateral(address token, uint256 requested, uint256 available);
error ZeroAmount();
```

### MEV Protection Errors

#### EncryptedMempool

| Error | Description |
|-------|-------------|
| `InvalidEncryption` | Payload not properly encrypted |
| `NotOrdered` | Transaction not yet ordered |
| `AlreadyDecrypted` | Transaction already decrypted |
| `AlreadyExecuted` | Transaction already executed |
| `ExecutionExpired` | Execution window passed |
| `InsufficientValue` | msg.value doesn't cover gas |

```solidity
error InvalidEncryption();
error NotOrdered(bytes32 txId);
error AlreadyDecrypted(bytes32 txId);
error AlreadyExecuted(bytes32 txId);
error ExecutionExpired(bytes32 txId, uint256 expiredAt);
error InsufficientValue(uint256 provided, uint256 required);
```

#### ForcedInclusion

| Error | Description |
|-------|-------------|
| `InsufficientBond` | Bond below required amount |
| `NotExpired` | Deadline not yet passed |
| `AlreadyClaimed` | Bond already claimed |
| `AlreadyIncluded` | Transaction was included |
| `InvalidInclusionProof` | Inclusion proof invalid |

```solidity
error InsufficientBond(uint256 provided, uint256 required);
error NotExpired(bytes32 txId, uint256 deadline);
error AlreadyClaimed(bytes32 txId);
error AlreadyIncluded(bytes32 txId, uint256 blockNumber);
error InvalidInclusionProof(bytes32 txId);
```

## SDK Error Codes

| Code | Class | Description |
|------|-------|-------------|
| `INVALID_ADDRESS` | `InvalidAddressError` | Invalid Ethereum address |
| `INVALID_AMOUNT` | `InvalidAmountError` | Invalid amount (zero, negative, etc.) |
| `INSUFFICIENT_BALANCE` | `InsufficientBalanceError` | Not enough balance |
| `TRANSACTION_FAILED` | `TransactionFailedError` | Transaction reverted |
| `NAV_STALE` | `NAVStaleError` | NAV data is stale |
| `DEPOSITS_PAUSED` | `DepositsPausedError` | Deposits are paused |
| `REDEMPTIONS_PAUSED` | `RedemptionsPausedError` | Redemptions are paused |
| `SLIPPAGE_EXCEEDED` | `SlippageExceededError` | Output below minimum |
| `TOKEN_NOT_APPROVED` | `TokenNotApprovedError` | Token not in registry |
| `MEV_UNAVAILABLE` | `MEVUnavailableError` | MEV protection unavailable |
| `ENCRYPTION_FAILED` | `EncryptionFailedError` | Encryption failed |
| `TRANSACTION_EXPIRED` | `TransactionExpiredError` | Encrypted tx expired |
| `NETWORK_ERROR` | `NetworkError` | Network connectivity issue |
| `CONTRACT_ERROR` | `ContractError` | Generic contract error |
| `UNKNOWN_ERROR` | `SDKError` | Unknown error |

## Error Handling Examples

### Solidity (Catching Specific Errors)

```solidity
try treasury.deposit(token, amount, minOut) returns (uint256 ssUSD) {
    // Success
} catch Error(string memory reason) {
    // Revert with reason string
    revert(reason);
} catch (bytes memory data) {
    // Custom error - decode it
    if (bytes4(data) == DepositsPaused.selector) {
        revert("Deposits are paused");
    } else if (bytes4(data) == SlippageExceeded.selector) {
        // Decode SlippageExceeded(expected, actual, minimum)
        (uint256 expected, uint256 actual, uint256 minimum) =
            abi.decode(data[4:], (uint256, uint256, uint256));
        revert("Slippage too high");
    }
    revert("Unknown error");
}
```

### TypeScript (ethers.js)

```typescript
import { isError } from "ethers";

try {
    await treasury.deposit(token, amount, minOut);
} catch (error) {
    if (isError(error, "CALL_EXCEPTION")) {
        const reason = error.reason;

        if (reason === "DepositsPaused") {
            console.error("Deposits are currently paused");
        } else if (reason?.startsWith("SlippageExceeded")) {
            // Parse error data
            const iface = new Interface(TreasuryVaultABI);
            const decoded = iface.parseError(error.data);
            console.error(`Slippage: expected ${decoded.args.expected}, got ${decoded.args.actual}`);
        } else {
            console.error("Transaction failed:", reason);
        }
    } else if (isError(error, "INSUFFICIENT_FUNDS")) {
        console.error("Insufficient ETH for gas");
    } else if (isError(error, "NETWORK_ERROR")) {
        console.error("Network error - please retry");
    } else {
        throw error;
    }
}
```

### SDK Error Handling

```typescript
import {
    isSDKError,
    SDKErrorCode,
    DepositsPausedError,
    NAVStaleError,
    SlippageExceededError
} from "@setchain/sdk";

try {
    await client.deposit(token, amount);
} catch (error) {
    if (isSDKError(error)) {
        switch (error.code) {
            case SDKErrorCode.DEPOSITS_PAUSED:
                return { error: "Deposits are temporarily unavailable" };

            case SDKErrorCode.NAV_STALE:
                const navError = error as NAVStaleError;
                return {
                    error: "Price data is being updated",
                    lastUpdate: new Date(navError.lastUpdate * 1000)
                };

            case SDKErrorCode.SLIPPAGE_EXCEEDED:
                const slipError = error as SlippageExceededError;
                return {
                    error: "Price moved too much",
                    expected: formatUnits(slipError.expected, 18),
                    actual: formatUnits(slipError.actual, 18)
                };

            case SDKErrorCode.INSUFFICIENT_BALANCE:
                return { error: "Insufficient balance" };

            default:
                return { error: error.message };
        }
    }
    throw error;
}
```

## Error Decoding

### Decode Custom Error

```typescript
import { Interface } from "ethers";

function decodeError(data: string, abi: any[]): { name: string; args: any } | null {
    const iface = new Interface(abi);

    try {
        const decoded = iface.parseError(data);
        return {
            name: decoded.name,
            args: decoded.args
        };
    } catch {
        return null;
    }
}

// Usage
const error = decodeError(revertData, TreasuryVaultABI);
if (error) {
    console.log(`Error: ${error.name}`);
    console.log(`Args:`, error.args);
}
```

### Common Error Selectors

```typescript
const ERROR_SELECTORS = {
    "0x...": "DepositsPaused()",
    "0x...": "RedemptionsPaused()",
    "0x...": "SlippageExceeded(uint256,uint256,uint256)",
    "0x...": "StaleNAV(uint256,uint256)",
    "0x...": "TokenNotRegistered(address)",
    // ...
};

function getErrorName(selector: string): string {
    return ERROR_SELECTORS[selector] || "Unknown";
}
```

## Related

- [SDK Errors](../sdk/errors.md)
- [Contract ABIs](./abis.md)
- [Events Reference](./events.md)
