// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../mev/ForcedInclusion.sol";
import "../mev/EncryptedMempool.sol";
import "../mev/ThresholdKeyRegistry.sol";
import "../SetRegistry.sol";
import "../stablecoin/TokenRegistry.sol";
import "../stablecoin/NAVOracle.sol";
import "../stablecoin/ssUSD.sol";
import "../stablecoin/TreasuryVault.sol";
import "../stablecoin/interfaces/ITokenRegistry.sol";

/**
 * @title MockUSDC
 * @notice Mock USDC for testing
 */
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title MockL2OutputOracle
 * @notice Mock oracle for testing forced inclusion proofs
 */
contract MockL2OutputOracle {
    mapping(uint256 => bytes32) public outputRoots;

    function setL2Output(uint256 blockNumber, bytes32 outputRoot) external {
        outputRoots[blockNumber] = outputRoot;
    }

    function getL2Output(uint256 _l2BlockNumber) external view returns (bytes32) {
        return outputRoots[_l2BlockNumber];
    }
}

/**
 * @title SecurityFixesTest
 * @notice Tests for security-critical fixes
 */
contract SecurityFixesTest is Test {
    // =========================================================================
    // ForcedInclusion Tests - Proof Verification
    // =========================================================================

    ForcedInclusion public forcedInclusion;
    MockL2OutputOracle public mockOracle;

    address public owner = address(0x1);
    address public user = address(0x2);
    address public target = address(0x100);

    function setUp() public {
        vm.deal(user, 10 ether);

        mockOracle = new MockL2OutputOracle();

        forcedInclusion = new ForcedInclusion(
            owner,
            address(mockOracle),
            address(0x4)
        );
    }

    function test_ForcedInclusion_RejectsEmptyProof() public {
        vm.prank(user);
        bytes32 txId = forcedInclusion.forceTransaction{value: 0.1 ether}(
            target,
            abi.encodeWithSignature("test()"),
            100_000
        );

        // Empty proof should fail
        vm.expectRevert(ForcedInclusion.InvalidInclusionProof.selector);
        forcedInclusion.confirmInclusion(txId, 100, "");
    }

    function test_ForcedInclusion_RejectsShortProof() public {
        vm.prank(user);
        bytes32 txId = forcedInclusion.forceTransaction{value: 0.1 ether}(
            target,
            abi.encodeWithSignature("test()"),
            100_000
        );

        // Proof less than 64 bytes should fail
        bytes memory shortProof = abi.encodePacked(bytes32(uint256(1)));
        vm.expectRevert(ForcedInclusion.InvalidInclusionProof.selector);
        forcedInclusion.confirmInclusion(txId, 100, shortProof);
    }

    function test_ForcedInclusion_RejectsProofWithNoOracleOutput() public {
        vm.prank(user);
        bytes32 txId = forcedInclusion.forceTransaction{value: 0.1 ether}(
            target,
            abi.encodeWithSignature("test()"),
            100_000
        );

        // Create a valid-looking proof but oracle has no output
        bytes32[] memory storageProof = new bytes32[](1);
        storageProof[0] = bytes32(uint256(1));
        bytes memory proof = abi.encode(bytes32(uint256(123)), storageProof, uint256(0));

        vm.expectRevert(ForcedInclusion.InvalidInclusionProof.selector);
        forcedInclusion.confirmInclusion(txId, 100, proof);
    }

    function test_ForcedInclusion_RejectsProofWithMismatchedOutputRoot() public {
        vm.prank(user);
        bytes32 txId = forcedInclusion.forceTransaction{value: 0.1 ether}(
            target,
            abi.encodeWithSignature("test()"),
            100_000
        );

        // Set oracle output
        bytes32 oracleRoot = keccak256("oracle_root");
        mockOracle.setL2Output(100, oracleRoot);

        // Create proof with different claimed root
        bytes32 claimedRoot = keccak256("different_root");
        bytes32[] memory storageProof = new bytes32[](1);
        storageProof[0] = bytes32(uint256(1));
        bytes memory proof = abi.encode(claimedRoot, storageProof, uint256(0));

        vm.expectRevert(ForcedInclusion.InvalidInclusionProof.selector);
        forcedInclusion.confirmInclusion(txId, 100, proof);
    }

    // =========================================================================
    // ThresholdKeyRegistry Tests - DKG State Hygiene
    // =========================================================================

    ThresholdKeyRegistry public registry;
    address public keyper1 = address(0x10);
    address public keyper2 = address(0x20);
    address public keyper3 = address(0x30);

    bytes public validPubKey = hex"a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4";

    function _setupRegistry() internal {
        ThresholdKeyRegistry impl = new ThresholdKeyRegistry();
        bytes memory initData = abi.encodeCall(
            ThresholdKeyRegistry.initialize,
            (owner, 2, 1 ether)
        );
        address registryProxy = address(new ERC1967Proxy(address(impl), initData));
        registry = ThresholdKeyRegistry(payable(registryProxy));

        // Register keypers
        vm.deal(keyper1, 2 ether);
        vm.deal(keyper2, 2 ether);
        vm.deal(keyper3, 2 ether);

        vm.prank(keyper1);
        registry.registerKeyper{value: 1 ether}(validPubKey, "http://k1:8080");
        vm.prank(keyper2);
        registry.registerKeyper{value: 1 ether}(validPubKey, "http://k2:8080");
        vm.prank(keyper3);
        registry.registerKeyper{value: 1 ether}(validPubKey, "http://k3:8080");
    }

    function test_DKG_PreventsDuplicateRegistration() public {
        _setupRegistry();

        vm.prank(owner);
        registry.startDKG();

        vm.prank(keyper1);
        registry.registerForDKG();

        // Second registration should fail
        vm.prank(keyper1);
        vm.expectRevert(ThresholdKeyRegistry.AlreadyRegisteredForDKG.selector);
        registry.registerForDKG();
    }

    function test_DKG_ClearsStateOnNewCeremony() public {
        _setupRegistry();

        // First DKG ceremony
        vm.prank(owner);
        registry.startDKG();

        vm.prank(keyper1);
        registry.registerForDKG();
        vm.prank(keyper2);
        registry.registerForDKG();

        vm.prank(keyper1);
        registry.submitDealing(keccak256("dealing1"));
        vm.prank(keyper2);
        registry.submitDealing(keccak256("dealing2"));

        vm.prank(owner);
        registry.finalizeDKG(validPubKey, keccak256("commitment1"));

        // Start second DKG ceremony
        vm.prank(owner);
        registry.startDKG();

        // Keyper1 should be able to register again
        vm.prank(keyper1);
        registry.registerForDKG(); // Should not revert

        // Keyper1 should be able to submit dealing again
        vm.prank(keyper2);
        registry.registerForDKG();

        vm.prank(keyper1);
        registry.submitDealing(keccak256("dealing3")); // Should not revert
    }

    function test_DKG_AbortClearsState() public {
        _setupRegistry();

        vm.prank(owner);
        registry.startDKG();

        vm.prank(keyper1);
        registry.registerForDKG();
        vm.prank(keyper2);
        registry.registerForDKG();

        // Abort the DKG
        vm.prank(owner);
        registry.abortDKG("Test abort");

        assertEq(registry.getDKGPhase(), 0);

        // Start new DKG
        vm.prank(owner);
        registry.startDKG();

        // Should be able to register again
        vm.prank(keyper1);
        registry.registerForDKG();
    }

    // =========================================================================
    // SetRegistry Tests - Legacy Function Access
    // =========================================================================

    SetRegistry public setRegistry;
    address public sequencer = address(0x50);

    function _setupSetRegistry() internal {
        SetRegistry impl = new SetRegistry();
        bytes memory initData = abi.encodeCall(
            SetRegistry.initialize,
            (owner, sequencer)
        );
        address registryProxy = address(new ERC1967Proxy(address(impl), initData));
        setRegistry = SetRegistry(registryProxy);
    }

    function test_RegisterBatchRoot_DisabledByDefault() public {
        _setupSetRegistry();

        vm.prank(sequencer);
        vm.expectRevert(SetRegistry.LegacyFunctionsDisabled.selector);
        setRegistry.registerBatchRoot(1, 10, keccak256("root"));
    }

    function test_RegisterBatchRoot_RequiresAuthorization() public {
        _setupSetRegistry();

        // Enable legacy functions
        vm.prank(owner);
        setRegistry.setLegacyFunctionsEnabled(true);

        // Unauthorized caller should fail
        vm.prank(user);
        vm.expectRevert(SetRegistry.NotAuthorizedSequencer.selector);
        setRegistry.registerBatchRoot(1, 10, keccak256("root"));
    }

    function test_RegisterBatchRoot_WorksWhenEnabled() public {
        _setupSetRegistry();

        // Enable legacy functions
        vm.prank(owner);
        setRegistry.setLegacyFunctionsEnabled(true);

        // Authorized caller should succeed
        vm.prank(sequencer);
        setRegistry.registerBatchRoot(1, 10, keccak256("root"));

        assertEq(setRegistry.totalCommitments(), 1);
    }

    function test_SetLegacyFunctionsEnabled_OnlyOwner() public {
        _setupSetRegistry();

        vm.prank(user);
        vm.expectRevert();
        setRegistry.setLegacyFunctionsEnabled(true);
    }
}

