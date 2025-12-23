// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../stablecoin/TokenRegistry.sol";
import "../../stablecoin/NAVOracle.sol";
import "../../stablecoin/ssUSD.sol";
import "../../stablecoin/wssUSD.sol";
import "../../stablecoin/TreasuryVault.sol";

/**
 * @title MockUSDC
 * @notice Mock USDC with 6 decimals
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
 * @title MockUSDT
 * @notice Mock USDT with 6 decimals
 */
contract MockUSDT is ERC20 {
    constructor() ERC20("Tether USD", "USDT") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title StablecoinIntegrationTest
 * @notice Integration tests for the ssUSD stablecoin system
 */
contract StablecoinIntegrationTest is Test {
    // Contracts
    TokenRegistry public tokenRegistry;
    NAVOracle public navOracle;
    ssUSD public ssusd;
    wssUSD public wssusd;
    TreasuryVault public treasury;

    // Mock tokens
    MockUSDC public usdc;
    MockUSDT public usdt;

    // Actors
    address public owner = address(0x1);
    address public attestor = address(0x2);
    address public operator = address(0x3);
    address public user1 = address(0x100);
    address public user2 = address(0x200);

    // Constants
    uint256 constant INITIAL_BALANCE = 1_000_000 * 1e6; // 1M USDC/USDT

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock tokens
        usdc = new MockUSDC();
        usdt = new MockUSDT();

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

        // Deploy wssUSD
        wssUSD wssusdImpl = new wssUSD();
        wssusd = wssUSD(address(new ERC1967Proxy(
            address(wssusdImpl),
            abi.encodeCall(wssUSD.initialize, (owner, address(ssusd)))
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

        // Wire up contracts
        ssusd.setTreasuryVault(address(treasury));
        navOracle.setssUSD(address(ssusd));

        // Register collateral tokens
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

        // Register ssUSD and wssUSD
        tokenRegistry.registerToken(
            address(ssusd),
            "Set Stablecoin USD",
            "ssUSD",
            18,
            ITokenRegistry.TokenCategory.NATIVE,
            ITokenRegistry.TrustLevel.TRUSTED,
            false,
            ""
        );

        tokenRegistry.registerToken(
            address(wssusd),
            "Wrapped Set Stablecoin USD",
            "wssUSD",
            18,
            ITokenRegistry.TokenCategory.NATIVE,
            ITokenRegistry.TrustLevel.TRUSTED,
            false,
            ""
        );

        // Set operator
        treasury.setOperator(operator, true);

        vm.stopPrank();

        // Fund users
        usdc.mint(user1, INITIAL_BALANCE);
        usdc.mint(user2, INITIAL_BALANCE);
        usdt.mint(user1, INITIAL_BALANCE);
        usdt.mint(user2, INITIAL_BALANCE);
    }

    // =========================================================================
    // Deposit Tests
    // =========================================================================

    function test_DepositUSDC() public {
        uint256 depositAmount = 1000 * 1e6; // 1000 USDC

        vm.startPrank(user1);
        usdc.approve(address(treasury), depositAmount);
        uint256 ssUSDMinted = treasury.deposit(address(usdc), depositAmount, user1);
        vm.stopPrank();

        // Should mint 1000 ssUSD (1:1 with normalized amount)
        assertEq(ssUSDMinted, 1000 * 1e18);
        assertEq(ssusd.balanceOf(user1), 1000 * 1e18);
        assertEq(treasury.getCollateralBalance(address(usdc)), depositAmount);
    }

    function test_DepositUSDT() public {
        uint256 depositAmount = 500 * 1e6; // 500 USDT

        vm.startPrank(user1);
        usdt.approve(address(treasury), depositAmount);
        uint256 ssUSDMinted = treasury.deposit(address(usdt), depositAmount, user1);
        vm.stopPrank();

        assertEq(ssUSDMinted, 500 * 1e18);
        assertEq(ssusd.balanceOf(user1), 500 * 1e18);
    }

    function test_DepositForOther() public {
        uint256 depositAmount = 100 * 1e6;

        vm.startPrank(user1);
        usdc.approve(address(treasury), depositAmount);
        treasury.deposit(address(usdc), depositAmount, user2);
        vm.stopPrank();

        assertEq(ssusd.balanceOf(user1), 0);
        assertEq(ssusd.balanceOf(user2), 100 * 1e18);
    }

    // =========================================================================
    // Transfer Tests
    // =========================================================================

    function test_TransferssUSD() public {
        // Deposit
        vm.startPrank(user1);
        usdc.approve(address(treasury), 1000 * 1e6);
        treasury.deposit(address(usdc), 1000 * 1e6, user1);

        // Transfer
        ssusd.transfer(user2, 300 * 1e18);
        vm.stopPrank();

        assertEq(ssusd.balanceOf(user1), 700 * 1e18);
        assertEq(ssusd.balanceOf(user2), 300 * 1e18);
    }

    // =========================================================================
    // Rebase Tests
    // =========================================================================

    function test_RebaseIncreasesBalance() public {
        // User deposits 1000 USDC
        vm.startPrank(user1);
        usdc.approve(address(treasury), 1000 * 1e6);
        treasury.deposit(address(usdc), 1000 * 1e6, user1);
        vm.stopPrank();

        uint256 initialBalance = ssusd.balanceOf(user1);
        uint256 initialShares = ssusd.sharesOf(user1);

        // Attestor updates NAV (5% yield)
        vm.prank(attestor);
        navOracle.attestNAV(
            1050 * 1e18, // Total assets now $1050 (5% yield)
            20240101,
            bytes32(0)
        );

        uint256 newBalance = ssusd.balanceOf(user1);
        uint256 newShares = ssusd.sharesOf(user1);

        // Shares should be unchanged
        assertEq(newShares, initialShares);

        // Balance should increase by ~5%
        assertApproxEqRel(newBalance, 1050 * 1e18, 0.01e18); // 1% tolerance
    }

    function test_SharesStableAcrossRebase() public {
        // Two users deposit
        vm.startPrank(user1);
        usdc.approve(address(treasury), 600 * 1e6);
        treasury.deposit(address(usdc), 600 * 1e6, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        usdc.approve(address(treasury), 400 * 1e6);
        treasury.deposit(address(usdc), 400 * 1e6, user2);
        vm.stopPrank();

        uint256 user1Shares = ssusd.sharesOf(user1);
        uint256 user2Shares = ssusd.sharesOf(user2);

        // NAV update (10% yield)
        vm.prank(attestor);
        navOracle.attestNAV(1100 * 1e18, 20240101, bytes32(0));

        // Shares unchanged
        assertEq(ssusd.sharesOf(user1), user1Shares);
        assertEq(ssusd.sharesOf(user2), user2Shares);

        // Balances increased proportionally
        assertApproxEqRel(ssusd.balanceOf(user1), 660 * 1e18, 0.01e18);
        assertApproxEqRel(ssusd.balanceOf(user2), 440 * 1e18, 0.01e18);
    }

    // =========================================================================
    // wssUSD Tests
    // =========================================================================

    function test_WrapssUSD() public {
        // Deposit and get ssUSD
        vm.startPrank(user1);
        usdc.approve(address(treasury), 1000 * 1e6);
        treasury.deposit(address(usdc), 1000 * 1e6, user1);

        // Wrap ssUSD
        ssusd.approve(address(wssusd), 500 * 1e18);
        uint256 wssUSDReceived = wssusd.wrap(500 * 1e18);
        vm.stopPrank();

        assertEq(wssusd.balanceOf(user1), wssUSDReceived);
        assertEq(ssusd.balanceOf(user1), 500 * 1e18);
    }

    function test_wssUSDStableOnRebase() public {
        // Deposit and wrap
        vm.startPrank(user1);
        usdc.approve(address(treasury), 1000 * 1e6);
        treasury.deposit(address(usdc), 1000 * 1e6, user1);
        ssusd.approve(address(wssusd), 1000 * 1e18);
        uint256 wssUSDBalance = wssusd.wrap(1000 * 1e18);
        vm.stopPrank();

        // NAV update (5% yield)
        vm.prank(attestor);
        navOracle.attestNAV(1050 * 1e18, 20240101, bytes32(0));

        // wssUSD balance unchanged
        assertEq(wssusd.balanceOf(user1), wssUSDBalance);

        // But ssUSD value increased
        uint256 ssUSDValue = wssusd.getssUSDValue(user1);
        assertApproxEqRel(ssUSDValue, 1050 * 1e18, 0.01e18);
    }

    function test_UnwrapAfterYield() public {
        // Deposit and wrap
        vm.startPrank(user1);
        usdc.approve(address(treasury), 1000 * 1e6);
        treasury.deposit(address(usdc), 1000 * 1e6, user1);
        ssusd.approve(address(wssusd), 1000 * 1e18);
        uint256 wssUSDBalance = wssusd.wrap(1000 * 1e18);
        vm.stopPrank();

        // NAV update (5% yield)
        vm.prank(attestor);
        navOracle.attestNAV(1050 * 1e18, 20240101, bytes32(0));

        // Unwrap
        vm.prank(user1);
        uint256 ssUSDReceived = wssusd.unwrap(wssUSDBalance);

        // Should receive more ssUSD than deposited
        assertApproxEqRel(ssUSDReceived, 1050 * 1e18, 0.01e18);
    }

    // =========================================================================
    // Redemption Tests
    // =========================================================================

    function test_RequestRedemption() public {
        // Deposit
        vm.startPrank(user1);
        usdc.approve(address(treasury), 1000 * 1e6);
        treasury.deposit(address(usdc), 1000 * 1e6, user1);

        // Request redemption
        ssusd.approve(address(treasury), 500 * 1e18);
        uint256 requestId = treasury.requestRedemption(500 * 1e18, address(usdc));
        vm.stopPrank();

        ITreasuryVault.RedemptionRequest memory request = treasury.getRedemptionRequest(requestId);
        assertEq(request.requester, user1);
        assertEq(request.ssUSDAmount, 500 * 1e18);
        assertEq(uint256(request.status), uint256(ITreasuryVault.RedemptionStatus.PENDING));
    }

    function test_ProcessRedemption() public {
        // Deposit
        vm.startPrank(user1);
        usdc.approve(address(treasury), 1000 * 1e6);
        treasury.deposit(address(usdc), 1000 * 1e6, user1);

        // Request redemption
        ssusd.approve(address(treasury), 500 * 1e18);
        uint256 requestId = treasury.requestRedemption(500 * 1e18, address(usdc));
        vm.stopPrank();

        // Wait for delay
        vm.warp(block.timestamp + 1 hours + 1);

        // Process
        uint256 usdcBefore = usdc.balanceOf(user1);
        treasury.processRedemption(requestId);
        uint256 usdcAfter = usdc.balanceOf(user1);

        // Should receive ~500 USDC minus 0.1% fee
        uint256 expectedUsdc = 500 * 1e6 - (500 * 1e6 * 10 / 10000);
        assertApproxEqRel(usdcAfter - usdcBefore, expectedUsdc, 0.01e18);
    }

    function test_CancelRedemption() public {
        // Deposit
        vm.startPrank(user1);
        usdc.approve(address(treasury), 1000 * 1e6);
        treasury.deposit(address(usdc), 1000 * 1e6, user1);

        // Request redemption
        ssusd.approve(address(treasury), 500 * 1e18);
        uint256 requestId = treasury.requestRedemption(500 * 1e18, address(usdc));

        uint256 ssUSDAfterRequest = ssusd.balanceOf(user1);

        // Cancel
        treasury.cancelRedemption(requestId);
        vm.stopPrank();

        // ssUSD returned
        assertEq(ssusd.balanceOf(user1), ssUSDAfterRequest + 500 * 1e18);

        ITreasuryVault.RedemptionRequest memory request = treasury.getRedemptionRequest(requestId);
        assertEq(uint256(request.status), uint256(ITreasuryVault.RedemptionStatus.CANCELLED));
    }

    // =========================================================================
    // Full Lifecycle Test
    // =========================================================================

    function test_FullLifecycle() public {
        // 1. User1 deposits 10,000 USDC
        vm.startPrank(user1);
        usdc.approve(address(treasury), 10000 * 1e6);
        treasury.deposit(address(usdc), 10000 * 1e6, user1);
        vm.stopPrank();

        assertEq(ssusd.balanceOf(user1), 10000 * 1e18);

        // 2. User2 deposits 5,000 USDT
        vm.startPrank(user2);
        usdt.approve(address(treasury), 5000 * 1e6);
        treasury.deposit(address(usdt), 5000 * 1e6, user2);
        vm.stopPrank();

        // 3. User1 wraps half to wssUSD
        vm.startPrank(user1);
        ssusd.approve(address(wssusd), 5000 * 1e18);
        wssusd.wrap(5000 * 1e18);
        vm.stopPrank();

        // 4. Time passes, yield accrues (5%)
        vm.prank(attestor);
        navOracle.attestNAV(15750 * 1e18, 20240101, bytes32(0)); // 15000 * 1.05

        // 5. Verify balances
        // User1 ssUSD: 5000 * 1.05 = 5250
        assertApproxEqRel(ssusd.balanceOf(user1), 5250 * 1e18, 0.01e18);

        // User1 wssUSD value: 5000 * 1.05 = 5250 (balance unchanged)
        assertApproxEqRel(wssusd.getssUSDValue(user1), 5250 * 1e18, 0.01e18);

        // User2 ssUSD: 5000 * 1.05 = 5250
        assertApproxEqRel(ssusd.balanceOf(user2), 5250 * 1e18, 0.01e18);

        // 6. User2 transfers to User1
        vm.prank(user2);
        ssusd.transfer(user1, 1000 * 1e18);

        // 7. User1 unwraps wssUSD
        vm.startPrank(user1);
        uint256 wssUSDBalance = wssusd.balanceOf(user1);
        wssusd.unwrap(wssUSDBalance);
        vm.stopPrank();

        // 8. User1 redeems some ssUSD
        vm.startPrank(user1);
        uint256 redeemAmount = 2000 * 1e18;
        ssusd.approve(address(treasury), redeemAmount);
        uint256 requestId = treasury.requestRedemption(redeemAmount, address(usdc));
        vm.stopPrank();

        // 9. Wait and process
        vm.warp(block.timestamp + 1 hours + 1);
        treasury.processRedemption(requestId);

        // 10. Verify final state
        assertTrue(ssusd.balanceOf(user1) > 0);
        assertTrue(usdc.balanceOf(user1) > INITIAL_BALANCE - 10000 * 1e6);
    }

    // =========================================================================
    // Access Control Tests
    // =========================================================================

    function test_OnlyAttestorCanAttest() public {
        vm.prank(user1);
        vm.expectRevert(NAVOracle.NotAuthorizedAttestor.selector);
        navOracle.attestNAV(1000 * 1e18, 20240101, bytes32(0));
    }

    function test_OnlyTreasuryCanMint() public {
        vm.prank(user1);
        vm.expectRevert(ssUSD.NotTreasuryVault.selector);
        ssusd.mintShares(user1, 1000 * 1e18);
    }

    function test_OnlyOwnerCanPause() public {
        vm.prank(user1);
        vm.expectRevert();
        treasury.pauseDeposits(true);
    }

    // =========================================================================
    // Edge Cases
    // =========================================================================

    function test_DepositMinimum() public {
        // Less than $1 should fail
        vm.startPrank(user1);
        usdc.approve(address(treasury), 1e5); // 0.1 USDC

        vm.expectRevert(TreasuryVault.InsufficientDeposit.selector);
        treasury.deposit(address(usdc), 1e5, user1);
        vm.stopPrank();
    }

    function test_UnapprovedCollateral() public {
        MockUSDC badToken = new MockUSDC();
        badToken.mint(user1, 1000 * 1e6);

        vm.startPrank(user1);
        badToken.approve(address(treasury), 1000 * 1e6);

        vm.expectRevert(TreasuryVault.NotApprovedCollateral.selector);
        treasury.deposit(address(badToken), 1000 * 1e6, user1);
        vm.stopPrank();
    }

    function test_RedemptionBeforeDelay() public {
        vm.startPrank(user1);
        usdc.approve(address(treasury), 1000 * 1e6);
        treasury.deposit(address(usdc), 1000 * 1e6, user1);

        ssusd.approve(address(treasury), 500 * 1e18);
        uint256 requestId = treasury.requestRedemption(500 * 1e18, address(usdc));
        vm.stopPrank();

        // Try to process immediately
        vm.expectRevert(TreasuryVault.RedemptionNotReady.selector);
        treasury.processRedemption(requestId);
    }
}
