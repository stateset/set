// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../stablecoin/TreasuryVault.sol";
import "../../stablecoin/TokenRegistry.sol";
import "../../stablecoin/NAVOracle.sol";
import "../../stablecoin/SSDC.sol";
import "../../stablecoin/interfaces/ITreasuryVault.sol";

/**
 * @title MockCollateral
 * @notice Mock ERC20 for testing with configurable decimals
 */
contract MockCollateral is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title TreasuryVaultTest
 * @notice Unit tests for TreasuryVault contract
 */
contract TreasuryVaultTest is Test {
    // Contracts
    TreasuryVault public vault;
    TokenRegistry public tokenRegistry;
    NAVOracle public navOracle;
    ssUSD public ssusd;

    // Mock tokens
    MockCollateral public usdc;
    MockCollateral public usdt;

    // Actors
    address public owner = address(0x1);
    address public attestor = address(0x2);
    address public operator = address(0x3);
    address public user1 = address(0x100);
    address public user2 = address(0x200);

    // Constants
    uint256 constant INITIAL_BALANCE = 1_000_000 * 1e6;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock tokens
        usdc = new MockCollateral("USD Coin", "USDC", 6);
        usdt = new MockCollateral("Tether USD", "USDT", 6);

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
        TreasuryVault vaultImpl = new TreasuryVault();
        vault = TreasuryVault(address(new ERC1967Proxy(
            address(vaultImpl),
            abi.encodeCall(TreasuryVault.initialize, (
                owner,
                address(tokenRegistry),
                address(navOracle),
                address(ssusd)
            ))
        )));

        // Wire up contracts
        ssusd.setTreasuryVault(address(vault));
        navOracle.setssUSD(address(ssusd));

        // Register USDC as collateral
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

        // Register USDT as collateral
        tokenRegistry.registerToken(
            address(usdt),
            "Tether USD",
            "USDT",
            6,
            ITokenRegistry.TokenCategory.BRIDGED,
            ITokenRegistry.TrustLevel.TRUSTED,
            true,
            ""
        );

        // Set operator
        vault.setOperator(operator, true);

        vm.stopPrank();

        // Fund users
        usdc.mint(user1, INITIAL_BALANCE);
        usdc.mint(user2, INITIAL_BALANCE);
        usdt.mint(user1, INITIAL_BALANCE);
        usdt.mint(user2, INITIAL_BALANCE);
    }

    // =========================================================================
    // Initialization Tests
    // =========================================================================

    function test_Initialization() public view {
        assertEq(vault.owner(), owner);
        assertEq(address(vault.tokenRegistry()), address(tokenRegistry));
        assertEq(address(vault.navOracle()), address(navOracle));
        assertEq(address(vault.ssUSD()), address(ssusd));
        assertEq(vault.mintFee(), 0);
        assertEq(vault.redeemFee(), 10); // 0.1%
        assertEq(vault.redemptionDelay(), 1 hours);
    }

    function test_CannotInitializeTwice() public {
        vm.expectRevert();
        vault.initialize(owner, address(tokenRegistry), address(navOracle), address(ssusd));
    }

    // =========================================================================
    // Deposit Tests
    // =========================================================================

    function test_Deposit() public {
        uint256 depositAmount = 1000 * 1e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        uint256 minted = vault.deposit(address(usdc), depositAmount, user1);
        vm.stopPrank();

        assertEq(minted, 1000 * 1e18);
        assertEq(ssusd.balanceOf(user1), 1000 * 1e18);
        assertEq(vault.getCollateralBalance(address(usdc)), depositAmount);
        assertEq(vault.getTotalCollateralValue(), 1000 * 1e18);
    }

    function test_DepositWithDifferentDecimals() public {
        // Deploy 18 decimal token
        MockCollateral token18 = new MockCollateral("Test Token", "TEST", 18);
        token18.mint(user1, 1000 * 1e18);

        vm.startPrank(owner);
        tokenRegistry.registerToken(
            address(token18),
            "Test Token",
            "TEST",
            18,
            ITokenRegistry.TokenCategory.NATIVE,
            ITokenRegistry.TrustLevel.TRUSTED,
            true,
            ""
        );
        vm.stopPrank();

        vm.startPrank(user1);
        token18.approve(address(vault), 1000 * 1e18);
        uint256 minted = vault.deposit(address(token18), 1000 * 1e18, user1);
        vm.stopPrank();

        assertEq(minted, 1000 * 1e18);
    }

    function test_DepositForOther() public {
        uint256 depositAmount = 500 * 1e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(address(usdc), depositAmount, user2);
        vm.stopPrank();

        assertEq(ssusd.balanceOf(user1), 0);
        assertEq(ssusd.balanceOf(user2), 500 * 1e18);
    }

    function test_DepositWithMintFee() public {
        vm.prank(owner);
        vault.setFees(50, 10); // 0.5% mint fee

        uint256 depositAmount = 1000 * 1e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        uint256 minted = vault.deposit(address(usdc), depositAmount, user1);
        vm.stopPrank();

        // 1000 - 0.5% = 995
        assertEq(minted, 995 * 1e18);
    }

    function test_RevertDepositBelowMinimum() public {
        uint256 smallAmount = 1e5; // 0.1 USDC = $0.10

        vm.startPrank(user1);
        usdc.approve(address(vault), smallAmount);

        vm.expectRevert(TreasuryVault.InsufficientDeposit.selector);
        vault.deposit(address(usdc), smallAmount, user1);
        vm.stopPrank();
    }

    function test_RevertDepositUnapprovedCollateral() public {
        MockCollateral badToken = new MockCollateral("Bad", "BAD", 6);
        badToken.mint(user1, 1000 * 1e6);

        vm.startPrank(user1);
        badToken.approve(address(vault), 1000 * 1e6);

        vm.expectRevert(TreasuryVault.NotApprovedCollateral.selector);
        vault.deposit(address(badToken), 1000 * 1e6, user1);
        vm.stopPrank();
    }

    function test_RevertDepositWhenPaused() public {
        vm.prank(owner);
        vault.pauseDeposits(true);

        vm.startPrank(user1);
        usdc.approve(address(vault), 1000 * 1e6);

        vm.expectRevert(TreasuryVault.DepositsArePaused.selector);
        vault.deposit(address(usdc), 1000 * 1e6, user1);
        vm.stopPrank();
    }

    // =========================================================================
    // Redemption Request Tests
    // =========================================================================

    function test_RequestRedemption() public {
        // First deposit
        vm.startPrank(user1);
        usdc.approve(address(vault), 1000 * 1e6);
        vault.deposit(address(usdc), 1000 * 1e6, user1);

        // Request redemption
        ssusd.approve(address(vault), 500 * 1e18);
        uint256 requestId = vault.requestRedemption(500 * 1e18, address(usdc));
        vm.stopPrank();

        ITreasuryVault.RedemptionRequest memory request = vault.getRedemptionRequest(requestId);
        assertEq(request.requester, user1);
        assertEq(request.ssUSDAmount, 500 * 1e18);
        assertEq(request.collateralToken, address(usdc));
        assertEq(uint256(request.status), uint256(ITreasuryVault.RedemptionStatus.PENDING));
        assertEq(vault.pendingRedemptionCount(), 1);
    }

    function test_RevertRedemptionZeroAmount() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), 1000 * 1e6);
        vault.deposit(address(usdc), 1000 * 1e6, user1);

        vm.expectRevert(TreasuryVault.InvalidAmount.selector);
        vault.requestRedemption(0, address(usdc));
        vm.stopPrank();
    }

    function test_RevertRedemptionInsufficientBalance() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), 100 * 1e6);
        vault.deposit(address(usdc), 100 * 1e6, user1);

        ssusd.approve(address(vault), 500 * 1e18);

        vm.expectRevert(TreasuryVault.InvalidAmount.selector);
        vault.requestRedemption(500 * 1e18, address(usdc));
        vm.stopPrank();
    }

    function test_RevertRedemptionWhenPaused() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), 1000 * 1e6);
        vault.deposit(address(usdc), 1000 * 1e6, user1);
        vm.stopPrank();

        vm.prank(owner);
        vault.pauseRedemptions(true);

        vm.startPrank(user1);
        ssusd.approve(address(vault), 500 * 1e18);

        vm.expectRevert(TreasuryVault.RedemptionsArePaused.selector);
        vault.requestRedemption(500 * 1e18, address(usdc));
        vm.stopPrank();
    }

    // =========================================================================
    // Redemption Cancel Tests
    // =========================================================================

    function test_CancelRedemption() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), 1000 * 1e6);
        vault.deposit(address(usdc), 1000 * 1e6, user1);

        ssusd.approve(address(vault), 500 * 1e18);
        uint256 requestId = vault.requestRedemption(500 * 1e18, address(usdc));

        uint256 balanceAfterRequest = ssusd.balanceOf(user1);

        vault.cancelRedemption(requestId);
        vm.stopPrank();

        // ssUSD restored
        assertEq(ssusd.balanceOf(user1), balanceAfterRequest + 500 * 1e18);

        ITreasuryVault.RedemptionRequest memory request = vault.getRedemptionRequest(requestId);
        assertEq(uint256(request.status), uint256(ITreasuryVault.RedemptionStatus.CANCELLED));
        assertEq(vault.pendingRedemptionCount(), 0);
    }

    function test_RevertCancelNotOwner() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), 1000 * 1e6);
        vault.deposit(address(usdc), 1000 * 1e6, user1);

        ssusd.approve(address(vault), 500 * 1e18);
        uint256 requestId = vault.requestRedemption(500 * 1e18, address(usdc));
        vm.stopPrank();

        vm.prank(user2);
        vm.expectRevert(TreasuryVault.NotRequestOwner.selector);
        vault.cancelRedemption(requestId);
    }

    function test_RevertCancelAlreadyProcessed() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), 1000 * 1e6);
        vault.deposit(address(usdc), 1000 * 1e6, user1);

        ssusd.approve(address(vault), 500 * 1e18);
        uint256 requestId = vault.requestRedemption(500 * 1e18, address(usdc));
        vm.stopPrank();

        // Wait and process
        vm.warp(block.timestamp + 1 hours + 1);
        vault.processRedemption(requestId);

        vm.prank(user1);
        vm.expectRevert(TreasuryVault.RedemptionAlreadyProcessed.selector);
        vault.cancelRedemption(requestId);
    }

    // =========================================================================
    // Redemption Process Tests
    // =========================================================================

    function test_ProcessRedemption() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), 1000 * 1e6);
        vault.deposit(address(usdc), 1000 * 1e6, user1);

        ssusd.approve(address(vault), 500 * 1e18);
        uint256 requestId = vault.requestRedemption(500 * 1e18, address(usdc));
        vm.stopPrank();

        uint256 usdcBefore = usdc.balanceOf(user1);

        // Wait for delay
        vm.warp(block.timestamp + 1 hours + 1);

        vault.processRedemption(requestId);

        uint256 usdcAfter = usdc.balanceOf(user1);

        // 500 ssUSD - 0.1% fee = 499.5 USDC (but in 6 decimals)
        uint256 expectedUsdc = 500 * 1e6 - (500 * 1e6 * 10 / 10000);
        assertApproxEqRel(usdcAfter - usdcBefore, expectedUsdc, 0.01e18);

        ITreasuryVault.RedemptionRequest memory request = vault.getRedemptionRequest(requestId);
        assertEq(uint256(request.status), uint256(ITreasuryVault.RedemptionStatus.COMPLETED));
    }

    function test_RevertProcessBeforeDelay() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), 1000 * 1e6);
        vault.deposit(address(usdc), 1000 * 1e6, user1);

        ssusd.approve(address(vault), 500 * 1e18);
        uint256 requestId = vault.requestRedemption(500 * 1e18, address(usdc));
        vm.stopPrank();

        vm.expectRevert(TreasuryVault.RedemptionNotReady.selector);
        vault.processRedemption(requestId);
    }

    function test_BatchProcessRedemptions() public {
        // Two users deposit and request redemption
        vm.startPrank(user1);
        usdc.approve(address(vault), 1000 * 1e6);
        vault.deposit(address(usdc), 1000 * 1e6, user1);
        ssusd.approve(address(vault), 500 * 1e18);
        uint256 requestId1 = vault.requestRedemption(500 * 1e18, address(usdc));
        vm.stopPrank();

        vm.startPrank(user2);
        usdc.approve(address(vault), 1000 * 1e6);
        vault.deposit(address(usdc), 1000 * 1e6, user2);
        ssusd.approve(address(vault), 300 * 1e18);
        uint256 requestId2 = vault.requestRedemption(300 * 1e18, address(usdc));
        vm.stopPrank();

        // Wait and batch process
        vm.warp(block.timestamp + 1 hours + 1);

        uint256[] memory requestIds = new uint256[](2);
        requestIds[0] = requestId1;
        requestIds[1] = requestId2;

        vm.prank(operator);
        vault.processBatchRedemptions(requestIds);

        ITreasuryVault.RedemptionRequest memory request1 = vault.getRedemptionRequest(requestId1);
        ITreasuryVault.RedemptionRequest memory request2 = vault.getRedemptionRequest(requestId2);

        assertEq(uint256(request1.status), uint256(ITreasuryVault.RedemptionStatus.COMPLETED));
        assertEq(uint256(request2.status), uint256(ITreasuryVault.RedemptionStatus.COMPLETED));
    }

    // =========================================================================
    // Admin Tests
    // =========================================================================

    function test_SetFees() public {
        vm.prank(owner);
        vault.setFees(50, 25);

        assertEq(vault.mintFee(), 50);
        assertEq(vault.redeemFee(), 25);
    }

    function test_RevertSetFeesTooHigh() public {
        vm.prank(owner);
        vm.expectRevert(TreasuryVault.FeeTooHigh.selector);
        vault.setFees(200, 10); // 2% exceeds MAX_FEE_BPS (1%)
    }

    function test_SetRedemptionDelay() public {
        vm.prank(owner);
        vault.setRedemptionDelay(2 hours);

        assertEq(vault.redemptionDelay(), 2 hours);
    }

    function test_SetOperator() public {
        address newOperator = address(0x999);

        vm.prank(owner);
        vault.setOperator(newOperator, true);

        assertTrue(vault.operators(newOperator));
    }

    function test_PauseDeposits() public {
        vm.prank(owner);
        vault.pauseDeposits(true);

        assertTrue(vault.depositsPaused());
    }

    function test_PauseRedemptions() public {
        vm.prank(owner);
        vault.pauseRedemptions(true);

        assertTrue(vault.redemptionsPaused());
    }

    function test_EmergencyWithdraw() public {
        // Deposit first
        vm.startPrank(user1);
        usdc.approve(address(vault), 1000 * 1e6);
        vault.deposit(address(usdc), 1000 * 1e6, user1);
        vm.stopPrank();

        address recipient = address(0x999);
        uint256 withdrawAmount = 500 * 1e6;

        vm.prank(owner);
        vault.emergencyWithdraw(address(usdc), withdrawAmount, recipient);

        assertEq(usdc.balanceOf(recipient), withdrawAmount);
        assertEq(vault.getCollateralBalance(address(usdc)), 500 * 1e6);
    }

    function test_RevertNonOwnerAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.setFees(10, 10);

        vm.prank(user1);
        vm.expectRevert();
        vault.pauseDeposits(true);

        vm.prank(user1);
        vm.expectRevert();
        vault.setOperator(user2, true);
    }

    // =========================================================================
    // View Function Tests
    // =========================================================================

    function test_GetCollateralRatio() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), 1000 * 1e6);
        vault.deposit(address(usdc), 1000 * 1e6, user1);
        vm.stopPrank();

        // Should be 100% (1e18)
        uint256 ratio = vault.getCollateralRatio();
        assertEq(ratio, 1e18);
    }

    function test_GetCollateralRatioNoSupply() public view {
        // With no supply, should return max
        uint256 ratio = vault.getCollateralRatio();
        assertEq(ratio, type(uint256).max);
    }

    function test_GetUserRedemptions() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), 1000 * 1e6);
        vault.deposit(address(usdc), 1000 * 1e6, user1);

        ssusd.approve(address(vault), 300 * 1e18);
        vault.requestRedemption(100 * 1e18, address(usdc));
        vault.requestRedemption(100 * 1e18, address(usdc));
        vault.requestRedemption(100 * 1e18, address(usdc));
        vm.stopPrank();

        uint256[] memory redemptions = vault.getUserRedemptions(user1);
        assertEq(redemptions.length, 3);
    }

    // =========================================================================
    // Fuzz Tests
    // =========================================================================

    function testFuzz_Deposit(uint256 amount) public {
        // Bound to reasonable amounts (min $1 to max $10M)
        amount = bound(amount, 1 * 1e6, 10_000_000 * 1e6);

        usdc.mint(user1, amount);

        vm.startPrank(user1);
        usdc.approve(address(vault), amount);
        uint256 minted = vault.deposit(address(usdc), amount, user1);
        vm.stopPrank();

        // Minted should be normalized to 18 decimals
        uint256 expectedMinted = amount * 1e12; // 6 decimals to 18 decimals
        assertEq(minted, expectedMinted);
    }

    function testFuzz_RedemptionFee(uint256 amount) public {
        amount = bound(amount, 100 * 1e6, 100_000 * 1e6);

        usdc.mint(user1, amount);

        vm.startPrank(user1);
        usdc.approve(address(vault), amount);
        vault.deposit(address(usdc), amount, user1);

        uint256 ssUSDAmount = amount * 1e12;
        ssusd.approve(address(vault), ssUSDAmount);
        uint256 requestId = vault.requestRedemption(ssUSDAmount, address(usdc));
        vm.stopPrank();

        vm.warp(block.timestamp + 1 hours + 1);

        uint256 usdcBefore = usdc.balanceOf(user1);
        vault.processRedemption(requestId);
        uint256 usdcAfter = usdc.balanceOf(user1);

        // Should receive amount minus 0.1% fee
        uint256 expectedFee = (amount * 10) / 10000;
        uint256 expectedReturn = amount - expectedFee;

        assertApproxEqRel(usdcAfter - usdcBefore, expectedReturn, 0.001e18);
    }
}