/**
 * @title RedemptionAccountingTest
 * @notice Tests for redemption accounting under NAV changes
 */
contract RedemptionAccountingTest is Test {
    TokenRegistry public tokenRegistry;
    NAVOracle public navOracle;
    ssUSD public ssusd;
    TreasuryVault public treasury;
    MockUSDC public usdc;

    address public owner = address(0x1);
    address public attestor = address(0x2);
    address public user1 = address(0x100);
    address public user2 = address(0x200);

    function setUp() public {
        vm.startPrank(owner);

        usdc = new MockUSDC();

        // Deploy TokenRegistry
        TokenRegistry registryImpl = new TokenRegistry();
        tokenRegistry = TokenRegistry(address(new ERC1967Proxy(
            address(registryImpl),
            abi.encodeCall(TokenRegistry.initialize, (owner))
        )));

        // Deploy NAVOracle
        NAVOracle oracleImpl = new NAVOracle();
        navOracle = NAVOracle(address(new ERC1967Proxy(
            address(oracleImpl),
            abi.encodeCall(NAVOracle.initialize, (owner, attestor, 24 hours))
        )));

        // Deploy ssUSD
        ssUSD ssusdImpl = new ssUSD();
        ssusd = ssUSD(address(new ERC1967Proxy(
            address(ssusdImpl),
            abi.encodeCall(ssUSD.initialize, (owner, address(navOracle)))
        )));

        // Deploy TreasuryVault
        TreasuryVault treasuryImpl = new TreasuryVault();
        treasury = TreasuryVault(address(new ERC1967Proxy(
            address(treasuryImpl),
            abi.encodeCall(TreasuryVault.initialize, (
                owner,
                address(tokenRegistry),
                address(navOracle),
                address(ssusd)
            ))
        )));

        // Wire up
        ssusd.setTreasuryVault(address(treasury));
        navOracle.setssUSD(address(ssusd));

        // Register USDC
        tokenRegistry.registerToken(
            address(usdc),
            "USD Coin",
            "USDC",
            6,
            ITokenRegistry.TokenCategory.BRIDGED,
            ITokenRegistry.TrustLevel.TRUSTED,
            true,
            ""
        );

        vm.stopPrank();

        // Fund users
        usdc.mint(user1, 1_000_000 * 1e6);
        usdc.mint(user2, 1_000_000 * 1e6);
    }

    function test_RedemptionShares_LockedAtRequestTime() public {
        // User deposits 1000 USDC
        vm.startPrank(user1);
        usdc.approve(address(treasury), 1000 * 1e6);
        treasury.deposit(address(usdc), 1000 * 1e6, user1);

        uint256 sharesBefore = ssusd.sharesOf(user1);

        // Request redemption of 500 ssUSD
        ssusd.approve(address(treasury), 500 * 1e18);
        uint256 requestId = treasury.requestRedemption(500 * 1e18, address(usdc));
        vm.stopPrank();

        // Shares should be burned immediately
        uint256 sharesAfter = ssusd.sharesOf(user1);
        assertTrue(sharesAfter < sharesBefore, "Shares should be burned at request time");

        // Check tracked redemption shares
        uint256 redemptionShares = treasury.redemptionShares(requestId);
        assertTrue(redemptionShares > 0, "Redemption shares should be tracked");
    }

    function test_RedemptionUnaffectedByNAVIncrease() public {
        // User deposits 1000 USDC
        vm.startPrank(user1);
        usdc.approve(address(treasury), 1000 * 1e6);
        treasury.deposit(address(usdc), 1000 * 1e6, user1);

        // Request redemption
        ssusd.approve(address(treasury), 500 * 1e18);
        uint256 requestId = treasury.requestRedemption(500 * 1e18, address(usdc));
        vm.stopPrank();

        // Record USDC balance before
        uint256 usdcBefore = usdc.balanceOf(user1);

        // NAV increases by 50% (should not affect redemption)
        vm.prank(attestor);
        navOracle.attestNAV(1500 * 1e18, 20240101, bytes32(0));

        // Wait for delay
        vm.warp(block.timestamp + 1 hours + 1);

        // Process redemption
        treasury.processRedemption(requestId);

        uint256 usdcAfter = usdc.balanceOf(user1);
        uint256 received = usdcAfter - usdcBefore;

        // Should receive ~500 USDC (minus 0.1% fee), NOT 750 USDC
        // Fee: 500 * 0.001 = 0.5 USDC, so ~499.5 USDC
        uint256 expectedMin = 499 * 1e6;
        uint256 expectedMax = 500 * 1e6;

        assertTrue(received >= expectedMin && received <= expectedMax,
            "Redemption should be based on request-time value, not current NAV");
    }

    function test_CancelRedemption_RestoresShares() public {
        // User deposits 1000 USDC
        vm.startPrank(user1);
        usdc.approve(address(treasury), 1000 * 1e6);
        treasury.deposit(address(usdc), 1000 * 1e6, user1);

        uint256 sharesBefore = ssusd.sharesOf(user1);

        // Request redemption
        ssusd.approve(address(treasury), 500 * 1e18);
        uint256 requestId = treasury.requestRedemption(500 * 1e18, address(usdc));

        uint256 sharesAfterRequest = ssusd.sharesOf(user1);

        // Cancel redemption
        treasury.cancelRedemption(requestId);
        vm.stopPrank();

        uint256 sharesAfterCancel = ssusd.sharesOf(user1);

        // Shares should be restored
        assertEq(sharesAfterCancel, sharesBefore, "Shares should be fully restored after cancel");
    }

    function test_MultipleRedemptions_IndependentAccounting() public {
        // User deposits
        vm.startPrank(user1);
        usdc.approve(address(treasury), 1000 * 1e6);
        treasury.deposit(address(usdc), 1000 * 1e6, user1);

        // Request two redemptions
        ssusd.approve(address(treasury), 600 * 1e18);
        uint256 request1 = treasury.requestRedemption(300 * 1e18, address(usdc));
        uint256 request2 = treasury.requestRedemption(300 * 1e18, address(usdc));
        vm.stopPrank();

        // Both should have separate share tracking
        uint256 shares1 = treasury.redemptionShares(request1);
        uint256 shares2 = treasury.redemptionShares(request2);

        assertTrue(shares1 > 0, "Request 1 should have tracked shares");
        assertTrue(shares2 > 0, "Request 2 should have tracked shares");
    }
}

