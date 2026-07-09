// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../commerce/SetPaymentBatch.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/mocks/ERC1271WalletMock.sol";

/// @dev Minimal ERC20 mock for testing payment settlement
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(
        address to,
        uint256 amount
    ) external {
        _mint(to, amount);
    }
}

/// @dev ERC20 that returns false on transferFrom instead of reverting
contract MockERC20ReturnsFalse is ERC20 {
    bool public shouldFail;

    constructor() ERC20("FailToken", "FAIL") { }

    function mint(
        address to,
        uint256 amount
    ) external {
        _mint(to, amount);
    }

    function setShouldFail(
        bool _fail
    ) external {
        shouldFail = _fail;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        if (shouldFail) {
            return false;
        }
        return super.transferFrom(from, to, amount);
    }
}

contract SetPaymentBatchTest is Test {
    SetPaymentBatch public paymentBatch;
    SetPaymentBatch public paymentBatchImpl;

    MockERC20 public usdc;
    MockERC20 public ssUsd;
    MockERC20 public usdt;

    address public owner = address(0x1);
    address public sequencer = address(0x2);
    address public unauthorized = address(0x3);
    // Payers are derived from known private keys so they can produce real
    // EIP-712 authorizations. Payees/others stay as plain addresses.
    uint256 internal constant PAYER1_PK = 0xA11CE;
    uint256 internal constant PAYER2_PK = 0xB0B;
    address public payer1;
    address public payer2;
    address public payee1 = address(0x6);
    address public payee2 = address(0x7);
    address public registryAddr = address(0x8);

    /// @dev payer address => signing private key (0 if the payer cannot sign)
    mapping(address => uint256) internal payerKey;

    // Events (must match contract definitions)
    event SequencerAuthorized(address indexed sequencer, bool authorized);

    event AssetConfigured(
        address indexed token,
        bool enabled,
        uint256 minAmount,
        uint256 maxAmount,
        uint256 dailyLimit
    );

    event BatchSubmitted(
        bytes32 indexed batchId,
        bytes32 merkleRoot,
        uint32 paymentCount,
        uint256 totalAmount,
        address indexed token
    );

    event BatchSettled(
        bytes32 indexed batchId, uint32 paymentsSettled, uint256 totalAmount, uint256 gasUsed
    );

    event PaymentSettled(
        bytes32 indexed batchId,
        bytes32 indexed intentId,
        address indexed payer,
        address payee,
        uint256 amount,
        address token
    );

    event PaymentFailed(
        bytes32 indexed batchId, bytes32 indexed intentId, address indexed payer, string reason
    );

    event ContractUpgraded(address indexed newImplementation, address indexed authorizer);

    function setUp() public {
        // Derive payer addresses from known keys and register them for signing
        payer1 = vm.addr(PAYER1_PK);
        payer2 = vm.addr(PAYER2_PK);
        payerKey[payer1] = PAYER1_PK;
        payerKey[payer2] = PAYER2_PK;

        // Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        ssUsd = new MockERC20("ssUSD", "ssUSD", 6);
        usdt = new MockERC20("Tether", "USDT", 6);

        // Deploy implementation
        paymentBatchImpl = new SetPaymentBatch();

        // Deploy proxy
        bytes memory initData = abi.encodeCall(
            SetPaymentBatch.initialize,
            (owner, sequencer, address(usdc), address(ssUsd), registryAddr)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(paymentBatchImpl), initData);
        paymentBatch = SetPaymentBatch(address(proxy));

        // Fund payers with tokens and set approvals
        usdc.mint(payer1, 1_000_000e6);
        usdc.mint(payer2, 1_000_000e6);
        ssUsd.mint(payer1, 1_000_000e6);
        ssUsd.mint(payer2, 1_000_000e6);

        vm.prank(payer1);
        usdc.approve(address(paymentBatch), type(uint256).max);
        vm.prank(payer2);
        usdc.approve(address(paymentBatch), type(uint256).max);
        vm.prank(payer1);
        ssUsd.approve(address(paymentBatch), type(uint256).max);
        vm.prank(payer2);
        ssUsd.approve(address(paymentBatch), type(uint256).max);
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _makePayment(
        bytes32 intentId,
        address payer,
        address payee,
        uint256 amount,
        address token,
        uint64 nonce,
        uint64 validUntil
    ) internal view returns (SetPaymentBatch.PaymentIntent memory p) {
        p = SetPaymentBatch.PaymentIntent({
            intentId: intentId,
            payer: payer,
            payee: payee,
            amount: amount,
            token: token,
            nonce: nonce,
            validAfter: 0,
            validUntil: validUntil,
            signingHash: keccak256(abi.encodePacked(intentId, payer, payee, amount)),
            authorization: bytes("")
        });
        // Auto-sign a valid EIP-712 authorization if the payer has a known key.
        uint256 pk = payerKey[payer];
        if (pk != 0) {
            p.authorization = _signAuthorization(p, pk);
        }
    }

    /// @dev Produce an EIP-712 signature over the payment using the given key.
    function _signAuthorization(
        SetPaymentBatch.PaymentIntent memory p,
        uint256 pk
    ) internal view returns (bytes memory) {
        bytes32 digest = paymentBatch.hashPaymentAuthorization(p);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _makeDefaultPayment() internal view returns (SetPaymentBatch.PaymentIntent memory) {
        return _makePayment(
            keccak256("intent1"),
            payer1,
            payee1,
            100e6, // 100 USDC
            address(usdc),
            1,
            uint64(block.timestamp + 1 hours)
        );
    }

    function _makePaymentArray(
        SetPaymentBatch.PaymentIntent memory payment
    ) internal pure returns (SetPaymentBatch.PaymentIntent[] memory) {
        SetPaymentBatch.PaymentIntent[] memory payments = new SetPaymentBatch.PaymentIntent[](1);
        payments[0] = payment;
        return payments;
    }

    function _settleSinglePayment(
        bytes32 batchId,
        SetPaymentBatch.PaymentIntent memory payment
    ) internal {
        SetPaymentBatch.PaymentIntent[] memory payments = _makePaymentArray(payment);
        vm.prank(sequencer);
        paymentBatch.settleBatch(
            batchId, keccak256("merkle_root"), keccak256("tenant_store"), 1, 1, payments
        );
    }

    // =========================================================================
    // 1. Initialization Tests
    // =========================================================================

    function test_Initialize() public view {
        assertEq(paymentBatch.owner(), owner);
        assertTrue(paymentBatch.authorizedSequencers(sequencer));
        assertEq(paymentBatch.sequencerCount(), 1);
        assertEq(paymentBatch.usdcToken(), address(usdc));
        assertEq(paymentBatch.ssUsdToken(), address(ssUsd));
        assertEq(paymentBatch.registry(), registryAddr);
    }

    function test_Initialize_DefaultAssetConfigs() public view {
        SetPaymentBatch.AssetConfig memory usdcConfig = paymentBatch.getAssetConfig(address(usdc));
        assertTrue(usdcConfig.enabled);
        assertEq(usdcConfig.minAmount, 1e4);
        assertEq(usdcConfig.maxAmount, 1e12);
        assertEq(usdcConfig.dailyLimit, 1e14);
        assertEq(usdcConfig.dailyVolume, 0);

        SetPaymentBatch.AssetConfig memory ssUsdConfig = paymentBatch.getAssetConfig(address(ssUsd));
        assertTrue(ssUsdConfig.enabled);
        assertEq(ssUsdConfig.minAmount, 1e4);
        assertEq(ssUsdConfig.maxAmount, 1e12);
        assertEq(ssUsdConfig.dailyLimit, 1e14);
    }

    function test_Initialize_WithZeroSequencer() public {
        SetPaymentBatch impl = new SetPaymentBatch();
        bytes memory initData = abi.encodeCall(
            SetPaymentBatch.initialize,
            (owner, address(0), address(usdc), address(ssUsd), registryAddr)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        SetPaymentBatch pb = SetPaymentBatch(address(proxy));

        assertFalse(pb.authorizedSequencers(address(0)));
        assertEq(pb.sequencerCount(), 0);
    }

    function test_Initialize_WithZeroTokens() public {
        SetPaymentBatch impl = new SetPaymentBatch();
        bytes memory initData = abi.encodeCall(
            SetPaymentBatch.initialize, (owner, sequencer, address(0), address(0), registryAddr)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        SetPaymentBatch pb = SetPaymentBatch(address(proxy));

        SetPaymentBatch.AssetConfig memory config = pb.getAssetConfig(address(0));
        assertFalse(config.enabled);
    }

    function test_CannotReinitialize() public {
        vm.expectRevert();
        paymentBatch.initialize(owner, sequencer, address(usdc), address(ssUsd), registryAddr);
    }

    // =========================================================================
    // 2. Authorization Tests
    // =========================================================================

    function test_SetSequencerAuthorization_Authorize() public {
        address newSequencer = address(0x10);

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit SequencerAuthorized(newSequencer, true);
        paymentBatch.setSequencerAuthorization(newSequencer, true);

        assertTrue(paymentBatch.authorizedSequencers(newSequencer));
        assertEq(paymentBatch.sequencerCount(), 2);
    }

    function test_SetSequencerAuthorization_Revoke() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit SequencerAuthorized(sequencer, false);
        paymentBatch.setSequencerAuthorization(sequencer, false);

        assertFalse(paymentBatch.authorizedSequencers(sequencer));
        assertEq(paymentBatch.sequencerCount(), 0);
    }

    function test_SetSequencerAuthorization_AuthorizeTwice_NoDoubleCount() public {
        vm.startPrank(owner);
        paymentBatch.setSequencerAuthorization(sequencer, true); // already authorized
        vm.stopPrank();

        assertEq(paymentBatch.sequencerCount(), 1); // should not increment
    }

    function test_SetSequencerAuthorization_RevokeTwice_NoUnderflow() public {
        vm.startPrank(owner);
        paymentBatch.setSequencerAuthorization(sequencer, false);
        paymentBatch.setSequencerAuthorization(sequencer, false); // revoke again
        vm.stopPrank();

        assertEq(paymentBatch.sequencerCount(), 0); // should not underflow
    }

    function test_SetSequencerAuthorization_NotOwner() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        paymentBatch.setSequencerAuthorization(address(0x10), true);
    }

    function test_SetSequencerAuthorization_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(SetPaymentBatch.InvalidAddress.selector);
        paymentBatch.setSequencerAuthorization(address(0), true);
    }

    // =========================================================================
    // 3. Asset Configuration Tests
    // =========================================================================

    function test_ConfigureAsset_NewAsset() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit AssetConfigured(address(usdt), true, 1e4, 1e10, 1e13);
        paymentBatch.configureAsset(address(usdt), true, 1e4, 1e10, 1e13);

        SetPaymentBatch.AssetConfig memory config = paymentBatch.getAssetConfig(address(usdt));
        assertTrue(config.enabled);
        assertEq(config.minAmount, 1e4);
        assertEq(config.maxAmount, 1e10);
        assertEq(config.dailyLimit, 1e13);
    }

    function test_ConfigureAsset_UpdateExisting() public {
        vm.prank(owner);
        paymentBatch.configureAsset(address(usdc), true, 5e4, 5e11, 5e13);

        SetPaymentBatch.AssetConfig memory config = paymentBatch.getAssetConfig(address(usdc));
        assertEq(config.minAmount, 5e4);
        assertEq(config.maxAmount, 5e11);
        assertEq(config.dailyLimit, 5e13);
    }

    function test_ConfigureAsset_DisableAsset() public {
        vm.prank(owner);
        paymentBatch.configureAsset(address(usdc), false, 0, 0, 0);

        SetPaymentBatch.AssetConfig memory config = paymentBatch.getAssetConfig(address(usdc));
        assertFalse(config.enabled);
    }

    function test_ConfigureAsset_PreservesDailyVolume() public {
        // First settle a payment to accumulate volume
        SetPaymentBatch.PaymentIntent memory payment = _makeDefaultPayment();
        _settleSinglePayment(keccak256("batch1"), payment);

        SetPaymentBatch.AssetConfig memory configBefore = paymentBatch.getAssetConfig(address(usdc));
        uint256 volumeBefore = configBefore.dailyVolume;
        assertGt(volumeBefore, 0);

        // Reconfigure the asset
        vm.prank(owner);
        paymentBatch.configureAsset(address(usdc), true, 1e3, 1e13, 1e15);

        // Volume should be preserved
        SetPaymentBatch.AssetConfig memory configAfter = paymentBatch.getAssetConfig(address(usdc));
        assertEq(configAfter.dailyVolume, volumeBefore);
    }

    function test_ConfigureAsset_NotOwner() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        paymentBatch.configureAsset(address(usdt), true, 1e4, 1e10, 1e13);
    }

    function test_SetRegistry() public {
        address newRegistry = address(0x99);

        vm.prank(owner);
        paymentBatch.setRegistry(newRegistry);

        assertEq(paymentBatch.registry(), newRegistry);
    }

    function test_SetRegistry_NotOwner() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        paymentBatch.setRegistry(address(0x99));
    }

    // =========================================================================
    // 4. Payment Submission Tests (settleBatch validation)
    // =========================================================================

    function test_SettleBatch_SinglePayment() public {
        SetPaymentBatch.PaymentIntent memory payment = _makeDefaultPayment();
        bytes32 batchId = keccak256("batch1");

        uint256 payerBalanceBefore = usdc.balanceOf(payer1);
        uint256 payeeBalanceBefore = usdc.balanceOf(payee1);

        _settleSinglePayment(batchId, payment);

        // Verify token transfer
        assertEq(usdc.balanceOf(payer1), payerBalanceBefore - 100e6);
        assertEq(usdc.balanceOf(payee1), payeeBalanceBefore + 100e6);

        // Verify batch recorded
        SetPaymentBatch.BatchSettlement memory batch = paymentBatch.getBatch(batchId);
        assertGt(batch.settledAt, 0);
        assertEq(batch.paymentCount, 1);
        assertEq(batch.totalAmount, 100e6);
        assertEq(batch.token, address(usdc));
        assertEq(batch.settledAt, uint64(block.timestamp));

        // Verify stats
    }

    function test_SettleBatch_NotSequencer() public {
        SetPaymentBatch.PaymentIntent[] memory payments = _makePaymentArray(_makeDefaultPayment());

        vm.prank(unauthorized);
        vm.expectRevert(SetPaymentBatch.NotAuthorizedSequencer.selector);
        paymentBatch.settleBatch(
            keccak256("batch1"), keccak256("root"), keccak256("tenant"), 1, 1, payments
        );
    }

    function test_SettleBatch_EmptyBatch() public {
        SetPaymentBatch.PaymentIntent[] memory payments = new SetPaymentBatch.PaymentIntent[](0);

        vm.prank(sequencer);
        vm.expectRevert(SetPaymentBatch.EmptyBatch.selector);
        paymentBatch.settleBatch(
            keccak256("batch1"), keccak256("root"), keccak256("tenant"), 1, 1, payments
        );
    }

    function test_SettleBatch_AlreadySettled() public {
        bytes32 batchId = keccak256("batch1");

        // Settle first time
        _settleSinglePayment(batchId, _makeDefaultPayment());

        // Try to settle again with same batchId
        SetPaymentBatch.PaymentIntent memory payment2 = _makePayment(
            keccak256("intent2"),
            payer1,
            payee1,
            50e6,
            address(usdc),
            2,
            uint64(block.timestamp + 1 hours)
        );
        SetPaymentBatch.PaymentIntent[] memory payments = _makePaymentArray(payment2);

        vm.prank(sequencer);
        vm.expectRevert(SetPaymentBatch.BatchAlreadySettled.selector);
        paymentBatch.settleBatch(batchId, keccak256("root2"), keccak256("tenant"), 2, 2, payments);
    }

    function test_SettleBatch_InvalidMerkleRoot() public {
        SetPaymentBatch.PaymentIntent[] memory payments = _makePaymentArray(_makeDefaultPayment());

        vm.prank(sequencer);
        vm.expectRevert(SetPaymentBatch.InvalidMerkleRoot.selector);
        paymentBatch.settleBatch(
            keccak256("batch1"),
            bytes32(0), // invalid merkle root
            keccak256("tenant"),
            1,
            1,
            payments
        );
    }

    function test_SettleBatch_WhenPaused() public {
        vm.prank(owner);
        paymentBatch.pause();

        SetPaymentBatch.PaymentIntent[] memory payments = _makePaymentArray(_makeDefaultPayment());

        vm.prank(sequencer);
        vm.expectRevert();
        paymentBatch.settleBatch(
            keccak256("batch1"), keccak256("root"), keccak256("tenant"), 1, 1, payments
        );
    }

    function test_SettleBatch_EmitsEvents() public {
        SetPaymentBatch.PaymentIntent memory payment = _makeDefaultPayment();
        SetPaymentBatch.PaymentIntent[] memory payments = _makePaymentArray(payment);
        bytes32 batchId = keccak256("batch1");
        bytes32 merkleRoot = keccak256("root");

        // Expect PaymentSettled event
        vm.expectEmit(true, true, true, true);
        emit PaymentSettled(batchId, payment.intentId, payer1, payee1, 100e6, address(usdc));

        // Expect BatchSubmitted event
        vm.expectEmit(true, false, false, true);
        emit BatchSubmitted(batchId, merkleRoot, 1, 100e6, address(usdc));

        vm.prank(sequencer);
        paymentBatch.settleBatch(batchId, merkleRoot, keccak256("tenant"), 1, 1, payments);
    }

    // =========================================================================
    // 5. Payment Settlement Tests (individual payment validation)
    // =========================================================================

    function test_Settlement_ExpiredPayment() public {
        // Create a payment that expires before settlement
        SetPaymentBatch.PaymentIntent memory payment = _makePayment(
            keccak256("expired_intent"),
            payer1,
            payee1,
            100e6,
            address(usdc),
            1,
            uint64(block.timestamp - 1) // already expired
        );
        bytes32 batchId = keccak256("batch_expired");

        // Settlement proceeds but payment fails with PaymentFailed event
        SetPaymentBatch.PaymentIntent[] memory payments = _makePaymentArray(payment);

        vm.prank(sequencer);
        vm.expectEmit(true, true, true, true);
        emit PaymentFailed(batchId, payment.intentId, payer1, "Payment expired");
        paymentBatch.settleBatch(batchId, keccak256("root"), keccak256("tenant"), 1, 1, payments);

        // Batch was created but with 0 successful payments
        SetPaymentBatch.BatchSettlement memory batch = paymentBatch.getBatch(batchId);
        assertGt(batch.settledAt, 0);
        assertEq(batch.paymentCount, 0);
        assertEq(batch.totalAmount, 0);
    }

    function test_Settlement_DuplicateIntentId() public {
        bytes32 intentId = keccak256("intent1");

        // Settle first time
        SetPaymentBatch.PaymentIntent memory payment1 = _makePayment(
            intentId, payer1, payee1, 100e6, address(usdc), 1, uint64(block.timestamp + 1 hours)
        );
        _settleSinglePayment(keccak256("batch1"), payment1);

        // Try to settle same intentId in a different batch
        SetPaymentBatch.PaymentIntent memory payment2 = _makePayment(
            intentId, payer1, payee1, 100e6, address(usdc), 2, uint64(block.timestamp + 1 hours)
        );
        bytes32 batchId2 = keccak256("batch2");
        SetPaymentBatch.PaymentIntent[] memory payments = _makePaymentArray(payment2);

        vm.prank(sequencer);
        vm.expectEmit(true, true, true, true);
        emit PaymentFailed(batchId2, intentId, payer1, "Already settled");
        paymentBatch.settleBatch(batchId2, keccak256("root2"), keccak256("tenant"), 2, 2, payments);

        SetPaymentBatch.BatchSettlement memory batch = paymentBatch.getBatch(batchId2);
        assertEq(batch.paymentCount, 0);
    }

    function test_Settlement_NonceAlreadyUsed() public {
        uint64 nonce = 42;

        // Settle first payment with nonce
        SetPaymentBatch.PaymentIntent memory payment1 = _makePayment(
            keccak256("intent1"),
            payer1,
            payee1,
            100e6,
            address(usdc),
            nonce,
            uint64(block.timestamp + 1 hours)
        );
        _settleSinglePayment(keccak256("batch1"), payment1);

        // Try to use same nonce for same payer
        SetPaymentBatch.PaymentIntent memory payment2 = _makePayment(
            keccak256("intent2"),
            payer1,
            payee2,
            50e6,
            address(usdc),
            nonce,
            uint64(block.timestamp + 1 hours)
        );
        bytes32 batchId2 = keccak256("batch2");
        SetPaymentBatch.PaymentIntent[] memory payments = _makePaymentArray(payment2);

        vm.prank(sequencer);
        vm.expectEmit(true, true, true, true);
        emit PaymentFailed(batchId2, keccak256("intent2"), payer1, "Nonce already used");
        paymentBatch.settleBatch(batchId2, keccak256("root2"), keccak256("tenant"), 2, 2, payments);
    }

    function test_Settlement_AssetNotEnabled() public {
        SetPaymentBatch.PaymentIntent memory payment = _makePayment(
            keccak256("intent1"),
            payer1,
            payee1,
            100e6,
            address(usdt),
            1,
            uint64(block.timestamp + 1 hours)
        );
        bytes32 batchId = keccak256("batch1");
        SetPaymentBatch.PaymentIntent[] memory payments = _makePaymentArray(payment);

        vm.prank(sequencer);
        vm.expectEmit(true, true, true, true);
        emit PaymentFailed(batchId, payment.intentId, payer1, "Asset not enabled");
        paymentBatch.settleBatch(batchId, keccak256("root"), keccak256("tenant"), 1, 1, payments);
    }

    function test_Settlement_AmountBelowMinimum() public {
        // Default min is 1e4 (0.01 USDC)
        SetPaymentBatch.PaymentIntent memory payment = _makePayment(
            keccak256("intent1"),
            payer1,
            payee1,
            1e3,
            address(usdc),
            1,
            uint64(block.timestamp + 1 hours)
        );
        bytes32 batchId = keccak256("batch1");
        SetPaymentBatch.PaymentIntent[] memory payments = _makePaymentArray(payment);

        vm.prank(sequencer);
        vm.expectEmit(true, true, true, true);
        emit PaymentFailed(batchId, payment.intentId, payer1, "Amount below minimum");
        paymentBatch.settleBatch(batchId, keccak256("root"), keccak256("tenant"), 1, 1, payments);
    }

    function test_Settlement_AmountAboveMaximum() public {
        // Default max is 1e12 (1M USDC)
        uint256 overMax = 1e12 + 1;
        usdc.mint(payer1, overMax); // make sure payer has enough

        SetPaymentBatch.PaymentIntent memory payment = _makePayment(
            keccak256("intent1"),
            payer1,
            payee1,
            overMax,
            address(usdc),
            1,
            uint64(block.timestamp + 1 hours)
        );
        bytes32 batchId = keccak256("batch1");
        SetPaymentBatch.PaymentIntent[] memory payments = _makePaymentArray(payment);

        vm.prank(sequencer);
        vm.expectEmit(true, true, true, true);
        emit PaymentFailed(batchId, payment.intentId, payer1, "Amount above maximum");
        paymentBatch.settleBatch(batchId, keccak256("root"), keccak256("tenant"), 1, 1, payments);
    }

    function test_Settlement_InsufficientBalance() public {
        // Keyed payer so authorization is valid and we reach the balance check.
        uint256 poorPk = 0xB16B00B5;
        address poorPayer = vm.addr(poorPk);
        payerKey[poorPayer] = poorPk;
        // Give payer approval but no balance
        vm.prank(poorPayer);
        usdc.approve(address(paymentBatch), type(uint256).max);

        SetPaymentBatch.PaymentIntent memory payment = _makePayment(
            keccak256("intent1"),
            poorPayer,
            payee1,
            100e6,
            address(usdc),
            1,
            uint64(block.timestamp + 1 hours)
        );
        bytes32 batchId = keccak256("batch1");
        SetPaymentBatch.PaymentIntent[] memory payments = _makePaymentArray(payment);

        vm.prank(sequencer);
        vm.expectEmit(true, true, true, true);
        emit PaymentFailed(batchId, payment.intentId, poorPayer, "Insufficient balance");
        paymentBatch.settleBatch(batchId, keccak256("root"), keccak256("tenant"), 1, 1, payments);
    }

    function test_Settlement_InsufficientAllowance() public {
        // Keyed payer so authorization is valid and we reach the allowance check.
        uint256 noApprovalPk = 0xA110;
        address noApprovalPayer = vm.addr(noApprovalPk);
        payerKey[noApprovalPayer] = noApprovalPk;
        usdc.mint(noApprovalPayer, 1_000_000e6);
        // No approval given

        SetPaymentBatch.PaymentIntent memory payment = _makePayment(
            keccak256("intent1"),
            noApprovalPayer,
            payee1,
            100e6,
            address(usdc),
            1,
            uint64(block.timestamp + 1 hours)
        );
        bytes32 batchId = keccak256("batch1");
        SetPaymentBatch.PaymentIntent[] memory payments = _makePaymentArray(payment);

        vm.prank(sequencer);
        vm.expectEmit(true, true, true, true);
        emit PaymentFailed(batchId, payment.intentId, noApprovalPayer, "Insufficient allowance");
        paymentBatch.settleBatch(batchId, keccak256("root"), keccak256("tenant"), 1, 1, payments);
    }

    function test_Settlement_TransferReturnsFalse() public {
        MockERC20ReturnsFalse failToken = new MockERC20ReturnsFalse();
        failToken.mint(payer1, 1_000_000e6);

        vm.prank(payer1);
        failToken.approve(address(paymentBatch), type(uint256).max);

        // Enable the fail token as an asset
        vm.prank(owner);
        paymentBatch.configureAsset(address(failToken), true, 1e4, 1e12, 1e14);

        // Set token to fail on transfer
        failToken.setShouldFail(true);

        SetPaymentBatch.PaymentIntent memory payment = _makePayment(
            keccak256("intent1"),
            payer1,
            payee1,
            100e6,
            address(failToken),
            1,
            uint64(block.timestamp + 1 hours)
        );
        bytes32 batchId = keccak256("batch1");
        SetPaymentBatch.PaymentIntent[] memory payments = _makePaymentArray(payment);

        vm.prank(sequencer);
        vm.expectEmit(true, true, true, true);
        emit PaymentFailed(batchId, payment.intentId, payer1, "Transfer failed");
        paymentBatch.settleBatch(batchId, keccak256("root"), keccak256("tenant"), 1, 1, payments);
    }

    function test_Settlement_MarksIntentAndNonce() public {
        bytes32 intentId = keccak256("intent1");
        uint64 nonce = 7;

        SetPaymentBatch.PaymentIntent memory payment = _makePayment(
            intentId, payer1, payee1, 100e6, address(usdc), nonce, uint64(block.timestamp + 1 hours)
        );

        assertFalse(paymentBatch.isIntentSettled(intentId));
        assertFalse(paymentBatch.isNonceUsed(payer1, nonce));

        _settleSinglePayment(keccak256("batch1"), payment);

        assertTrue(paymentBatch.isIntentSettled(intentId));
        assertTrue(paymentBatch.isNonceUsed(payer1, nonce));
    }

    // =========================================================================
    // 6. Daily Limits Tests
    // =========================================================================

    function test_DailyLimit_Exceeded() public {
        // Configure USDC with a small daily limit
        vm.prank(owner);
        paymentBatch.configureAsset(address(usdc), true, 1e4, 1e12, 200e6); // 200 USDC daily

        // Settle 150 USDC
        SetPaymentBatch.PaymentIntent memory payment1 = _makePayment(
            keccak256("intent1"),
            payer1,
            payee1,
            150e6,
            address(usdc),
            1,
            uint64(block.timestamp + 1 hours)
        );
        _settleSinglePayment(keccak256("batch1"), payment1);

        // Try to settle 60 USDC (would exceed 200 limit)
        SetPaymentBatch.PaymentIntent memory payment2 = _makePayment(
            keccak256("intent2"),
            payer1,
            payee1,
            60e6,
            address(usdc),
            2,
            uint64(block.timestamp + 1 hours)
        );
        bytes32 batchId2 = keccak256("batch2");
        SetPaymentBatch.PaymentIntent[] memory payments = _makePaymentArray(payment2);

        vm.prank(sequencer);
        vm.expectEmit(true, true, true, true);
        emit PaymentFailed(batchId2, keccak256("intent2"), payer1, "Daily limit exceeded");
        paymentBatch.settleBatch(batchId2, keccak256("root2"), keccak256("tenant"), 2, 2, payments);
    }

    function test_DailyLimit_ResetsAfterOneDay() public {
        // Configure USDC with a small daily limit
        vm.prank(owner);
        paymentBatch.configureAsset(address(usdc), true, 1e4, 1e12, 200e6); // 200 USDC daily

        // Settle 150 USDC
        SetPaymentBatch.PaymentIntent memory payment1 = _makePayment(
            keccak256("intent1"),
            payer1,
            payee1,
            150e6,
            address(usdc),
            1,
            uint64(block.timestamp + 1 hours)
        );
        _settleSinglePayment(keccak256("batch1"), payment1);

        // Warp forward 1 day
        vm.warp(block.timestamp + 1 days);

        // Should now be able to settle 150 again (daily volume reset)
        SetPaymentBatch.PaymentIntent memory payment2 = _makePayment(
            keccak256("intent2"),
            payer1,
            payee1,
            150e6,
            address(usdc),
            2,
            uint64(block.timestamp + 1 hours)
        );
        _settleSinglePayment(keccak256("batch2"), payment2);

        SetPaymentBatch.AssetConfig memory config = paymentBatch.getAssetConfig(address(usdc));
        assertEq(config.dailyVolume, 150e6); // reset and re-accumulated
    }

    function test_DailyLimit_ExactLimit() public {
        // Configure USDC with an exact limit
        vm.prank(owner);
        paymentBatch.configureAsset(address(usdc), true, 1e4, 1e12, 100e6); // 100 USDC daily

        // Settle exactly the daily limit
        SetPaymentBatch.PaymentIntent memory payment = _makePayment(
            keccak256("intent1"),
            payer1,
            payee1,
            100e6,
            address(usdc),
            1,
            uint64(block.timestamp + 1 hours)
        );
        _settleSinglePayment(keccak256("batch1"), payment);

        SetPaymentBatch.AssetConfig memory config = paymentBatch.getAssetConfig(address(usdc));
        assertEq(config.dailyVolume, 100e6);
    }

    // =========================================================================
    // 7. Batch Operations Tests
    // =========================================================================

    function test_SettleBatch_MultiplePayments() public {
        SetPaymentBatch.PaymentIntent[] memory payments = new SetPaymentBatch.PaymentIntent[](3);

        payments[0] = _makePayment(
            keccak256("intent1"),
            payer1,
            payee1,
            100e6,
            address(usdc),
            1,
            uint64(block.timestamp + 1 hours)
        );
        payments[1] = _makePayment(
            keccak256("intent2"),
            payer2,
            payee2,
            200e6,
            address(usdc),
            1,
            uint64(block.timestamp + 1 hours)
        );
        payments[2] = _makePayment(
            keccak256("intent3"),
            payer1,
            payee2,
            50e6,
            address(usdc),
            2,
            uint64(block.timestamp + 1 hours)
        );

        bytes32 batchId = keccak256("batch_multi");

        uint256 payer1Before = usdc.balanceOf(payer1);
        uint256 payer2Before = usdc.balanceOf(payer2);
        uint256 payee1Before = usdc.balanceOf(payee1);
        uint256 payee2Before = usdc.balanceOf(payee2);

        vm.prank(sequencer);
        paymentBatch.settleBatch(batchId, keccak256("root"), keccak256("tenant"), 1, 3, payments);

        // Verify balances
        assertEq(usdc.balanceOf(payer1), payer1Before - 150e6); // 100 + 50
        assertEq(usdc.balanceOf(payer2), payer2Before - 200e6);
        assertEq(usdc.balanceOf(payee1), payee1Before + 100e6);
        assertEq(usdc.balanceOf(payee2), payee2Before + 250e6); // 200 + 50

        // Verify batch stats
        SetPaymentBatch.BatchSettlement memory batch = paymentBatch.getBatch(batchId);
        assertEq(batch.paymentCount, 3);
        assertEq(batch.totalAmount, 350e6);

        // Verify global stats
    }

    function test_SettleBatch_PartialSuccess() public {
        // Two payments: one valid, one expired
        SetPaymentBatch.PaymentIntent[] memory payments = new SetPaymentBatch.PaymentIntent[](2);

        payments[0] = _makePayment(
            keccak256("good_intent"),
            payer1,
            payee1,
            100e6,
            address(usdc),
            1,
            uint64(block.timestamp + 1 hours)
        );
        payments[1] = _makePayment(
            keccak256("bad_intent"),
            payer1,
            payee2,
            50e6,
            address(usdc),
            2,
            uint64(block.timestamp - 1) // expired
        );

        bytes32 batchId = keccak256("batch_partial");

        vm.prank(sequencer);
        paymentBatch.settleBatch(batchId, keccak256("root"), keccak256("tenant"), 1, 2, payments);

        SetPaymentBatch.BatchSettlement memory batch = paymentBatch.getBatch(batchId);
        assertEq(batch.paymentCount, 1); // only 1 succeeded
        assertEq(batch.totalAmount, 100e6);
    }

    function test_SettleBatch_AllFail() public {
        // All payments expired
        SetPaymentBatch.PaymentIntent[] memory payments = new SetPaymentBatch.PaymentIntent[](2);

        payments[0] = _makePayment(
            keccak256("bad1"), payer1, payee1, 100e6, address(usdc), 1, uint64(block.timestamp - 1)
        );
        payments[1] = _makePayment(
            keccak256("bad2"), payer1, payee2, 50e6, address(usdc), 2, uint64(block.timestamp - 1)
        );

        bytes32 batchId = keccak256("batch_allfail");

        vm.prank(sequencer);
        paymentBatch.settleBatch(batchId, keccak256("root"), keccak256("tenant"), 1, 2, payments);

        SetPaymentBatch.BatchSettlement memory batch = paymentBatch.getBatch(batchId);
        assertGt(batch.settledAt, 0);
        assertEq(batch.paymentCount, 0);
        assertEq(batch.totalAmount, 0);
    }

    function test_SettleBatch_WithSsUsdToken() public {
        SetPaymentBatch.PaymentIntent memory payment = _makePayment(
            keccak256("intent_ssusd"),
            payer1,
            payee1,
            100e6,
            address(ssUsd),
            1,
            uint64(block.timestamp + 1 hours)
        );

        uint256 payerBefore = ssUsd.balanceOf(payer1);
        uint256 payeeBefore = ssUsd.balanceOf(payee1);

        _settleSinglePayment(keccak256("batch_ssusd"), payment);

        assertEq(ssUsd.balanceOf(payer1), payerBefore - 100e6);
        assertEq(ssUsd.balanceOf(payee1), payeeBefore + 100e6);
    }

    function test_SettleBatch_MultipleBatchesSequentially() public {
        // Settle batch 1
        SetPaymentBatch.PaymentIntent memory payment1 = _makePayment(
            keccak256("intent1"),
            payer1,
            payee1,
            100e6,
            address(usdc),
            1,
            uint64(block.timestamp + 1 hours)
        );
        _settleSinglePayment(keccak256("batch1"), payment1);

        // Settle batch 2
        SetPaymentBatch.PaymentIntent memory payment2 = _makePayment(
            keccak256("intent2"),
            payer2,
            payee2,
            200e6,
            address(usdc),
            1,
            uint64(block.timestamp + 1 hours)
        );
        _settleSinglePayment(keccak256("batch2"), payment2);
    }

    // =========================================================================
    // 8. View Functions Tests
    // =========================================================================

    function test_GetBatch_NonExistent() public view {
        SetPaymentBatch.BatchSettlement memory batch = paymentBatch.getBatch(keccak256("nope"));
        assertEq(batch.settledAt, 0);
        assertEq(batch.paymentCount, 0);
        assertEq(batch.totalAmount, 0);
    }

    function test_IsIntentSettled() public {
        bytes32 intentId = keccak256("intent1");
        assertFalse(paymentBatch.isIntentSettled(intentId));

        SetPaymentBatch.PaymentIntent memory payment = _makePayment(
            intentId, payer1, payee1, 100e6, address(usdc), 1, uint64(block.timestamp + 1 hours)
        );
        _settleSinglePayment(keccak256("batch1"), payment);

        assertTrue(paymentBatch.isIntentSettled(intentId));
    }

    function test_IsNonceUsed() public {
        assertFalse(paymentBatch.isNonceUsed(payer1, 1));

        SetPaymentBatch.PaymentIntent memory payment = _makeDefaultPayment();
        _settleSinglePayment(keccak256("batch1"), payment);

        assertTrue(paymentBatch.isNonceUsed(payer1, 1));
        assertFalse(paymentBatch.isNonceUsed(payer1, 2)); // different nonce
        assertFalse(paymentBatch.isNonceUsed(payer2, 1)); // different payer
    }

    function test_GetAssetConfig_Unconfigured() public view {
        SetPaymentBatch.AssetConfig memory config = paymentBatch.getAssetConfig(address(0xDEAD));
        assertFalse(config.enabled);
        assertEq(config.minAmount, 0);
        assertEq(config.maxAmount, 0);
        assertEq(config.dailyLimit, 0);
    }

    function test_GetStats() public {
        // Counters no longer updated in hot path (gas optimization)
        // Only verify sequencer count works
        (,,, uint256 sequencers) = paymentBatch.getStats();
        assertEq(sequencers, 1);
    }

    // =========================================================================
    // 9. Merkle Proof Verification Tests
    // =========================================================================

    function test_VerifyPaymentInclusion_ValidProof() public {
        // Build a simple 4-leaf Merkle tree
        bytes32 leaf0 = keccak256("intent0");
        bytes32 leaf1 = keccak256("intent1");
        bytes32 leaf2 = keccak256("intent2");
        bytes32 leaf3 = keccak256("intent3");

        bytes32 hash01 = keccak256(abi.encodePacked(leaf0, leaf1));
        bytes32 hash23 = keccak256(abi.encodePacked(leaf2, leaf3));
        bytes32 merkleRoot = keccak256(abi.encodePacked(hash01, hash23));

        // Settle a batch with this Merkle root
        bytes32 batchId = keccak256("batch_merkle");
        SetPaymentBatch.PaymentIntent memory payment = _makePayment(
            leaf0, payer1, payee1, 100e6, address(usdc), 1, uint64(block.timestamp + 1 hours)
        );
        SetPaymentBatch.PaymentIntent[] memory payments = _makePaymentArray(payment);

        vm.prank(sequencer);
        paymentBatch.settleBatch(batchId, merkleRoot, keccak256("tenant"), 1, 1, payments);

        // Verify leaf0 (index 0)
        bytes32[] memory proof0 = new bytes32[](2);
        proof0[0] = leaf1;
        proof0[1] = hash23;
        assertTrue(paymentBatch.verifyPaymentInclusion(batchId, leaf0, proof0, 0));

        // Verify leaf1 (index 1)
        bytes32[] memory proof1 = new bytes32[](2);
        proof1[0] = leaf0;
        proof1[1] = hash23;
        assertTrue(paymentBatch.verifyPaymentInclusion(batchId, leaf1, proof1, 1));

        // Verify leaf2 (index 2)
        bytes32[] memory proof2 = new bytes32[](2);
        proof2[0] = leaf3;
        proof2[1] = hash01;
        assertTrue(paymentBatch.verifyPaymentInclusion(batchId, leaf2, proof2, 2));

        // Verify leaf3 (index 3)
        bytes32[] memory proof3 = new bytes32[](2);
        proof3[0] = leaf2;
        proof3[1] = hash01;
        assertTrue(paymentBatch.verifyPaymentInclusion(batchId, leaf3, proof3, 3));
    }

    function test_VerifyPaymentInclusion_InvalidProof() public {
        bytes32 leaf = keccak256("intent0");
        bytes32 merkleRoot = keccak256(abi.encodePacked(leaf, keccak256("intent1")));

        bytes32 batchId = keccak256("batch_merkle");
        SetPaymentBatch.PaymentIntent memory payment = _makePayment(
            leaf, payer1, payee1, 100e6, address(usdc), 1, uint64(block.timestamp + 1 hours)
        );
        SetPaymentBatch.PaymentIntent[] memory payments = _makePaymentArray(payment);

        vm.prank(sequencer);
        paymentBatch.settleBatch(batchId, merkleRoot, keccak256("tenant"), 1, 1, payments);

        bytes32[] memory wrongProof = new bytes32[](1);
        wrongProof[0] = keccak256("wrong");
        assertFalse(paymentBatch.verifyPaymentInclusion(batchId, leaf, wrongProof, 0));
    }

    function test_VerifyPaymentInclusion_BatchNotExecuted() public view {
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = keccak256("sibling");

        assertFalse(
            paymentBatch.verifyPaymentInclusion(
                keccak256("nonexistent"), keccak256("leaf"), proof, 0
            )
        );
    }

    // =========================================================================
    // 10. Pause / Unpause Tests
    // =========================================================================

    function test_Pause() public {
        vm.prank(owner);
        paymentBatch.pause();
        assertTrue(paymentBatch.paused());
    }

    function test_Unpause() public {
        vm.prank(owner);
        paymentBatch.pause();

        vm.prank(owner);
        paymentBatch.unpause();
        assertFalse(paymentBatch.paused());
    }

    function test_Pause_NotOwner() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        paymentBatch.pause();
    }

    function test_Unpause_NotOwner() public {
        vm.prank(owner);
        paymentBatch.pause();

        vm.prank(unauthorized);
        vm.expectRevert();
        paymentBatch.unpause();
    }

    function test_SettleAfterUnpause() public {
        vm.prank(owner);
        paymentBatch.pause();

        vm.prank(owner);
        paymentBatch.unpause();

        // Should work after unpause
        _settleSinglePayment(keccak256("batch1"), _makeDefaultPayment());
    }

    // =========================================================================
    // 11. Edge Cases
    // =========================================================================

    function test_EdgeCase_MinAmountPayment() public {
        // Default min is 1e4
        SetPaymentBatch.PaymentIntent memory payment = _makePayment(
            keccak256("intent_min"),
            payer1,
            payee1,
            1e4,
            address(usdc),
            1,
            uint64(block.timestamp + 1 hours)
        );
        _settleSinglePayment(keccak256("batch_min"), payment);

        assertTrue(paymentBatch.isIntentSettled(keccak256("intent_min")));
    }

    function test_EdgeCase_MaxAmountPayment() public {
        // Default max is 1e12 (1M USDC)
        usdc.mint(payer1, 1e12);
        vm.prank(payer1);
        usdc.approve(address(paymentBatch), type(uint256).max);

        SetPaymentBatch.PaymentIntent memory payment = _makePayment(
            keccak256("intent_max"),
            payer1,
            payee1,
            1e12,
            address(usdc),
            100,
            uint64(block.timestamp + 1 hours)
        );
        _settleSinglePayment(keccak256("batch_max"), payment);

        assertTrue(paymentBatch.isIntentSettled(keccak256("intent_max")));
    }

    function test_EdgeCase_PaymentExactlyAtExpiry() public {
        uint64 expiryTime = uint64(block.timestamp);

        // At exactly validUntil: block.timestamp == validUntil means NOT expired
        // because the check is block.timestamp > _payment.validUntil
        SetPaymentBatch.PaymentIntent memory payment = _makePayment(
            keccak256("intent_exact"), payer1, payee1, 100e6, address(usdc), 1, expiryTime
        );
        _settleSinglePayment(keccak256("batch_exact"), payment);

        assertTrue(paymentBatch.isIntentSettled(keccak256("intent_exact")));
    }

    function test_EdgeCase_DifferentPayersSameNonce() public {
        // Same nonce is fine for different payers
        SetPaymentBatch.PaymentIntent[] memory payments = new SetPaymentBatch.PaymentIntent[](2);

        payments[0] = _makePayment(
            keccak256("intent1"),
            payer1,
            payee1,
            100e6,
            address(usdc),
            1,
            uint64(block.timestamp + 1 hours)
        );
        payments[1] = _makePayment(
            keccak256("intent2"),
            payer2,
            payee2,
            200e6,
            address(usdc),
            1, // same nonce
            uint64(block.timestamp + 1 hours)
        );

        bytes32 batchId = keccak256("batch_same_nonce");

        vm.prank(sequencer);
        paymentBatch.settleBatch(batchId, keccak256("root"), keccak256("tenant"), 1, 2, payments);

        SetPaymentBatch.BatchSettlement memory batch = paymentBatch.getBatch(batchId);
        assertEq(batch.paymentCount, 2); // both succeed
    }

    function test_EdgeCase_SamePayerSameNonceSameBatch() public {
        // Two payments with same payer and nonce in the same batch.
        // First succeeds; second fails because nonce is consumed.
        SetPaymentBatch.PaymentIntent[] memory payments = new SetPaymentBatch.PaymentIntent[](2);

        payments[0] = _makePayment(
            keccak256("intent1"),
            payer1,
            payee1,
            100e6,
            address(usdc),
            1,
            uint64(block.timestamp + 1 hours)
        );
        payments[1] = _makePayment(
            keccak256("intent2"),
            payer1,
            payee2,
            50e6,
            address(usdc),
            1, // same nonce
            uint64(block.timestamp + 1 hours)
        );

        bytes32 batchId = keccak256("batch_dup_nonce");

        vm.prank(sequencer);
        paymentBatch.settleBatch(batchId, keccak256("root"), keccak256("tenant"), 1, 2, payments);

        SetPaymentBatch.BatchSettlement memory batch = paymentBatch.getBatch(batchId);
        assertEq(batch.paymentCount, 1); // only first succeeds
        assertEq(batch.totalAmount, 100e6);
    }

    function test_EdgeCase_DuplicateIntentInSameBatch() public {
        // Two payments with the same intentId in one batch
        bytes32 intentId = keccak256("duplicate_intent");

        SetPaymentBatch.PaymentIntent[] memory payments = new SetPaymentBatch.PaymentIntent[](2);

        payments[0] = _makePayment(
            intentId, payer1, payee1, 100e6, address(usdc), 1, uint64(block.timestamp + 1 hours)
        );
        payments[1] = _makePayment(
            intentId, payer1, payee2, 50e6, address(usdc), 2, uint64(block.timestamp + 1 hours)
        );

        bytes32 batchId = keccak256("batch_dup_intent");

        vm.prank(sequencer);
        paymentBatch.settleBatch(batchId, keccak256("root"), keccak256("tenant"), 1, 2, payments);

        SetPaymentBatch.BatchSettlement memory batch = paymentBatch.getBatch(batchId);
        assertEq(batch.paymentCount, 1); // second should fail as already settled
    }

    function test_EdgeCase_LargeBatch() public {
        uint256 batchSize = 20;
        SetPaymentBatch.PaymentIntent[] memory payments =
            new SetPaymentBatch.PaymentIntent[](batchSize);

        for (uint256 i = 0; i < batchSize; i++) {
            payments[i] = _makePayment(
                bytes32(uint256(i + 1)),
                payer1,
                payee1,
                1e4, // min amount
                address(usdc),
                uint64(i + 1),
                uint64(block.timestamp + 1 hours)
            );
        }

        bytes32 batchId = keccak256("large_batch");

        vm.prank(sequencer);
        paymentBatch.settleBatch(
            batchId, keccak256("root"), keccak256("tenant"), 1, uint64(batchSize), payments
        );

        SetPaymentBatch.BatchSettlement memory batch = paymentBatch.getBatch(batchId);
        assertEq(batch.paymentCount, uint32(batchSize));
        assertEq(batch.totalAmount, 1e4 * batchSize);
    }

    function test_EdgeCase_SelfPayment() public {
        // Payer and payee are the same address
        SetPaymentBatch.PaymentIntent memory payment = _makePayment(
            keccak256("self_pay"),
            payer1,
            payer1,
            100e6,
            address(usdc),
            1,
            uint64(block.timestamp + 1 hours)
        );

        uint256 balanceBefore = usdc.balanceOf(payer1);

        _settleSinglePayment(keccak256("batch_self"), payment);

        // Balance unchanged (transferred to self)
        assertEq(usdc.balanceOf(payer1), balanceBefore);
        assertTrue(paymentBatch.isIntentSettled(keccak256("self_pay")));
    }

    // =========================================================================
    // 12. Multiple Sequencer Tests
    // =========================================================================

    function test_MultipleSequencers() public {
        address sequencer2 = address(0x30);

        vm.prank(owner);
        paymentBatch.setSequencerAuthorization(sequencer2, true);
        assertEq(paymentBatch.sequencerCount(), 2);

        // Sequencer 1 settles a batch
        SetPaymentBatch.PaymentIntent memory payment1 = _makePayment(
            keccak256("intent1"),
            payer1,
            payee1,
            100e6,
            address(usdc),
            1,
            uint64(block.timestamp + 1 hours)
        );
        _settleSinglePayment(keccak256("batch1"), payment1);

        // Sequencer 2 settles a batch
        SetPaymentBatch.PaymentIntent memory payment2 = _makePayment(
            keccak256("intent2"),
            payer2,
            payee2,
            200e6,
            address(usdc),
            1,
            uint64(block.timestamp + 1 hours)
        );
        SetPaymentBatch.PaymentIntent[] memory payments = _makePaymentArray(payment2);

        vm.prank(sequencer2);
        paymentBatch.settleBatch(
            keccak256("batch2"), keccak256("root2"), keccak256("tenant"), 2, 2, payments
        );

        SetPaymentBatch.BatchSettlement memory batch1 = paymentBatch.getBatch(keccak256("batch1"));
        SetPaymentBatch.BatchSettlement memory batch2 = paymentBatch.getBatch(keccak256("batch2"));
    }

    function test_RevokedSequencer_CannotSettle() public {
        vm.prank(owner);
        paymentBatch.setSequencerAuthorization(sequencer, false);

        SetPaymentBatch.PaymentIntent[] memory payments = _makePaymentArray(_makeDefaultPayment());

        vm.prank(sequencer);
        vm.expectRevert(SetPaymentBatch.NotAuthorizedSequencer.selector);
        paymentBatch.settleBatch(
            keccak256("batch1"), keccak256("root"), keccak256("tenant"), 1, 1, payments
        );
    }

    // =========================================================================
    // 13. Upgrade Tests
    // =========================================================================

    function test_UpgradeAuthorization_OnlyOwner() public {
        SetPaymentBatch newImpl = new SetPaymentBatch();

        vm.prank(unauthorized);
        vm.expectRevert();
        paymentBatch.upgradeToAndCall(address(newImpl), "");
    }

    function test_UpgradeAuthorization_OwnerCanUpgrade() public {
        SetPaymentBatch newImpl = new SetPaymentBatch();

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit ContractUpgraded(address(newImpl), owner);
        paymentBatch.upgradeToAndCall(address(newImpl), "");
    }

    // =========================================================================
    // 14. Fuzz Tests
    // =========================================================================

    function testFuzz_SettleBatch_ValidAmounts(
        uint256 amount
    ) public {
        // Bound to valid range: between minAmount (1e4) and maxAmount (1e12)
        amount = bound(amount, 1e4, 1e12);

        usdc.mint(payer1, amount);

        SetPaymentBatch.PaymentIntent memory payment = _makePayment(
            keccak256(abi.encodePacked("fuzz_intent", amount)),
            payer1,
            payee1,
            amount,
            address(usdc),
            100, // use a nonce unlikely to conflict
            uint64(block.timestamp + 1 hours)
        );

        uint256 payerBefore = usdc.balanceOf(payer1);
        uint256 payeeBefore = usdc.balanceOf(payee1);

        _settleSinglePayment(keccak256(abi.encodePacked("fuzz_batch", amount)), payment);

        assertEq(usdc.balanceOf(payer1), payerBefore - amount);
        assertEq(usdc.balanceOf(payee1), payeeBefore + amount);
    }

    function testFuzz_ConfigureAsset(
        uint256 minAmount,
        uint256 maxAmount,
        uint256 dailyLimit
    ) public {
        vm.assume(minAmount > 0);
        vm.assume(dailyLimit <= type(uint128).max);
        vm.assume(maxAmount >= minAmount);
        vm.assume(dailyLimit >= maxAmount);

        vm.prank(owner);
        paymentBatch.configureAsset(address(usdt), true, minAmount, maxAmount, dailyLimit);

        SetPaymentBatch.AssetConfig memory config = paymentBatch.getAssetConfig(address(usdt));
        assertTrue(config.enabled);
        assertEq(config.minAmount, minAmount);
        assertEq(config.maxAmount, maxAmount);
        assertEq(config.dailyLimit, dailyLimit);
    }

    function testFuzz_SequencerAuthorization(
        address _sequencer
    ) public {
        vm.assume(_sequencer != address(0));

        vm.prank(owner);
        paymentBatch.setSequencerAuthorization(_sequencer, true);
        assertTrue(paymentBatch.authorizedSequencers(_sequencer));

        vm.prank(owner);
        paymentBatch.setSequencerAuthorization(_sequencer, false);
        assertFalse(paymentBatch.authorizedSequencers(_sequencer));
    }

    // =========================================================================
    // 15. Batch Settlement Data Integrity Tests
    // =========================================================================

    function test_BatchSettlement_RecordsAllFields() public {
        bytes32 batchId = keccak256("integrity_batch");
        bytes32 merkleRoot = keccak256("integrity_root");
        bytes32 tenantStoreKey = keccak256("tenant_store_key");

        SetPaymentBatch.PaymentIntent[] memory payments = new SetPaymentBatch.PaymentIntent[](2);

        payments[0] = _makePayment(
            keccak256("i1"),
            payer1,
            payee1,
            100e6,
            address(usdc),
            1,
            uint64(block.timestamp + 1 hours)
        );
        payments[1] = _makePayment(
            keccak256("i2"),
            payer2,
            payee2,
            200e6,
            address(usdc),
            1,
            uint64(block.timestamp + 1 hours)
        );

        vm.prank(sequencer);
        paymentBatch.settleBatch(batchId, merkleRoot, tenantStoreKey, 5, 10, payments);

        SetPaymentBatch.BatchSettlement memory batch = paymentBatch.getBatch(batchId);
        assertEq(batch.merkleRoot, merkleRoot);
        assertEq(batch.tenantStoreKey, tenantStoreKey);
        assertEq(batch.sequenceStart, 5);
        assertEq(batch.sequenceEnd, 10);
        assertEq(batch.paymentCount, 2);
        assertEq(batch.totalAmount, 300e6);
        assertEq(batch.token, address(usdc)); // primary token from first payment
        assertEq(batch.settledAt, uint64(block.timestamp));
        assertGt(batch.settledAt, 0);
    }

    function test_BatchSettlement_PrimaryTokenFromFirstPayment() public {
        // When batch has mixed tokens, primary token is first payment's token
        SetPaymentBatch.PaymentIntent[] memory payments = new SetPaymentBatch.PaymentIntent[](2);

        payments[0] = _makePayment(
            keccak256("i1"),
            payer1,
            payee1,
            100e6,
            address(ssUsd),
            1,
            uint64(block.timestamp + 1 hours)
        );
        payments[1] = _makePayment(
            keccak256("i2"),
            payer2,
            payee2,
            200e6,
            address(usdc),
            1,
            uint64(block.timestamp + 1 hours)
        );

        bytes32 batchId = keccak256("mixed_batch");

        vm.prank(sequencer);
        paymentBatch.settleBatch(batchId, keccak256("root"), keccak256("tenant"), 1, 2, payments);

        SetPaymentBatch.BatchSettlement memory batch = paymentBatch.getBatch(batchId);
        assertEq(batch.token, address(ssUsd)); // primary from first payment
    }

    // =========================================================================
    // 16. Daily Volume Accounting Tests
    // =========================================================================

    function test_DailyVolume_AccumulatesCorrectly() public {
        // Settle two payments on the same token
        SetPaymentBatch.PaymentIntent memory payment1 = _makePayment(
            keccak256("vol1"),
            payer1,
            payee1,
            100e6,
            address(usdc),
            1,
            uint64(block.timestamp + 1 hours)
        );
        _settleSinglePayment(keccak256("b1"), payment1);

        SetPaymentBatch.PaymentIntent memory payment2 = _makePayment(
            keccak256("vol2"),
            payer1,
            payee1,
            200e6,
            address(usdc),
            2,
            uint64(block.timestamp + 1 hours)
        );
        _settleSinglePayment(keccak256("b2"), payment2);

        SetPaymentBatch.AssetConfig memory config = paymentBatch.getAssetConfig(address(usdc));
        assertEq(config.dailyVolume, 300e6);
    }

    function test_DailyVolume_IndependentPerToken() public {
        // Settle payments in different tokens
        SetPaymentBatch.PaymentIntent memory paymentUsdc = _makePayment(
            keccak256("usdc_vol"),
            payer1,
            payee1,
            100e6,
            address(usdc),
            1,
            uint64(block.timestamp + 1 hours)
        );
        _settleSinglePayment(keccak256("b_usdc"), paymentUsdc);

        SetPaymentBatch.PaymentIntent memory paymentSsUsd = _makePayment(
            keccak256("ssusd_vol"),
            payer1,
            payee1,
            200e6,
            address(ssUsd),
            2,
            uint64(block.timestamp + 1 hours)
        );
        _settleSinglePayment(keccak256("b_ssusd"), paymentSsUsd);

        SetPaymentBatch.AssetConfig memory usdcConfig = paymentBatch.getAssetConfig(address(usdc));
        SetPaymentBatch.AssetConfig memory ssUsdConfig = paymentBatch.getAssetConfig(address(ssUsd));

        assertEq(usdcConfig.dailyVolume, 100e6);
        assertEq(ssUsdConfig.dailyVolume, 200e6);
    }

    // =========================================================================
    // 17. Per-Payment Payer Authorization (EIP-712) Tests
    // =========================================================================

    /// @dev Shared assertion: settlement emits "Invalid authorization" and moves no funds.
    function _expectAuthFailure(
        bytes32 batchId,
        SetPaymentBatch.PaymentIntent memory payment
    ) internal {
        uint256 payee1Before = usdc.balanceOf(payee1);
        uint256 payee2Before = usdc.balanceOf(payee2);
        uint256 ssUsdPayee1Before = ssUsd.balanceOf(payee1);

        SetPaymentBatch.PaymentIntent[] memory payments = _makePaymentArray(payment);
        vm.prank(sequencer);
        vm.expectEmit(true, true, true, true);
        emit PaymentFailed(batchId, payment.intentId, payment.payer, "Invalid authorization");
        paymentBatch.settleBatch(batchId, keccak256("root"), keccak256("tenant"), 1, 1, payments);

        // No funds moved anywhere, intent not marked settled.
        assertEq(usdc.balanceOf(payee1), payee1Before);
        assertEq(usdc.balanceOf(payee2), payee2Before);
        assertEq(ssUsd.balanceOf(payee1), ssUsdPayee1Before);
        assertFalse(paymentBatch.isIntentSettled(payment.intentId));

        SetPaymentBatch.BatchSettlement memory batch = paymentBatch.getBatch(batchId);
        assertEq(batch.paymentCount, 0);
    }

    function test_Auth_ValidAuthorizationSettles() public {
        SetPaymentBatch.PaymentIntent memory payment = _makeDefaultPayment();
        assertGt(payment.authorization.length, 0);

        uint256 payeeBefore = usdc.balanceOf(payee1);
        _settleSinglePayment(keccak256("auth_ok"), payment);

        assertEq(usdc.balanceOf(payee1), payeeBefore + 100e6);
        assertTrue(paymentBatch.isIntentSettled(payment.intentId));
    }

    function test_Auth_WrongSigner_Fails() public {
        // Claims payer1 but is signed with payer2's key.
        SetPaymentBatch.PaymentIntent memory payment = _makeDefaultPayment();
        payment.authorization = _signAuthorization(payment, PAYER2_PK);
        _expectAuthFailure(keccak256("auth_wrong_signer"), payment);
    }

    function test_Auth_MissingSignature_Fails() public {
        SetPaymentBatch.PaymentIntent memory payment = _makeDefaultPayment();
        payment.authorization = bytes("");
        _expectAuthFailure(keccak256("auth_missing"), payment);
    }

    function test_Auth_TamperedAmount_Fails() public {
        // Signed over 100e6; sequencer inflates to 101e6 (still within limits/balance).
        SetPaymentBatch.PaymentIntent memory payment = _makeDefaultPayment();
        payment.amount = 101e6;
        _expectAuthFailure(keccak256("auth_amount"), payment);
    }

    function test_Auth_TamperedPayee_Fails() public {
        // Signed to pay payee1; sequencer redirects to payee2.
        SetPaymentBatch.PaymentIntent memory payment = _makeDefaultPayment();
        payment.payee = payee2;
        _expectAuthFailure(keccak256("auth_payee"), payment);
    }

    function test_Auth_TamperedToken_Fails() public {
        // Signed for USDC; sequencer swaps to ssUSD.
        SetPaymentBatch.PaymentIntent memory payment = _makeDefaultPayment();
        payment.token = address(ssUsd);
        _expectAuthFailure(keccak256("auth_token"), payment);
    }

    function test_Auth_TamperedNonce_Fails() public {
        SetPaymentBatch.PaymentIntent memory payment = _makeDefaultPayment();
        payment.nonce = 999;
        _expectAuthFailure(keccak256("auth_nonce"), payment);
    }

    function test_Auth_ExpiredValidBefore_Fails() public {
        // Signature is valid, but the signed validBefore (validUntil) has passed.
        SetPaymentBatch.PaymentIntent memory payment = _makePayment(
            keccak256("auth_expired"),
            payer1,
            payee1,
            100e6,
            address(usdc),
            1,
            uint64(block.timestamp - 1)
        );
        assertGt(payment.authorization.length, 0);

        bytes32 batchId = keccak256("auth_expired_batch");
        SetPaymentBatch.PaymentIntent[] memory payments = _makePaymentArray(payment);
        vm.prank(sequencer);
        vm.expectEmit(true, true, true, true);
        emit PaymentFailed(batchId, payment.intentId, payer1, "Payment expired");
        paymentBatch.settleBatch(batchId, keccak256("root"), keccak256("tenant"), 1, 1, payments);
    }

    function test_Auth_NotYetValid_Fails() public {
        // validAfter in the future; signed over it, so signature is valid but window not open.
        SetPaymentBatch.PaymentIntent memory payment = _makeDefaultPayment();
        payment.validAfter = uint64(block.timestamp + 1 hours);
        payment.authorization = _signAuthorization(payment, PAYER1_PK);

        bytes32 batchId = keccak256("auth_notyet_batch");
        SetPaymentBatch.PaymentIntent[] memory payments = _makePaymentArray(payment);
        vm.prank(sequencer);
        vm.expectEmit(true, true, true, true);
        emit PaymentFailed(batchId, payment.intentId, payer1, "Payment not yet valid");
        paymentBatch.settleBatch(batchId, keccak256("root"), keccak256("tenant"), 1, 1, payments);
    }

    function test_Auth_ReplayedNonce_Fails() public {
        // First payment settles with a valid signature over nonce 55.
        SetPaymentBatch.PaymentIntent memory p1 = _makePayment(
            keccak256("rn1"),
            payer1,
            payee1,
            100e6,
            address(usdc),
            55,
            uint64(block.timestamp + 1 hours)
        );
        _settleSinglePayment(keccak256("rn_b1"), p1);

        // Fresh intent, same payer + nonce, freshly and validly signed -> nonce blocks it.
        SetPaymentBatch.PaymentIntent memory p2 = _makePayment(
            keccak256("rn2"),
            payer1,
            payee1,
            100e6,
            address(usdc),
            55,
            uint64(block.timestamp + 1 hours)
        );
        assertGt(p2.authorization.length, 0);

        bytes32 batchId = keccak256("rn_b2");
        SetPaymentBatch.PaymentIntent[] memory payments = _makePaymentArray(p2);
        vm.prank(sequencer);
        vm.expectEmit(true, true, true, true);
        emit PaymentFailed(batchId, p2.intentId, payer1, "Nonce already used");
        paymentBatch.settleBatch(batchId, keccak256("root2"), keccak256("tenant"), 2, 2, payments);
    }

    function test_Auth_DomainSeparator_BindsVerifyingContract() public {
        // A signature valid for `paymentBatch` must NOT settle on an independent
        // instance (different verifyingContract in the EIP-712 domain).
        SetPaymentBatch.PaymentIntent memory payment = _makeDefaultPayment();

        SetPaymentBatch impl2 = new SetPaymentBatch();
        bytes memory initData = abi.encodeCall(
            SetPaymentBatch.initialize,
            (owner, sequencer, address(usdc), address(ssUsd), registryAddr)
        );
        ERC1967Proxy proxy2 = new ERC1967Proxy(address(impl2), initData);
        SetPaymentBatch pb2 = SetPaymentBatch(address(proxy2));

        // Domain separators differ.
        assertTrue(
            paymentBatch.hashPaymentAuthorization(payment) != pb2.hashPaymentAuthorization(payment)
        );

        vm.prank(payer1);
        usdc.approve(address(pb2), type(uint256).max);

        bytes32 batchId = keccak256("domain_batch");
        SetPaymentBatch.PaymentIntent[] memory payments = _makePaymentArray(payment);
        vm.prank(sequencer);
        vm.expectEmit(true, true, true, true);
        emit PaymentFailed(batchId, payment.intentId, payer1, "Invalid authorization");
        pb2.settleBatch(batchId, keccak256("root"), keccak256("tenant"), 1, 1, payments);
    }

    // ---- ERC-1271 smart-contract payer path ----

    function test_Auth_ERC1271_SmartWalletPayer_Settles() public {
        uint256 ownerPk = 0xC0FFEE;
        address walletOwner = vm.addr(ownerPk);
        ERC1271WalletMock wallet = new ERC1271WalletMock(walletOwner);

        usdc.mint(address(wallet), 1_000_000e6);
        vm.prank(address(wallet));
        usdc.approve(address(paymentBatch), type(uint256).max);

        // payer = smart wallet; authorization = owner's ECDSA sig, validated via ERC-1271.
        SetPaymentBatch.PaymentIntent memory payment = _makePayment(
            keccak256("erc1271_ok"),
            address(wallet),
            payee1,
            100e6,
            address(usdc),
            1,
            uint64(block.timestamp + 1 hours)
        );
        payment.authorization = _signAuthorization(payment, ownerPk);

        uint256 payeeBefore = usdc.balanceOf(payee1);
        _settleSinglePayment(keccak256("erc1271_batch"), payment);

        assertEq(usdc.balanceOf(payee1), payeeBefore + 100e6);
        assertTrue(paymentBatch.isIntentSettled(payment.intentId));
    }

    function test_Auth_ERC1271_WrongOwner_Fails() public {
        uint256 ownerPk = 0xC0FFEE;
        uint256 attackerPk = 0xBAD;
        address walletOwner = vm.addr(ownerPk);
        ERC1271WalletMock wallet = new ERC1271WalletMock(walletOwner);

        usdc.mint(address(wallet), 1_000_000e6);
        vm.prank(address(wallet));
        usdc.approve(address(paymentBatch), type(uint256).max);

        SetPaymentBatch.PaymentIntent memory payment = _makePayment(
            keccak256("erc1271_bad"),
            address(wallet),
            payee1,
            100e6,
            address(usdc),
            1,
            uint64(block.timestamp + 1 hours)
        );
        payment.authorization = _signAuthorization(payment, attackerPk); // not the wallet owner

        bytes32 batchId = keccak256("erc1271_bad_batch");
        uint256 payeeBefore = usdc.balanceOf(payee1);
        SetPaymentBatch.PaymentIntent[] memory payments = _makePaymentArray(payment);
        vm.prank(sequencer);
        vm.expectEmit(true, true, true, true);
        emit PaymentFailed(batchId, payment.intentId, address(wallet), "Invalid authorization");
        paymentBatch.settleBatch(batchId, keccak256("root"), keccak256("tenant"), 1, 1, payments);
        assertEq(usdc.balanceOf(payee1), payeeBefore);
        assertFalse(paymentBatch.isIntentSettled(payment.intentId));
    }
}
