//! Test contract deployment utilities
//!
//! Deploys SetRegistry contract to local Anvil instance for integration testing.

use alloy::{
    network::{EthereumWallet, TransactionBuilder},
    primitives::{Address, U256},
    providers::{Provider, ProviderBuilder},
    signers::local::PrivateKeySigner,
    sol,
    transports::http::Http,
};
use alloy_node_bindings::{Anvil, AnvilInstance};
use std::sync::Arc;

type HttpTransport = Http<reqwest::Client>;

// Import the SetRegistry contract interface
sol! {
    #[sol(rpc)]
    contract SetRegistry {
        // Events
        event SequencerAuthorized(address indexed sequencer, bool authorized);
        event BatchCommitted(
            bytes32 indexed batchId,
            bytes32 indexed tenantStoreKey,
            bytes32 eventsRoot,
            bytes32 newStateRoot,
            uint64 sequenceStart,
            uint64 sequenceEnd,
            uint32 eventCount
        );

        // Errors
        error NotAuthorizedSequencer();
        error InvalidSequenceRange();
        error EmptyEventsRoot();
        error BatchAlreadyCommitted();

        // Functions
        function initialize(address _owner, address _initialSequencer) external;
        function setSequencerAuthorization(address _sequencer, bool _authorized) external;
        function setStrictMode(bool _enabled) external;

        function commitBatch(
            bytes32 _batchId,
            bytes32 _tenantId,
            bytes32 _storeId,
            bytes32 _eventsRoot,
            bytes32 _prevStateRoot,
            bytes32 _newStateRoot,
            uint64 _sequenceStart,
            uint64 _sequenceEnd,
            uint32 _eventCount
        ) external;

        function authorizedSequencers(address) external view returns (bool);
        function totalCommitments() external view returns (uint256);
        function strictModeEnabled() external view returns (bool);

        function commitments(bytes32 batchId) external view returns (
            bytes32 eventsRoot,
            bytes32 prevStateRoot,
            bytes32 newStateRoot,
            uint64 sequenceStart,
            uint64 sequenceEnd,
            uint32 eventCount,
            uint64 timestamp,
            address submitter
        );

        function getLatestStateRoot(bytes32 _tenantId, bytes32 _storeId) external view returns (bytes32);
        function getHeadSequence(bytes32 _tenantId, bytes32 _storeId) external view returns (uint64);
    }
}

// Simplified SetRegistry bytecode for testing
// This is a minimal implementation that matches the interface
const SET_REGISTRY_BYTECODE: &str = include_str!("../fixtures/SetRegistry.bin");

/// Test SetRegistry deployment wrapper
pub struct TestSetRegistry {
    /// Anvil instance (keeps it alive)
    pub anvil: AnvilInstance,
    /// Contract address
    pub address: Address,
    /// Owner/deployer address
    pub owner: Address,
    /// Owner private key (hex string with 0x prefix)
    pub owner_key: String,
    /// Sequencer address
    pub sequencer: Address,
    /// Sequencer private key (hex string with 0x prefix)
    pub sequencer_key: String,
    /// RPC URL
    pub rpc_url: String,
    /// Chain ID
    pub chain_id: u64,
}

impl TestSetRegistry {
    /// Deploy a new SetRegistry to a local Anvil instance
    pub async fn deploy() -> anyhow::Result<Self> {
        // Start Anvil
        let anvil = Anvil::new().block_time(1).try_spawn()?;

        let rpc_url = anvil.endpoint();
        let chain_id = anvil.chain_id();

        // Get test accounts
        let owner_key = anvil.keys()[0].clone();
        let sequencer_key = anvil.keys()[1].clone();

        let owner_signer = PrivateKeySigner::from(owner_key.clone());
        let sequencer_signer = PrivateKeySigner::from(sequencer_key.clone());

        let owner = owner_signer.address();
        let sequencer = sequencer_signer.address();

        // Create provider with owner wallet
        let wallet = EthereumWallet::from(owner_signer);
        let provider = ProviderBuilder::new()
            .with_recommended_fillers()
            .wallet(wallet)
            .on_http(rpc_url.parse()?);

        // Deploy the contract
        // For testing, we'll deploy a simple mock that implements the interface
        let address = Self::deploy_mock_registry(&provider, owner, sequencer).await?;

        // Format private keys as hex strings
        let owner_key_hex = format!("0x{}", hex::encode(owner_key.to_bytes()));
        let sequencer_key_hex = format!("0x{}", hex::encode(sequencer_key.to_bytes()));

        Ok(Self {
            anvil,
            address,
            owner,
            owner_key: owner_key_hex,
            sequencer,
            sequencer_key: sequencer_key_hex,
            rpc_url,
            chain_id,
        })
    }

