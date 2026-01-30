// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../stablecoin/wSSDC.sol";
import "../stablecoin/SSDC.sol";
import "../stablecoin/NAVOracle.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title wSSDCTest
 * @notice Tests for wrapped SSDC vault
 */
contract wSSDCTest is Test {
    wSSDC public vault;
    SSDC public ssdcToken;
    NAVOracle public oracle;

    address public owner = address(0x1);
    address public attestor = address(0x2);
    address public user1 = address(0x10);
    address public user2 = address(0x20);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy NAVOracle
        NAVOracle oracleImpl = new NAVOracle();
        bytes memory oracleInitData = abi.encodeCall(
            NAVOracle.initialize,
            (owner, attestor, 1 days)
        );
        address oracleProxy = address(new ERC1967Proxy(address(oracleImpl), oracleInitData));
        oracle = NAVOracle(oracleProxy);

        // Deploy ssUSD
        ssUSD ssUSDImpl = new ssUSD();
        bytes memory ssUSDInitData = abi.encodeCall(
            ssUSD.initialize,
            (owner, address(oracle))
        );
        address ssUSDProxy = address(new ERC1967Proxy(address(ssUSDImpl), ssUSDInitData));
        ssUSDToken = ssUSD(ssUSDProxy);

        // Deploy wssUSD
        wssUSD vaultImpl = new wssUSD();
        bytes memory vaultInitData = abi.encodeCall(
            wssUSD.initialize,
            (owner, address(ssUSDToken))
        );
        address vaultProxy = address(new ERC1967Proxy(address(vaultImpl), vaultInitData));
        vault = wssUSD(vaultProxy);

        // Setup ssUSD - set treasury vault (use owner as mock treasury for testing)
        ssUSDToken.setTreasuryVault(owner);

        // Configure oracle
        oracle.setssUSD(address(ssUSDToken));

        vm.stopPrank();
    }

    // =========================================================================
    // Initialization Tests
    // =========================================================================

    function test_Initialization() public view {
        assertEq(vault.name(), "Wrapped Set Stablecoin USD");
        assertEq(vault.symbol(), "wssUSD");
        assertEq(vault.decimals(), 18);
        assertEq(vault.owner(), owner);
        assertEq(address(vault.asset()), address(ssUSDToken));
    }

    function test_Initialize_RevertsZeroAddress() public {
        wssUSD impl = new wssUSD();

        bytes memory initData = abi.encodeCall(
            wssUSD.initialize,
            (address(0), address(ssUSDToken))
        );

        vm.expectRevert(wssUSD.InvalidAddress.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    // =========================================================================
    // Wrap/Unwrap Tests
    // =========================================================================

    function test_Wrap() public {
        _mintssUSD(user1, 100 ether);

        vm.startPrank(user1);
        ssUSDToken.approve(address(vault), 100 ether);
        uint256 wssUSDReceived = vault.wrap(100 ether);
        vm.stopPrank();

        assertEq(vault.balanceOf(user1), wssUSDReceived);
        assertEq(ssUSDToken.balanceOf(user1), 0);
    }

    function test_Unwrap() public {
        _mintssUSD(user1, 100 ether);

        vm.startPrank(user1);
        ssUSDToken.approve(address(vault), 100 ether);
        uint256 wssUSDAmount = vault.wrap(100 ether);

        uint256 ssUSDReceived = vault.unwrap(wssUSDAmount);
        vm.stopPrank();

        assertEq(vault.balanceOf(user1), 0);
        assertEq(ssUSDToken.balanceOf(user1), ssUSDReceived);
    }

    // =========================================================================
    // Deposit Cap Tests
    // =========================================================================

    function test_SetDepositCap() public {
        vm.prank(owner);
        vault.setDepositCap(1000 ether);

        assertEq(vault.depositCap(), 1000 ether);
    }

    function test_Wrap_RevertsExceedsDepositCap() public {
        vm.prank(owner);
        vault.setDepositCap(50 ether);

        _mintssUSD(user1, 100 ether);

        vm.startPrank(user1);
        ssUSDToken.approve(address(vault), 100 ether);

        vm.expectRevert(wssUSD.DepositCapExceeded.selector);
        vault.wrap(100 ether);
        vm.stopPrank();
    }

    function test_Wrap_RespectsDepositCap() public {
        vm.prank(owner);
        vault.setDepositCap(100 ether);

        _mintssUSD(user1, 50 ether);
        _mintssUSD(user2, 50 ether);

        vm.startPrank(user1);
        ssUSDToken.approve(address(vault), 50 ether);
        vault.wrap(50 ether);
        vm.stopPrank();

        vm.startPrank(user2);
        ssUSDToken.approve(address(vault), 50 ether);
        vault.wrap(50 ether);
        vm.stopPrank();

        assertEq(vault.totalDeposited(), 100 ether);
    }

    // =========================================================================
    // Pause Tests
    // =========================================================================

    function test_Pause() public {
        vm.prank(owner);
        vault.pause();

        assertTrue(vault.paused());
    }

    function test_Unpause() public {
        vm.prank(owner);
        vault.pause();

        vm.prank(owner);
        vault.unpause();

        assertFalse(vault.paused());
    }

    function test_Wrap_RevertsWhenPaused() public {
        _mintssUSD(user1, 100 ether);

        vm.prank(owner);
        vault.pause();

        vm.startPrank(user1);
        ssUSDToken.approve(address(vault), 100 ether);

        vm.expectRevert();
        vault.wrap(100 ether);
        vm.stopPrank();
    }

    function test_Unwrap_RevertsWhenPaused() public {
        _mintssUSD(user1, 100 ether);

        vm.startPrank(user1);
        ssUSDToken.approve(address(vault), 100 ether);
        uint256 wssUSDAmount = vault.wrap(100 ether);
        vm.stopPrank();

        vm.prank(owner);
        vault.pause();

        vm.prank(user1);
        vm.expectRevert();
        vault.unwrap(wssUSDAmount);
    }

    // =========================================================================
    // Max Functions Tests
    // =========================================================================

    function test_MaxDeposit_ReturnsZeroWhenPaused() public {
        vm.prank(owner);
        vault.pause();

        assertEq(vault.maxDeposit(user1), 0);
    }

    function test_MaxDeposit_RespectsDepositCap() public {
        vm.prank(owner);
        vault.setDepositCap(100 ether);

        _mintssUSD(user1, 50 ether);

        vm.startPrank(user1);
        ssUSDToken.approve(address(vault), 50 ether);
        vault.wrap(50 ether);
        vm.stopPrank();

        assertEq(vault.maxDeposit(user2), 50 ether);
    }

    function test_MaxWithdraw_ReturnsZeroWhenPaused() public {
        _mintssUSD(user1, 100 ether);

        vm.startPrank(user1);
        ssUSDToken.approve(address(vault), 100 ether);
        vault.wrap(100 ether);
        vm.stopPrank();

        vm.prank(owner);
        vault.pause();

        assertEq(vault.maxWithdraw(user1), 0);
    }

    function test_MaxRedeem_ReturnsZeroWhenPaused() public {
        _mintssUSD(user1, 100 ether);

        vm.startPrank(user1);
        ssUSDToken.approve(address(vault), 100 ether);
        vault.wrap(100 ether);
        vm.stopPrank();

        vm.prank(owner);
        vault.pause();

        assertEq(vault.maxRedeem(user1), 0);
    }

    // =========================================================================
    // Monitoring Function Tests
    // =========================================================================

    function test_GetVaultStatus() public {
        _mintssUSD(user1, 100 ether);

        vm.startPrank(user1);
        ssUSDToken.approve(address(vault), 100 ether);
        vault.wrap(100 ether);
        vm.stopPrank();

        (
            uint256 assets,
            uint256 supply,
            uint256 sharePrice,
            uint256 cap,
            uint256 deposited,
            uint256 remainingCap,
            bool isPaused
        ) = vault.getVaultStatus();

        assertEq(assets, 100 ether);
        assertEq(supply, 100 ether);
        assertEq(sharePrice, 1e18);
        assertEq(cap, 0); // Unlimited
        assertEq(deposited, 100 ether);
        assertEq(remainingCap, type(uint256).max);
        assertFalse(isPaused);
    }

    function test_GetAccountDetails() public {
        _mintssUSD(user1, 100 ether);

        vm.startPrank(user1);
        ssUSDToken.approve(address(vault), 100 ether);
        vault.wrap(100 ether);
        vm.stopPrank();

        (
            uint256 wssUSDBalance,
            uint256 ssUSDValue,
            uint256 percentOfVault
        ) = vault.getAccountDetails(user1);

        assertEq(wssUSDBalance, 100 ether);
        assertEq(ssUSDValue, 100 ether);
        assertEq(percentOfVault, 10000); // 100%
    }

    function test_GetAccruedYield() public {
        _mintssUSD(user1, 100 ether);

        vm.startPrank(user1);
        ssUSDToken.approve(address(vault), 100 ether);
        vault.wrap(100 ether);
        vm.stopPrank();

        // Initially no yield
        uint256 yield = vault.getAccruedYield();
        assertEq(yield, 0);
    }

    function test_GetSharePrice() public view {
        uint256 price = vault.getSharePrice();
        assertEq(price, 1e18); // Initial 1:1 ratio
    }

    function test_GetssUSDValue() public {
        _mintssUSD(user1, 100 ether);

        vm.startPrank(user1);
        ssUSDToken.approve(address(vault), 100 ether);
        vault.wrap(100 ether);
        vm.stopPrank();

        uint256 value = vault.getssUSDValue(user1);
        assertEq(value, 100 ether);
    }

    function test_GetWssUSDBySSUSD() public view {
        uint256 wssUSDAmount = vault.getWssUSDBySSUSD(100 ether);
        assertEq(wssUSDAmount, 100 ether); // 1:1 initially
    }

    function test_GetSSUSDByWssUSD() public view {
        uint256 ssUSDAmount = vault.getSSUSDByWssUSD(100 ether);
        assertEq(ssUSDAmount, 100 ether); // 1:1 initially
    }

    // =========================================================================
    // Helper Functions
    // =========================================================================

    function _mintssUSD(address to, uint256 amount) internal {
        // Use owner as treasury to mint
        uint256 shares = (amount * 1e18) / oracle.getCurrentNAVPerShare();
        vm.prank(owner);
        ssUSDToken.mintShares(to, shares);
    }
}
