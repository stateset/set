# Error Handling

Guide to handling errors in the Set Chain SDK.

## Error Types

All SDK errors extend the base `SDKError` class:

```typescript
class SDKError extends Error {
    readonly code: SDKErrorCode;
    readonly details?: Record<string, unknown>;
}

enum SDKErrorCode {
    INVALID_ADDRESS = "INVALID_ADDRESS",
    INVALID_AMOUNT = "INVALID_AMOUNT",
    INSUFFICIENT_BALANCE = "INSUFFICIENT_BALANCE",
    TRANSACTION_FAILED = "TRANSACTION_FAILED",
    NAV_STALE = "NAV_STALE",
    DEPOSITS_PAUSED = "DEPOSITS_PAUSED",
    REDEMPTIONS_PAUSED = "REDEMPTIONS_PAUSED",
    SLIPPAGE_EXCEEDED = "SLIPPAGE_EXCEEDED",
    TOKEN_NOT_APPROVED = "TOKEN_NOT_APPROVED",
    MEV_UNAVAILABLE = "MEV_UNAVAILABLE",
    ENCRYPTION_FAILED = "ENCRYPTION_FAILED",
    TRANSACTION_EXPIRED = "TRANSACTION_EXPIRED",
    NETWORK_ERROR = "NETWORK_ERROR",
    CONTRACT_ERROR = "CONTRACT_ERROR",
    UNKNOWN_ERROR = "UNKNOWN_ERROR"
}
```

## Specific Error Classes

### InvalidAddressError

Thrown when an address is invalid.

```typescript
class InvalidAddressError extends SDKError {
    readonly address: string;
}
```

**Example:**
```typescript
import { InvalidAddressError } from "@setchain/sdk";

try {
    validateAddress("not-an-address");
} catch (error) {
    if (error instanceof InvalidAddressError) {
        console.error(`Invalid address: ${error.address}`);
    }
}
```

### InvalidAmountError

Thrown when an amount is invalid (zero, negative, or exceeds limits).

```typescript
class InvalidAmountError extends SDKError {
    readonly amount: bigint;
    readonly reason: "zero" | "negative" | "exceeds_max" | "below_min";
    readonly limit?: bigint;
}
```

**Example:**
```typescript
import { InvalidAmountError } from "@setchain/sdk";

try {
    await client.deposit(token, 0n);
} catch (error) {
    if (error instanceof InvalidAmountError) {
        console.error(`Invalid amount: ${error.reason}`);
        if (error.limit) {
            console.error(`Limit: ${error.limit}`);
        }
    }
}
```

### InsufficientBalanceError

Thrown when user doesn't have enough balance.

```typescript
class InsufficientBalanceError extends SDKError {
    readonly token: string;
    readonly required: bigint;
    readonly available: bigint;
}
```

**Example:**
```typescript
import { InsufficientBalanceError } from "@setchain/sdk";

try {
    await client.redeem(token, amount);
} catch (error) {
    if (error instanceof InsufficientBalanceError) {
        console.error(`Insufficient ${error.token}`);
        console.error(`Required: ${formatBalance(error.required, 18)}`);
        console.error(`Available: ${formatBalance(error.available, 18)}`);
    }
}
```

### TransactionFailedError

Thrown when a transaction fails.

```typescript
class TransactionFailedError extends SDKError {
    readonly txHash?: string;
    readonly reason?: string;
    readonly revertData?: string;
}
```

**Example:**
```typescript
import { TransactionFailedError } from "@setchain/sdk";

try {
    await client.deposit(token, amount);
} catch (error) {
    if (error instanceof TransactionFailedError) {
        console.error(`Transaction failed: ${error.reason}`);
        if (error.txHash) {
            console.error(`Tx: ${error.txHash}`);
        }
    }
}
```

### NAVStaleError

Thrown when NAV data is stale and operations are restricted.

```typescript
class NAVStaleError extends SDKError {
    readonly lastUpdate: number;
    readonly threshold: number;
}
```

**Example:**
```typescript
import { NAVStaleError } from "@setchain/sdk";

try {
    await client.deposit(token, amount);
} catch (error) {
    if (error instanceof NAVStaleError) {
        const lastUpdate = new Date(error.lastUpdate * 1000);
        console.error(`NAV data is stale`);
        console.error(`Last update: ${lastUpdate}`);
        console.error(`Threshold: ${error.threshold / 3600} hours`);
    }
}
```

### DepositsPausedError

Thrown when deposits are paused.