/**
 * @title EncryptedMempoolSecurityTest
 * @notice Tests for decryption proof binding
 */
contract EncryptedMempoolSecurityTest is Test {
    EncryptedMempool public mempool;
    ThresholdKeyRegistry public registry;

    address public owner = address(0x1);
    address public sequencer = address(0x2);
    address public user = address(0x3);
    address public keyper1 = address(0x10);
    address public keyper2 = address(0x20);

    bytes public validPubKey = hex"a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4";

    function setUp() public {
        vm.deal(user, 10 ether);
        vm.deal(keyper1, 2 ether);
        vm.deal(keyper2, 2 ether);

        // Deploy registry
        vm.startPrank(owner);
        ThresholdKeyRegistry registryImpl = new ThresholdKeyRegistry();
        bytes memory registryInit = abi.encodeCall(
            ThresholdKeyRegistry.initialize,
            (owner, 2, 1 ether)
        );
        address registryProxy = address(new ERC1967Proxy(address(registryImpl), registryInit));
        registry = ThresholdKeyRegistry(payable(registryProxy));

        // Deploy mempool
        EncryptedMempool mempoolImpl = new EncryptedMempool();
        bytes memory mempoolInit = abi.encodeCall(
            EncryptedMempool.initialize,
            (owner, address(registry), sequencer)
        );
        address mempoolProxy = address(new ERC1967Proxy(address(mempoolImpl), mempoolInit));
        mempool = EncryptedMempool(payable(mempoolProxy));
        vm.stopPrank();

        // Register keypers and complete DKG
        vm.prank(keyper1);
        registry.registerKeyper{value: 1 ether}(validPubKey, "http://k1:8080");
        vm.prank(keyper2);
        registry.registerKeyper{value: 1 ether}(validPubKey, "http://k2:8080");

        vm.prank(owner);
        registry.startDKG();

        vm.prank(keyper1);
        registry.registerForDKG();
        vm.prank(keyper2);
        registry.registerForDKG();

        vm.prank(keyper1);
        registry.submitDealing(keccak256("dealing1"));
        vm.prank(keyper2);
        registry.submitDealing(keccak256("dealing2"));

        vm.prank(owner);
        registry.finalizeDKG(validPubKey, keccak256("commitment"));
    }

    function test_SubmitDecryption_RejectsShortProof() public {
        // Submit encrypted tx
        bytes memory payload = abi.encodePacked("encrypted_data");
        vm.prank(user);
        bytes32 txId = mempool.submitEncryptedTx{value: 1 ether}(
            payload,
            2, // epoch
            100_000,
            1 gwei
        );

        // Commit ordering
        bytes32[] memory txIds = new bytes32[](1);
        txIds[0] = txId;
        vm.prank(sequencer);
        mempool.commitOrdering(keccak256("batch"), txIds, keccak256("root"), "sig");

        // Try to submit decryption with short proof
        bytes memory shortProof = abi.encodePacked(bytes32(uint256(1)));
        vm.prank(sequencer);
        vm.expectRevert(EncryptedMempool.DecryptionFailed.selector);
        mempool.submitDecryption(txId, address(0x100), "", 0, shortProof);
    }

    function test_SubmitDecryption_RejectsWrongCommitment() public {
        // Submit encrypted tx
        bytes memory payload = abi.encodePacked("encrypted_data");
        vm.prank(user);
        bytes32 txId = mempool.submitEncryptedTx{value: 1 ether}(
            payload,
            2, // epoch
            100_000,
            1 gwei
        );

        // Commit ordering
        bytes32[] memory txIds = new bytes32[](1);
        txIds[0] = txId;
        vm.prank(sequencer);
        mempool.commitOrdering(keccak256("batch"), txIds, keccak256("root"), "sig");

        // Create proof with wrong commitment (doesn't match payload hash + decrypted data)
        bytes memory signature = new bytes(96);
        bytes32 wrongCommitment = keccak256("wrong_commitment");
        address[] memory signers = new address[](2);
        signers[0] = keyper1;
        signers[1] = keyper2;

        bytes memory proof = abi.encode(signature, wrongCommitment, uint256(2), signers);

        vm.prank(sequencer);
        vm.expectRevert(EncryptedMempool.DecryptionFailed.selector);
        mempool.submitDecryption(txId, address(0x100), "", 0, proof);
    }

    function test_SubmitDecryption_RejectsWrongEpoch() public {
        // Submit encrypted tx with epoch 2
        bytes memory payload = abi.encodePacked("encrypted_data");
        vm.prank(user);
        bytes32 txId = mempool.submitEncryptedTx{value: 1 ether}(
            payload,
            2, // epoch
            100_000,
            1 gwei
        );

        // Commit ordering
        bytes32[] memory txIds = new bytes32[](1);
        txIds[0] = txId;
        vm.prank(sequencer);
        mempool.commitOrdering(keccak256("batch"), txIds, keccak256("root"), "sig");

        // Create proof with wrong epoch
        bytes memory signature = new bytes(96);
        bytes32 payloadHash = keccak256(payload);
        bytes32 correctCommitment = keccak256(abi.encodePacked(payloadHash, address(0x100), "", uint256(0)));
        address[] memory signers = new address[](2);
        signers[0] = keyper1;
        signers[1] = keyper2;

        // Use epoch 1 instead of 2
        bytes memory proof = abi.encode(signature, correctCommitment, uint256(1), signers);

        vm.prank(sequencer);
        vm.expectRevert(EncryptedMempool.DecryptionFailed.selector);
        mempool.submitDecryption(txId, address(0x100), "", 0, proof);
    }

    function test_SubmitDecryption_RejectsDuplicateSigners() public {
        // Submit encrypted tx
        bytes memory payload = abi.encodePacked("encrypted_data");
        vm.prank(user);
        bytes32 txId = mempool.submitEncryptedTx{value: 1 ether}(
            payload,
            2, // epoch
            100_000,
            1 gwei
        );

        // Commit ordering
        bytes32[] memory txIds = new bytes32[](1);
        txIds[0] = txId;
        vm.prank(sequencer);
        mempool.commitOrdering(keccak256("batch"), txIds, keccak256("root"), "sig");

        // Create proof with duplicate signers
        bytes memory signature = new bytes(96);
        bytes32 payloadHash = keccak256(payload);
        bytes32 correctCommitment = keccak256(abi.encodePacked(payloadHash, address(0x100), "", uint256(0)));
        address[] memory signers = new address[](2);
        signers[0] = keyper1;
        signers[1] = keyper1; // Duplicate!

        bytes memory proof = abi.encode(signature, correctCommitment, uint256(2), signers);

        vm.prank(sequencer);
        vm.expectRevert(EncryptedMempool.DecryptionFailed.selector);
        mempool.submitDecryption(txId, address(0x100), "", 0, proof);
    }
}
