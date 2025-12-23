// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../mev/EncryptedMempool.sol";
import "../mev/ThresholdKeyRegistry.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title EncryptedMempoolTest
 * @notice Tests for threshold-encrypted transaction mempool
 */
contract EncryptedMempoolTest is Test {
    EncryptedMempool public mempool;
    ThresholdKeyRegistry public keyRegistry;
    address public mempoolProxy;
    address public registryProxy;

    address public owner = address(0x1);
    address public sequencer = address(0x2);
    address public user1 = address(0x100);
    address public user2 = address(0x200);
    address payable public targetContract;

    // Test keypers
    uint256 private keyper1Pk = 0xA11CE;
    uint256 private keyper2Pk = 0xB0B;
    uint256 private keyper3Pk = 0xC0FFEE;

    address public keyper1;
    address public keyper2;
    address public keyper3;

    // Valid 48-byte BLS public key (placeholder)
    bytes public validPubKey = hex"a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4";

    // Sample encrypted payload
    bytes public samplePayload = hex"deadbeefcafebabe";

    function setUp() public {
        // Deploy target contract for execution tests
        targetContract = payable(address(new TestTarget()));

        keyper1 = vm.addr(keyper1Pk);
        keyper2 = vm.addr(keyper2Pk);
        keyper3 = vm.addr(keyper3Pk);

        vm.startPrank(owner);

        // Deploy ThresholdKeyRegistry
        ThresholdKeyRegistry registryImpl = new ThresholdKeyRegistry();
        bytes memory registryInitData = abi.encodeCall(
            ThresholdKeyRegistry.initialize,
            (owner, 2, 1 ether)
        );
        registryProxy = address(new ERC1967Proxy(address(registryImpl), registryInitData));
        keyRegistry = ThresholdKeyRegistry(payable(registryProxy));

        // Deploy EncryptedMempool
        EncryptedMempool mempoolImpl = new EncryptedMempool();
        bytes memory mempoolInitData = abi.encodeCall(
            EncryptedMempool.initialize,
            (owner, registryProxy, sequencer)
        );
        mempoolProxy = address(new ERC1967Proxy(address(mempoolImpl), mempoolInitData));
        mempool = EncryptedMempool(payable(mempoolProxy));

        vm.stopPrank();

        // Setup key registry with valid epoch key
        _setupKeyRegistry();
    }

    // =========================================================================
    // Initialization Tests
    // =========================================================================

    function test_Initialization() public view {
        assertEq(mempool.owner(), owner);
        assertEq(mempool.sequencer(), sequencer);
        assertEq(address(mempool.keyRegistry()), registryProxy);
    }

    // =========================================================================
    // Submit Encrypted Tx Tests
    // =========================================================================

    function test_SubmitEncryptedTx() public {
        vm.deal(user1, 10 ether);

        uint256 gasLimit = 100000;
        uint256 maxFeePerGas = 1 gwei;
        uint256 requiredFee = gasLimit * maxFeePerGas;

        vm.prank(user1);
        bytes32 txId = mempool.submitEncryptedTx{value: requiredFee}(
            samplePayload,
            2, // epoch
            gasLimit,
            maxFeePerGas
        );

        EncryptedMempool.EncryptedTx memory etx = mempool.getEncryptedTx(txId);

        assertEq(etx.sender, user1);
        assertEq(etx.epoch, 2);
        assertEq(etx.gasLimit, gasLimit);
        assertEq(etx.maxFeePerGas, maxFeePerGas);
        assertEq(etx.valueDeposit, 0);
        assertEq(uint256(etx.status), uint256(EncryptedMempool.EncryptedTxStatus.Pending));
        assertEq(mempool.totalSubmitted(), 1);
    }

    function test_SubmitEncryptedTx_RevertsPayloadTooLarge() public {
        vm.deal(user1, 10 ether);

        bytes memory largePayload = new bytes(65537); // MAX_PAYLOAD_SIZE + 1

        vm.prank(user1);
        vm.expectRevert(EncryptedMempool.PayloadTooLarge.selector);
        mempool.submitEncryptedTx{value: 1 ether}(
            largePayload,
            2,
            100000,
            1 gwei
        );
    }

    function test_SubmitEncryptedTx_RevertsInvalidGasLimit_TooLow() public {
        vm.deal(user1, 10 ether);

        vm.prank(user1);
        vm.expectRevert(EncryptedMempool.InvalidGasLimit.selector);
        mempool.submitEncryptedTx{value: 1 ether}(
            samplePayload,
            2,
            20000, // Below MIN_GAS_LIMIT (21000)
            1 gwei
        );
    }

    function test_SubmitEncryptedTx_RevertsInvalidGasLimit_TooHigh() public {
        vm.deal(user1, 100 ether);

        vm.prank(user1);
        vm.expectRevert(EncryptedMempool.InvalidGasLimit.selector);
        mempool.submitEncryptedTx{value: 100 ether}(
            samplePayload,
            2,
            20_000_000, // Above MAX_GAS_LIMIT (10_000_000)
            1 gwei
        );
    }

    function test_SubmitEncryptedTx_RevertsInvalidEpoch() public {
        vm.deal(user1, 10 ether);

        vm.prank(user1);
        vm.expectRevert(EncryptedMempool.InvalidEpoch.selector);
        mempool.submitEncryptedTx{value: 1 ether}(
            samplePayload,
            999, // Invalid epoch
            100000,
            1 gwei
        );
    }

    function test_SubmitEncryptedTx_RevertsInsufficientFee() public {
        vm.deal(user1, 0.01 ether);

        vm.prank(user1);
        vm.expectRevert(EncryptedMempool.InsufficientFee.selector);
        mempool.submitEncryptedTx{value: 0.00001 ether}(
            samplePayload,
            2,
            100000,
            1 gwei // Requires 0.0001 ether
        );
    }

    function test_SubmitMultipleEncryptedTxs() public {
        vm.deal(user1, 10 ether);

        vm.startPrank(user1);

        uint256 gasLimit = 100000;
        uint256 maxFeePerGas = 1 gwei;
        uint256 requiredFee = gasLimit * maxFeePerGas;

        bytes32 txId1 = mempool.submitEncryptedTx{value: requiredFee}(
            hex"11111111",
            2,
            gasLimit,
            maxFeePerGas
        );

        // Need different block to get different txId
        vm.roll(block.number + 1);

        bytes32 txId2 = mempool.submitEncryptedTx{value: requiredFee}(
            hex"22222222",
            2,
            gasLimit,
            maxFeePerGas
        );

        vm.stopPrank();

        assertEq(mempool.totalSubmitted(), 2);
        assertTrue(txId1 != txId2);

        bytes32[] memory userTxs = mempool.getUserPendingTxs(user1);
        assertEq(userTxs.length, 2);
    }

    // =========================================================================
    // Cancel Tx Tests
    // =========================================================================

    function test_CancelEncryptedTx() public {
        bytes32 txId = _submitEncryptedTx(user1);

        uint256 balanceBefore = user1.balance;

        vm.prank(user1);
        mempool.cancelEncryptedTx(txId);

        EncryptedMempool.EncryptedTx memory etx = mempool.getEncryptedTx(txId);
        assertEq(uint256(etx.status), uint256(EncryptedMempool.EncryptedTxStatus.Expired));

        // User should get refund
        assertGt(user1.balance, balanceBefore);
    }

    function test_CancelEncryptedTx_RevertsNotOwner() public {
        bytes32 txId = _submitEncryptedTx(user1);

        vm.prank(user2);
        vm.expectRevert(EncryptedMempool.TxNotFound.selector);
        mempool.cancelEncryptedTx(txId);
    }

    function test_CancelEncryptedTx_RevertsNotPending() public {
        bytes32 txId = _submitEncryptedTx(user1);

        // Cancel once
        vm.prank(user1);
        mempool.cancelEncryptedTx(txId);

        // Try to cancel again
        vm.prank(user1);
        vm.expectRevert(EncryptedMempool.TxNotFound.selector);
        mempool.cancelEncryptedTx(txId);
    }

    // =========================================================================
    // Commit Ordering Tests
    // =========================================================================

    function test_CommitOrdering() public {
        bytes32 txId1 = _submitEncryptedTx(user1);
        bytes32 txId2 = _submitEncryptedTx(user2);

        bytes32[] memory txIds = new bytes32[](2);
        txIds[0] = txId1;
        txIds[1] = txId2;

        bytes32 batchId = keccak256("batch1");
        bytes32 orderingRoot = keccak256(abi.encodePacked(txIds));

        vm.prank(sequencer);
        mempool.commitOrdering(batchId, txIds, orderingRoot, "sig");

        // Check transactions are now ordered
        EncryptedMempool.EncryptedTx memory etx1 = mempool.getEncryptedTx(txId1);
        EncryptedMempool.EncryptedTx memory etx2 = mempool.getEncryptedTx(txId2);

        assertEq(uint256(etx1.status), uint256(EncryptedMempool.EncryptedTxStatus.Ordered));
        assertEq(uint256(etx2.status), uint256(EncryptedMempool.EncryptedTxStatus.Ordered));
        assertEq(etx1.orderPosition, 0);
        assertEq(etx2.orderPosition, 1);
    }

    function test_CommitOrdering_RevertsNotSequencer() public {
        bytes32 txId = _submitEncryptedTx(user1);

        bytes32[] memory txIds = new bytes32[](1);
        txIds[0] = txId;

        vm.prank(user1);
        vm.expectRevert(EncryptedMempool.NotSequencer.selector);
        mempool.commitOrdering(
            keccak256("batch"),
            txIds,
            keccak256(abi.encodePacked(txIds)),
            "sig"
        );
    }

    // =========================================================================
    // Submit Decryption Tests
    // =========================================================================

    function test_SubmitDecryption() public {
        bytes32 txId = _submitAndOrderTx(user1);
        EncryptedMempool.EncryptedTx memory etx = mempool.getEncryptedTx(txId);
        bytes memory data = abi.encodeCall(TestTarget.setValue, (42));
        bytes memory proof = _buildProof(
            etx.payloadHash,
            targetContract,
            data,
            0,
            etx.epoch,
            _defaultSignerKeys()
        );

        vm.prank(sequencer);
        mempool.submitDecryption(
            txId,
            targetContract,
            data,
            0,
            proof
        );

        etx = mempool.getEncryptedTx(txId);
        assertEq(uint256(etx.status), uint256(EncryptedMempool.EncryptedTxStatus.Decrypted));

        EncryptedMempool.DecryptedTx memory dtx = mempool.getDecryptedTx(txId);
        assertEq(dtx.to, targetContract);
        assertFalse(dtx.executed);
    }

    function test_SubmitDecryption_RevertsTxNotOrdered() public {
        bytes32 txId = _submitEncryptedTx(user1);
        EncryptedMempool.EncryptedTx memory etx = mempool.getEncryptedTx(txId);
        bytes memory proof = _buildProof(
            etx.payloadHash,
            targetContract,
            bytes(""),
            0,
            etx.epoch,
            _defaultSignerKeys()
        );

        vm.prank(sequencer);
        vm.expectRevert(EncryptedMempool.TxNotOrdered.selector);
        mempool.submitDecryption(
            txId,
            targetContract,
            bytes(""),
            0,
            proof
        );
    }

    function test_SubmitDecryption_RevertsDecryptionFailed() public {
        bytes32 txId = _submitAndOrderTx(user1);

        bytes memory shortProof = new bytes(10); // Too short

        vm.prank(sequencer);
        vm.expectRevert(EncryptedMempool.DecryptionFailed.selector);
        mempool.submitDecryption(
            txId,
            targetContract,
            bytes(""),
            0,
            shortProof
        );
    }

    function test_SubmitDecryption_RevertsValueExceedsDeposit() public {
        bytes32 txId = _submitEncryptedTxWithDeposit(user1, 1 ether);

        bytes32[] memory txIds = new bytes32[](1);
        txIds[0] = txId;

        vm.prank(sequencer);
        mempool.commitOrdering(
            keccak256(abi.encodePacked("batch", txId)),
            txIds,
            keccak256(abi.encodePacked(txIds)),
            "sig"
        );

        vm.prank(sequencer);
        vm.expectRevert(EncryptedMempool.ValueExceedsDeposit.selector);
        mempool.submitDecryption(
            txId,
            targetContract,
            bytes(""),
            2 ether,
            bytes("")
        );
    }

    // =========================================================================
    // Execute Decrypted Tx Tests
    // =========================================================================

    function test_ExecuteDecryptedTx() public {
        bytes32 txId = _submitOrderAndDecrypt(user1);

        mempool.executeDecryptedTx(txId);

        EncryptedMempool.EncryptedTx memory etx = mempool.getEncryptedTx(txId);
        assertEq(uint256(etx.status), uint256(EncryptedMempool.EncryptedTxStatus.Executed));

        EncryptedMempool.DecryptedTx memory dtx = mempool.getDecryptedTx(txId);
        assertTrue(dtx.executed);
        assertTrue(dtx.success);

        // Verify target was called
        assertEq(TestTarget(targetContract).value(), 42);

        assertEq(mempool.totalExecuted(), 1);
    }

    function test_ExecuteDecryptedTx_FailedExecution() public {
        bytes32 txId = _submitAndOrderTx(user1);
        EncryptedMempool.EncryptedTx memory etx = mempool.getEncryptedTx(txId);
        bytes memory data = abi.encodeCall(TestTarget.revertingCall, ());
        bytes memory proof = _buildProof(
            etx.payloadHash,
            targetContract,
            data,
            0,
            etx.epoch,
            _defaultSignerKeys()
        );

        // Submit decryption that will fail (call to revert)
        vm.prank(sequencer);
        mempool.submitDecryption(
            txId,
            targetContract,
            data,
            0,
            proof
        );

        mempool.executeDecryptedTx(txId);

        EncryptedMempool.EncryptedTx memory etx = mempool.getEncryptedTx(txId);
        assertEq(uint256(etx.status), uint256(EncryptedMempool.EncryptedTxStatus.Failed));

        EncryptedMempool.DecryptedTx memory dtx = mempool.getDecryptedTx(txId);
        assertTrue(dtx.executed);
        assertFalse(dtx.success);

        assertEq(mempool.totalFailed(), 1);
    }

    function test_ExecuteDecryptedTx_RevertsTxNotDecrypted() public {
        bytes32 txId = _submitAndOrderTx(user1);

        vm.expectRevert(EncryptedMempool.TxNotDecrypted.selector);
        mempool.executeDecryptedTx(txId);
    }

    function test_ExecuteDecryptedTx_RevertsAlreadyExecuted() public {
        bytes32 txId = _submitOrderAndDecrypt(user1);

        mempool.executeDecryptedTx(txId);

        vm.expectRevert(EncryptedMempool.TxAlreadyExecuted.selector);
        mempool.executeDecryptedTx(txId);
    }

    // =========================================================================
    // Mark Expired Tests
    // =========================================================================

    function test_MarkExpired() public {
        bytes32 txId = _submitEncryptedTx(user1);

        // Advance past timeout
        vm.roll(block.number + 51); // DECRYPTION_TIMEOUT + 1

        bytes32[] memory txIds = new bytes32[](1);
        txIds[0] = txId;

        uint256 balanceBefore = user1.balance;

        mempool.markExpired(txIds);

        EncryptedMempool.EncryptedTx memory etx = mempool.getEncryptedTx(txId);
        assertEq(uint256(etx.status), uint256(EncryptedMempool.EncryptedTxStatus.Expired));
        assertEq(mempool.totalExpired(), 1);

        // User should get refund
        assertGt(user1.balance, balanceBefore);
    }

    function test_MarkExpired_NotExpiredYet() public {
        bytes32 txId = _submitEncryptedTx(user1);

        bytes32[] memory txIds = new bytes32[](1);
        txIds[0] = txId;

        mempool.markExpired(txIds);

        EncryptedMempool.EncryptedTx memory etx = mempool.getEncryptedTx(txId);
        assertEq(uint256(etx.status), uint256(EncryptedMempool.EncryptedTxStatus.Pending));
        assertEq(mempool.totalExpired(), 0);
    }

    // =========================================================================
    // Admin Tests
    // =========================================================================

    function test_SetSequencer() public {
        address newSequencer = address(0x999);

        vm.prank(owner);
        mempool.setSequencer(newSequencer);

        assertEq(mempool.sequencer(), newSequencer);
    }

    function test_SetSequencer_RevertsNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        mempool.setSequencer(address(0x999));
    }

    function test_SetKeyRegistry() public {
        address newRegistry = address(0x888);

        vm.prank(owner);
        mempool.setKeyRegistry(newRegistry);

        assertEq(address(mempool.keyRegistry()), newRegistry);
    }

    // =========================================================================
    // Query Tests
    // =========================================================================

    function test_GetStats() public {
        bytes32 txId1 = _submitOrderAndDecrypt(user1);
        bytes32 txId2 = _submitEncryptedTx(user2);

        mempool.executeDecryptedTx(txId1);

        vm.roll(block.number + 51);
        bytes32[] memory expiredTxs = new bytes32[](1);
        expiredTxs[0] = txId2;
        mempool.markExpired(expiredTxs);

        (uint256 submitted, uint256 executed, uint256 failed, uint256 expired) = mempool.getStats();

        assertEq(submitted, 2);
        assertEq(executed, 1);
        assertEq(failed, 0);
        assertEq(expired, 1);
    }

    function test_GetPendingQueueLength() public {
        _submitEncryptedTx(user1);
        _submitEncryptedTx(user2);

        assertEq(mempool.getPendingQueueLength(), 2);
    }

    // =========================================================================
    // Helper Functions
    // =========================================================================

    function _setupKeyRegistry() internal {
        // Register keypers
        vm.deal(keyper1, 2 ether);
        vm.deal(keyper2, 2 ether);
        vm.deal(keyper3, 2 ether);

        vm.prank(keyper1);
        keyRegistry.registerKeyper{value: 1 ether}(validPubKey, "http://keyper1:8080");

        vm.prank(keyper2);
        keyRegistry.registerKeyper{value: 1 ether}(validPubKey, "http://keyper2:8080");

        vm.prank(keyper3);
        keyRegistry.registerKeyper{value: 1 ether}(validPubKey, "http://keyper3:8080");

        // Start and complete DKG
        vm.prank(owner);
        keyRegistry.startDKG();

        vm.prank(keyper1);
        keyRegistry.registerForDKG();

        vm.prank(keyper2);
        keyRegistry.registerForDKG();

        vm.prank(keyper1);
        keyRegistry.submitDealing(keccak256("dealing1"));

        vm.prank(keyper2);
        keyRegistry.submitDealing(keccak256("dealing2"));

        vm.prank(owner);
        keyRegistry.finalizeDKG(validPubKey, keccak256("commitment"));
    }

    function _submitEncryptedTx(address user) internal returns (bytes32) {
        vm.deal(user, 10 ether);

        vm.roll(block.number + 1); // Ensure unique txId

        uint256 gasDeposit = 100000 * 1 gwei;

        vm.prank(user);
        return mempool.submitEncryptedTx{value: gasDeposit}(
            samplePayload,
            2, // Current epoch after DKG
            100000,
            1 gwei
        );
    }

    function _submitEncryptedTxWithDeposit(address user, uint256 valueDeposit) internal returns (bytes32) {
        vm.deal(user, 10 ether);

        vm.roll(block.number + 1);

        uint256 gasDeposit = 100000 * 1 gwei;

        vm.prank(user);
        return mempool.submitEncryptedTx{value: gasDeposit + valueDeposit}(
            samplePayload,
            2,
            100000,
            1 gwei
        );
    }

    function _submitAndOrderTx(address user) internal returns (bytes32) {
        bytes32 txId = _submitEncryptedTx(user);

        bytes32[] memory txIds = new bytes32[](1);
        txIds[0] = txId;

        vm.prank(sequencer);
        mempool.commitOrdering(
            keccak256(abi.encodePacked("batch", txId)),
            txIds,
            keccak256(abi.encodePacked(txIds)),
            "sig"
        );

        return txId;
    }

    function _submitOrderAndDecrypt(address user) internal returns (bytes32) {
        bytes32 txId = _submitAndOrderTx(user);

        EncryptedMempool.EncryptedTx memory etx = mempool.getEncryptedTx(txId);
        bytes memory data = abi.encodeCall(TestTarget.setValue, (42));
        bytes memory proof = _buildProof(
            etx.payloadHash,
            targetContract,
            data,
            0,
            etx.epoch,
            _defaultSignerKeys()
        );

        vm.prank(sequencer);
        mempool.submitDecryption(
            txId,
            targetContract,
            data,
            0,
            proof
        );

        return txId;
    }

    function _buildProof(
        bytes32 payloadHash,
        address to,
        bytes memory data,
        uint256 value,
        uint256 epoch,
        uint256[] memory signerKeys
    ) internal returns (bytes memory) {
        bytes32 commitment = keccak256(abi.encodePacked(payloadHash, to, data, value));
        (bytes memory signatures, address[] memory signers) = _buildSignatures(commitment, signerKeys);
        return abi.encode(signatures, commitment, epoch, signers);
    }

    function _buildSignatures(
        bytes32 commitment,
        uint256[] memory signerKeys
    ) internal returns (bytes memory signatures, address[] memory signers) {
        bytes32 digest = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", commitment)
        );

        signatures = new bytes(0);
        signers = new address[](signerKeys.length);

        for (uint256 i = 0; i < signerKeys.length; i++) {
            signers[i] = vm.addr(signerKeys[i]);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKeys[i], digest);
            bytes memory sig = bytes.concat(r, s, bytes1(v));
            signatures = bytes.concat(signatures, sig);
        }
    }

    function _defaultSignerKeys() internal view returns (uint256[] memory keys) {
        keys = new uint256[](2);
        keys[0] = keyper1Pk;
        keys[1] = keyper2Pk;
    }
}

/**
 * @notice Simple target contract for execution tests
 */
contract TestTarget {
    uint256 public value;

    function setValue(uint256 _value) external {
        value = _value;
    }

    function revertingCall() external pure {
        revert("Intentional revert");
    }

    receive() external payable {}
}