```typescript
class DepositsPausedError extends SDKError {
    readonly pausedSince?: number;
}
```

**Example:**
```typescript
import { DepositsPausedError } from "@setchain/sdk";

try {
    await client.deposit(token, amount);
} catch (error) {
    if (error instanceof DepositsPausedError) {
        console.error("Deposits are currently paused");
        console.error("Please try again later or check announcements");
    }
}
```

### RedemptionsPausedError

Thrown when redemptions are paused.

```typescript
class RedemptionsPausedError extends SDKError {
    readonly pausedSince?: number;
}
```

### SlippageExceededError

Thrown when output is below minimum (slippage protection triggered).

```typescript
class SlippageExceededError extends SDKError {
    readonly expected: bigint;
    readonly actual: bigint;
    readonly minimum: bigint;
}
```

**Example:**
```typescript
import { SlippageExceededError } from "@setchain/sdk";

try {
    await client.deposit(token, amount, { minSsUSD: strictMinimum });
} catch (error) {
    if (error instanceof SlippageExceededError) {
        console.error("Slippage protection triggered");
        console.error(`Expected: ${formatBalance(error.expected, 18)}`);
        console.error(`Would receive: ${formatBalance(error.actual, 18)}`);
        console.error(`Minimum set: ${formatBalance(error.minimum, 18)}`);
    }
}
```

### TokenNotApprovedError

Thrown when token is not approved in TokenRegistry.

```typescript
class TokenNotApprovedError extends SDKError {
    readonly token: string;
}
```

**Example:**
```typescript
import { TokenNotApprovedError } from "@setchain/sdk";

try {
    await client.deposit(unknownToken, amount);
} catch (error) {
    if (error instanceof TokenNotApprovedError) {
        console.error(`Token ${error.token} is not approved for deposits`);
        const approved = await client.getApprovedTokens();
        console.error(`Approved tokens: ${approved.map(t => t.symbol).join(", ")}`);
    }
}
```

### MEVUnavailableError

Thrown when MEV protection is not available.

```typescript
class MEVUnavailableError extends SDKError {
    readonly reason: string;
}
```

### EncryptionFailedError

Thrown when transaction encryption fails.

```typescript
class EncryptionFailedError extends SDKError {
    readonly reason: string;
}
```

### TransactionExpiredError

Thrown when an encrypted transaction expires.

```typescript
class TransactionExpiredError extends SDKError {
    readonly txId: string;
    readonly expiredAt: number;
}
```

## Utility Functions

### isSDKError

Check if an error is an SDK error.

```typescript
function isSDKError(error: unknown): error is SDKError
```

**Example:**
```typescript
import { isSDKError } from "@setchain/sdk";

try {
    await client.deposit(token, amount);
} catch (error) {
    if (isSDKError(error)) {
        console.error(`SDK Error [${error.code}]: ${error.message}`);
    } else {
        console.error("Unexpected error:", error);
    }
}
```

### hasErrorCode

Check if error has a specific error code.

```typescript
function hasErrorCode(error: unknown, code: SDKErrorCode): boolean
```

**Example:**
```typescript
import { hasErrorCode, SDKErrorCode } from "@setchain/sdk";

try {
    await client.deposit(token, amount);
} catch (error) {
    if (hasErrorCode(error, SDKErrorCode.NAV_STALE)) {
        // Wait and retry
        await sleep(60000);
        await client.deposit(token, amount);
    } else {
        throw error;
    }
}
```

### wrapError

Wrap any error in an SDKError.

```typescript
function wrapError(error: unknown, defaultCode?: SDKErrorCode): SDKError
```

**Example:**
```typescript
import { wrapError, SDKErrorCode } from "@setchain/sdk";

try {
    await someOperation();
} catch (error) {
    const sdkError = wrapError(error, SDKErrorCode.CONTRACT_ERROR);
    console.error(`Error [${sdkError.code}]: ${sdkError.message}`);
}
```

## Error Handling Patterns

### Comprehensive Handler

