//! Error types for the anchor service
//!
//! This module provides structured error types for better error handling,
//! monitoring, and debugging of the anchor service.

use thiserror::Error;

/// Main error type for the anchor service
#[derive(Error, Debug)]
pub enum AnchorError {
    /// Configuration errors
    #[error("Configuration error: {0}")]
    Config(#[from] ConfigError),

    /// L2 chain connection errors
    #[error("L2 connection error: {0}")]
    L2Connection(#[from] L2Error),

    /// Sequencer API errors
    #[error("Sequencer API error: {0}")]
    SequencerApi(#[from] SequencerApiError),

    /// Transaction errors
    #[error("Transaction error: {0}")]
    Transaction(#[from] TransactionError),

    /// Authorization errors
    #[error("Authorization error: {0}")]
    Authorization(#[from] AuthorizationError),

    /// Generic internal error
    #[error("Internal error: {0}")]
    Internal(String),
}

/// Configuration-related errors
#[derive(Error, Debug)]
pub enum ConfigError {
    #[error("Missing required environment variable: {0}")]
    MissingEnvVar(String),

    #[error("Invalid configuration value for {field}: {message}")]
    InvalidValue { field: String, message: String },

    #[error("Invalid private key format")]
    InvalidPrivateKey,

    #[error("Invalid address format: {0}")]
    InvalidAddress(String),

    #[error("Invalid URL format: {0}")]
    InvalidUrl(String),
}

/// L2 chain connection errors
#[derive(Error, Debug)]
pub enum L2Error {
    #[error("Failed to connect to L2 RPC at {url}: {message}")]
    ConnectionFailed { url: String, message: String },

    #[error("L2 RPC request failed: {0}")]
    RpcError(String),

    #[error("Chain ID mismatch: expected {expected}, got {actual}")]
    ChainIdMismatch { expected: u64, actual: u64 },

    #[error("Failed to get gas price: {0}")]
    GasPriceError(String),

    #[error("L2 connection timeout after {seconds}s")]
    Timeout { seconds: u64 },

    #[error("L2 provider not initialized")]
    NotInitialized,
}

/// Sequencer API errors
#[derive(Error, Debug)]
pub enum SequencerApiError {
    #[error("Failed to connect to sequencer API at {url}: {message}")]
    ConnectionFailed { url: String, message: String },

    #[error("Sequencer API returned error status {status}: {body}")]
    HttpError { status: u16, body: String },

    #[error("Failed to parse sequencer API response: {0}")]
    ParseError(String),

    #[error("Sequencer API request timeout after {seconds}s")]
    Timeout { seconds: u64 },

    #[error("No pending commitments available")]
    NoPendingCommitments,

    #[error("Failed to notify sequencer of anchoring: {0}")]
    NotificationFailed(String),
}

/// Transaction-related errors
#[derive(Error, Debug)]
pub enum TransactionError {
    #[error("Transaction failed to submit: {0}")]
    SubmissionFailed(String),

    #[error("Transaction reverted: {reason}")]
    Reverted { reason: String },

    #[error("Transaction timed out waiting for confirmation")]
    ConfirmationTimeout,

    #[error("Gas price {current_gwei} gwei exceeds maximum {max_gwei} gwei")]
    GasPriceTooHigh { current_gwei: u64, max_gwei: u64 },

    #[error("Insufficient funds for gas: required {required}, available {available}")]
    InsufficientFunds { required: String, available: String },

    #[error("Nonce error: {0}")]
    NonceError(String),

    #[error("Failed to encode transaction data: {0}")]
    EncodingError(String),

    #[error("Invalid bytes32 value: {0}")]
    InvalidBytes32(String),
}

/// Authorization-related errors
#[derive(Error, Debug)]
pub enum AuthorizationError {
    #[error("Sequencer address {address} is not authorized in SetRegistry")]
    NotAuthorized { address: String },

    #[error("Failed to check authorization: {0}")]
    CheckFailed(String),

    #[error("Invalid private key")]
    InvalidPrivateKey,
}

/// Error severity levels for monitoring
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ErrorSeverity {
    /// Transient errors that may resolve on retry
    Transient,
    /// Errors requiring attention but not critical
    Warning,
    /// Critical errors requiring immediate attention
    Critical,
    /// Fatal errors that prevent operation
    Fatal,
}

impl AnchorError {
    /// Get the severity level of this error
    pub fn severity(&self) -> ErrorSeverity {
        match self {
            AnchorError::Config(_) => ErrorSeverity::Fatal,
            AnchorError::Authorization(_) => ErrorSeverity::Fatal,
            AnchorError::L2Connection(e) => e.severity(),
            AnchorError::SequencerApi(e) => e.severity(),
            AnchorError::Transaction(e) => e.severity(),
            AnchorError::Internal(_) => ErrorSeverity::Critical,
        }
    }

    /// Check if this error is retryable
    pub fn is_retryable(&self) -> bool {
        matches!(self.severity(), ErrorSeverity::Transient)
    }

    /// Get a short error code for metrics/logging
    pub fn error_code(&self) -> &'static str {
        match self {
            AnchorError::Config(_) => "CONFIG_ERROR",
            AnchorError::L2Connection(_) => "L2_CONNECTION_ERROR",
            AnchorError::SequencerApi(_) => "SEQUENCER_API_ERROR",
            AnchorError::Transaction(_) => "TRANSACTION_ERROR",
            AnchorError::Authorization(_) => "AUTHORIZATION_ERROR",
            AnchorError::Internal(_) => "INTERNAL_ERROR",
        }
    }
}

impl L2Error {
    fn severity(&self) -> ErrorSeverity {
        match self {
            L2Error::ConnectionFailed { .. } => ErrorSeverity::Transient,
            L2Error::RpcError(_) => ErrorSeverity::Transient,
            L2Error::ChainIdMismatch { .. } => ErrorSeverity::Fatal,
            L2Error::GasPriceError(_) => ErrorSeverity::Transient,
            L2Error::Timeout { .. } => ErrorSeverity::Transient,
            L2Error::NotInitialized => ErrorSeverity::Fatal,
        }
    }
}

impl SequencerApiError {
    fn severity(&self) -> ErrorSeverity {
        match self {
            SequencerApiError::ConnectionFailed { .. } => ErrorSeverity::Transient,
            SequencerApiError::HttpError { status, .. } => {
                if *status >= 500 {
                    ErrorSeverity::Transient
                } else {
                    ErrorSeverity::Warning
                }
            }
            SequencerApiError::ParseError(_) => ErrorSeverity::Warning,
            SequencerApiError::Timeout { .. } => ErrorSeverity::Transient,
            SequencerApiError::NoPendingCommitments => ErrorSeverity::Transient,
            SequencerApiError::NotificationFailed(_) => ErrorSeverity::Warning,
        }
    }
}

impl TransactionError {
    fn severity(&self) -> ErrorSeverity {
        match self {
            TransactionError::SubmissionFailed(_) => ErrorSeverity::Transient,
            TransactionError::Reverted { .. } => ErrorSeverity::Warning,
            TransactionError::ConfirmationTimeout => ErrorSeverity::Transient,
            TransactionError::GasPriceTooHigh { .. } => ErrorSeverity::Transient,
            TransactionError::InsufficientFunds { .. } => ErrorSeverity::Critical,
            TransactionError::NonceError(_) => ErrorSeverity::Transient,
            TransactionError::EncodingError(_) => ErrorSeverity::Critical,
            TransactionError::InvalidBytes32(_) => ErrorSeverity::Critical,
        }
    }
}

/// Result type alias using AnchorError
pub type AnchorResult<T> = std::result::Result<T, AnchorError>;

/// Extension trait for converting anyhow errors to AnchorError
pub trait ResultExt<T> {
    /// Convert to AnchorError with context
    fn anchor_context(self, context: &str) -> AnchorResult<T>;
}

impl<T, E: std::error::Error> ResultExt<T> for std::result::Result<T, E> {
    fn anchor_context(self, context: &str) -> AnchorResult<T> {
        self.map_err(|e| AnchorError::Internal(format!("{}: {}", context, e)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_severity() {
        let config_err = AnchorError::Config(ConfigError::MissingEnvVar("TEST".into()));
        assert_eq!(config_err.severity(), ErrorSeverity::Fatal);
        assert!(!config_err.is_retryable());

        let l2_err = AnchorError::L2Connection(L2Error::Timeout { seconds: 30 });
        assert_eq!(l2_err.severity(), ErrorSeverity::Transient);
        assert!(l2_err.is_retryable());
    }

    #[test]
    fn test_error_codes() {
        let err = AnchorError::Transaction(TransactionError::ConfirmationTimeout);
        assert_eq!(err.error_code(), "TRANSACTION_ERROR");
    }

    #[test]
    fn test_error_display() {
        let err = ConfigError::MissingEnvVar("SEQUENCER_PRIVATE_KEY".into());
        assert!(err.to_string().contains("SEQUENCER_PRIVATE_KEY"));
    }
}