    /// Deploy a mock SetRegistry contract
    async fn deploy_mock_registry<P: Provider<HttpTransport> + Clone>(
        provider: &P,
        owner: Address,
        sequencer: Address,
    ) -> anyhow::Result<Address> {
        // For integration tests, we use a pre-compiled bytecode
        // In a real scenario, you'd compile the contract with forge

        // Try to load bytecode from fixtures, otherwise use inline mock
        let bytecode = if let Ok(hex_bytecode) = std::fs::read_to_string(
            std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("tests/fixtures/SetRegistry.bin"),
        ) {
            hex::decode(hex_bytecode.trim()).unwrap_or_else(|_| Self::mock_bytecode())
        } else {
            Self::mock_bytecode()
        };

        // Deploy contract
        let tx = alloy::rpc::types::TransactionRequest::default()
            .with_deploy_code(bytecode);

        let pending = provider.send_transaction(tx).await?;
        let receipt = pending.get_receipt().await?;

        let address = receipt
            .contract_address
            .ok_or_else(|| anyhow::anyhow!("No contract address in receipt"))?;

        // Initialize the contract
        let registry = SetRegistry::new(address, provider.clone());
        registry.initialize(owner, sequencer).send().await?.get_receipt().await?;

        Ok(address)
    }

    /// Generate mock bytecode for a simple registry
    /// This is a fallback when the actual contract bytecode isn't available
    fn mock_bytecode() -> Vec<u8> {
        // This would be replaced with actual compiled bytecode in CI
        // For now, return empty to trigger compilation requirement
        vec![]
    }

    /// Check if sequencer is authorized
    pub async fn is_sequencer_authorized(&self, address: Address) -> anyhow::Result<bool> {
        let provider = ProviderBuilder::new()
            .on_http(self.rpc_url.parse()?);

        let registry = SetRegistry::new(self.address, provider);
        let result = registry.authorizedSequencers(address).call().await?;
        Ok(result._0)
    }

    /// Get total commitments count
    pub async fn total_commitments(&self) -> anyhow::Result<U256> {
        let provider = ProviderBuilder::new()
            .on_http(self.rpc_url.parse()?);

        let registry = SetRegistry::new(self.address, provider);
        let result = registry.totalCommitments().call().await?;
        Ok(result._0)
    }

    /// Get commitment details
    pub async fn get_commitment(
        &self,
        batch_id: [u8; 32],
    ) -> anyhow::Result<(
        [u8; 32], // eventsRoot
        [u8; 32], // prevStateRoot
        [u8; 32], // newStateRoot
        u64,      // sequenceStart
        u64,      // sequenceEnd
        u32,      // eventCount
        u64,      // timestamp
        Address,  // submitter
    )> {
        let provider = ProviderBuilder::new()
            .on_http(self.rpc_url.parse()?);

        let registry = SetRegistry::new(self.address, provider);
        let result = registry.commitments(batch_id.into()).call().await?;

        Ok((
            result.eventsRoot.0,
            result.prevStateRoot.0,
            result.newStateRoot.0,
            result.sequenceStart,
            result.sequenceEnd,
            result.eventCount,
            result.timestamp,
            result.submitter,
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore = "requires anvil binary"]
    async fn test_deploy_registry() {
        let registry = TestSetRegistry::deploy().await.unwrap();

        assert!(!registry.address.is_zero());
        assert!(!registry.rpc_url.is_empty());

        // Verify sequencer is authorized
        let is_auth = registry.is_sequencer_authorized(registry.sequencer).await.unwrap();
        assert!(is_auth);
    }
}
