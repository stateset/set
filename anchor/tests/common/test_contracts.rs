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
use anyhow::{bail, Context};
use std::process::Command;

type HttpTransport = Http<reqwest::Client>;

// Import the SetRegistry contract interface
sol! {
    #[allow(clippy::too_many_arguments)]
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
/// Test SetRegistry deployment wrapper
pub struct TestSetRegistry {
    /// Anvil instance (keeps it alive)
    pub _anvil: AnvilInstance,
    /// Contract address
    pub address: Address,
    /// Sequencer address
    pub sequencer: Address,
    /// Sequencer private key (hex string with 0x prefix)
    pub sequencer_key: String,
    /// RPC URL
    pub rpc_url: String,
}

impl TestSetRegistry {
    /// Deploy a new SetRegistry to a local Anvil instance
    pub async fn deploy() -> anyhow::Result<Self> {
        // Start Anvil
        let anvil = Anvil::new().block_time(1).try_spawn()?;

        let rpc_url = anvil.endpoint();
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

        // Deploy the source-auditable test double.
        let address = Self::deploy_mock_registry(&provider, owner, sequencer).await?;

        // Format private keys as hex strings
        let sequencer_key_hex = format!("0x{}", hex::encode(sequencer_key.to_bytes()));

        Ok(Self {
            _anvil: anvil,
            address,
            sequencer,
            sequencer_key: sequencer_key_hex,
            rpc_url,
        })
    }

    /// Deploy a mock SetRegistry contract
    async fn deploy_mock_registry<P: Provider<HttpTransport> + Clone>(
        provider: &P,
        owner: Address,
        sequencer: Address,
    ) -> anyhow::Result<Address> {
        let bytecode = Self::compile_mock_registry()?;

        // Deploy contract
        let tx = alloy::rpc::types::TransactionRequest::default().with_deploy_code(bytecode);

        let pending = provider.send_transaction(tx).await?;
        let receipt = pending.get_receipt().await?;

        let address = receipt
            .contract_address
            .ok_or_else(|| anyhow::anyhow!("No contract address in receipt"))?;

        // Initialize the contract
        let registry = SetRegistry::new(address, provider.clone());
        registry
            .initialize(owner, sequencer)
            .send()
            .await?
            .get_receipt()
            .await?;

        Ok(address)
    }

    /// Compile the test registry from auditable Solidity source.
    ///
    /// Keeping source instead of opaque checked-in bytecode prevents the fixture from silently
    /// drifting away from the ABI exercised by these integration tests.
    fn compile_mock_registry() -> anyhow::Result<Vec<u8>> {
        let fixture_root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures");
        let build_dir = tempfile::tempdir().context("create temporary Foundry build directory")?;
        let out_dir = build_dir.path().join("out");
        let cache_dir = build_dir.path().join("cache");
        let forge = std::env::var_os("FOUNDRY_FORGE").unwrap_or_else(|| "forge".into());

        let output = Command::new(forge)
            .args(["build", "--root"])
            .arg(&fixture_root)
            .arg("--out")
            .arg(&out_dir)
            .arg("--cache-path")
            .arg(&cache_dir)
            .output()
            .context("run forge to compile the SetRegistry integration fixture")?;

        if !output.status.success() {
            bail!(
                "fixture compilation failed: {}",
                String::from_utf8_lossy(&output.stderr).trim()
            );
        }

        let artifact_path = out_dir.join("TestSetRegistry.sol/TestSetRegistry.json");
        let artifact: serde_json::Value =
            serde_json::from_slice(&std::fs::read(&artifact_path).with_context(|| {
                format!("read fixture artifact at {}", artifact_path.display())
            })?)
            .context("parse fixture artifact")?;
        let encoded_bytecode = artifact
            .pointer("/bytecode/object")
            .and_then(serde_json::Value::as_str)
            .context("fixture artifact has no deployable bytecode")?;
        let object = encoded_bytecode
            .strip_prefix("0x")
            .unwrap_or(encoded_bytecode);

        let bytecode = hex::decode(object).context("decode fixture deployment bytecode")?;
        if bytecode.is_empty() {
            bail!("fixture compiler returned empty deployment bytecode");
        }
        Ok(bytecode)
    }

    /// Check if sequencer is authorized
    pub async fn is_sequencer_authorized(&self, address: Address) -> anyhow::Result<bool> {
        let provider = ProviderBuilder::new().on_http(self.rpc_url.parse()?);

        let registry = SetRegistry::new(self.address, provider);
        let result = registry.authorizedSequencers(address).call().await?;
        Ok(result._0)
    }

    /// Get total commitments count
    pub async fn total_commitments(&self) -> anyhow::Result<U256> {
        let provider = ProviderBuilder::new().on_http(self.rpc_url.parse()?);

        let registry = SetRegistry::new(self.address, provider);
        let result = registry.totalCommitments().call().await?;
        Ok(result._0)
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
        let is_auth = registry
            .is_sequencer_authorized(registry.sequencer)
            .await
            .unwrap();
        assert!(is_auth);
    }
}