```typescript
import {
    isSDKError,
    InvalidAddressError,
    InvalidAmountError,
    InsufficientBalanceError,
    TransactionFailedError,
    NAVStaleError,
    DepositsPausedError,
    RedemptionsPausedError,
    SlippageExceededError,
    TokenNotApprovedError,
    SDKErrorCode
} from "@setchain/sdk";

async function handleDeposit(token: string, amount: bigint) {
    try {
        return await client.deposit(token, amount);
    } catch (error) {
        if (!isSDKError(error)) {
            console.error("Unexpected error:", error);
            throw error;
        }

        switch (error.code) {
            case SDKErrorCode.INVALID_ADDRESS:
                throw new Error("Invalid token address");

            case SDKErrorCode.INVALID_AMOUNT:
                throw new Error("Invalid deposit amount");

            case SDKErrorCode.INSUFFICIENT_BALANCE:
                const balErr = error as InsufficientBalanceError;
                throw new Error(
                    `Insufficient balance: need ${formatBalance(balErr.required, 6)}, ` +
                    `have ${formatBalance(balErr.available, 6)}`
                );

            case SDKErrorCode.NAV_STALE:
                throw new Error("System temporarily unavailable (NAV update pending)");

            case SDKErrorCode.DEPOSITS_PAUSED:
                throw new Error("Deposits are currently paused");

            case SDKErrorCode.SLIPPAGE_EXCEEDED:
                throw new Error("Price moved too much, please retry");

            case SDKErrorCode.TOKEN_NOT_APPROVED:
                throw new Error("This token is not supported");

            case SDKErrorCode.TRANSACTION_FAILED:
                const txErr = error as TransactionFailedError;
                throw new Error(`Transaction failed: ${txErr.reason || "unknown"}`);

            default:
                throw new Error(`Operation failed: ${error.message}`);
        }
    }
}
```

### Retry Handler

```typescript
import { withRetry, isSDKError, SDKErrorCode } from "@setchain/sdk";

async function depositWithRetry(token: string, amount: bigint) {
    return withRetry(
        () => client.deposit(token, amount),
        {
            maxRetries: 3,
            initialDelay: 2000,
            shouldRetry: (error) => {
                if (!isSDKError(error)) return false;

                // Retry on transient errors
                const retryableCodes = [
                    SDKErrorCode.NETWORK_ERROR,
                    SDKErrorCode.NAV_STALE,  // May resolve quickly
                ];

                return retryableCodes.includes(error.code);
            }
        }
    );
}
```

### User-Friendly Error Messages

```typescript
function getUserMessage(error: SDKError): string {
    switch (error.code) {
        case SDKErrorCode.INVALID_ADDRESS:
            return "Please enter a valid wallet address.";

        case SDKErrorCode.INVALID_AMOUNT:
            return "Please enter a valid amount.";

        case SDKErrorCode.INSUFFICIENT_BALANCE:
            return "You don't have enough tokens for this transaction.";

        case SDKErrorCode.NAV_STALE:
            return "The system is updating prices. Please try again in a few minutes.";

        case SDKErrorCode.DEPOSITS_PAUSED:
            return "Deposits are temporarily paused for maintenance.";

        case SDKErrorCode.REDEMPTIONS_PAUSED:
            return "Redemptions are temporarily paused for maintenance.";

        case SDKErrorCode.SLIPPAGE_EXCEEDED:
            return "Prices changed while processing. Please try again.";

        case SDKErrorCode.TOKEN_NOT_APPROVED:
            return "This token is not supported for deposits.";

        case SDKErrorCode.TRANSACTION_FAILED:
            return "Transaction failed. Please check your balance and try again.";

        case SDKErrorCode.NETWORK_ERROR:
            return "Network connection issue. Please check your internet and try again.";

        default:
            return "An unexpected error occurred. Please try again later.";
    }
}
```

## Contract Error Decoding

The SDK automatically decodes contract revert reasons:

```typescript
try {
    await client.deposit(token, amount);
} catch (error) {
    if (error instanceof TransactionFailedError) {
        // Decoded revert reason
        console.error(error.reason);
        // e.g., "DepositCapExceeded()", "TokenNotRegistered()"
    }
}
```

### Custom Error Handling

```typescript
import { TransactionFailedError } from "@setchain/sdk";

try {
    await treasury.deposit(token, amount, minOut);
} catch (error) {
    if (error instanceof TransactionFailedError) {
        if (error.reason?.includes("DepositCapExceeded")) {
            const tokenInfo = await client.getApprovedTokens()
                .then(tokens => tokens.find(t => t.address === token));

            throw new Error(
                `Deposit cap reached for ${tokenInfo?.symbol}. ` +
                `Max: ${formatBalance(tokenInfo?.depositCap || 0n, 6)}`
            );
        }
    }
    throw error;
}
```

## Related

- [SDK Installation](./installation.md)
- [Stablecoin Client](./stablecoin-client.md)
- [Utilities](./utilities.md)
