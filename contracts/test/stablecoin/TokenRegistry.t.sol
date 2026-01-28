// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../stablecoin/TokenRegistry.sol";
import "../../stablecoin/interfaces/ITokenRegistry.sol";

/**
 * @title TokenRegistryTest
 * @notice Unit tests for TokenRegistry contract
 */
contract TokenRegistryTest is Test {
    TokenRegistry public registry;

    address public owner = address(0x1);
    address public unauthorized = address(0x100);

    address public token1 = address(0x1001);
    address public token2 = address(0x1002);
    address public token3 = address(0x1003);

    function setUp() public {
        vm.startPrank(owner);

        TokenRegistry impl = new TokenRegistry();
        registry = TokenRegistry(address(new ERC1967Proxy(
            address(impl),
            abi.encodeCall(TokenRegistry.initialize, (owner))
        )));

        vm.stopPrank();
    }

    // =========================================================================
    // Initialization Tests
    // =========================================================================

    function test_Initialization() public view {
        assertEq(registry.owner(), owner);
        assertEq(registry.tokenCount(), 0);
    }

    function test_CannotInitializeTwice() public {
        vm.expectRevert();
        registry.initialize(owner);
    }

    // =========================================================================
    // Registration Tests
    // =========================================================================

    function test_RegisterToken() public {
        vm.prank(owner);
        registry.registerToken(
            token1,
            "USD Coin",
            "USDC",
            6,
            ITokenRegistry.TokenCategory.BRIDGED,
            ITokenRegistry.TrustLevel.TRUSTED,
            true,
            "https://example.com/usdc.png"
        );

        assertTrue(registry.isRegistered(token1));
        assertTrue(registry.isApprovedCollateral(token1));
        assertEq(registry.tokenCount(), 1);

        ITokenRegistry.TokenInfo memory info = registry.getTokenInfo(token1);
        assertEq(info.tokenAddress, token1);
        assertEq(info.name, "USD Coin");
        assertEq(info.symbol, "USDC");
        assertEq(info.decimals, 6);
        assertEq(uint256(info.category), uint256(ITokenRegistry.TokenCategory.BRIDGED));
        assertEq(uint256(info.trustLevel), uint256(ITokenRegistry.TrustLevel.TRUSTED));
        assertTrue(info.isCollateral);
        assertEq(info.logoURI, "https://example.com/usdc.png");
    }

    function test_RegisterMultipleTokens() public {
        vm.startPrank(owner);

        registry.registerToken(
            token1, "Token 1", "TK1", 18,
            ITokenRegistry.TokenCategory.NATIVE,
            ITokenRegistry.TrustLevel.TRUSTED,
            true, ""
        );

        registry.registerToken(
            token2, "Token 2", "TK2", 6,
            ITokenRegistry.TokenCategory.BRIDGED,
            ITokenRegistry.TrustLevel.TRUSTED,
            false, ""
        );

        registry.registerToken(
            token3, "Token 3", "TK3", 8,
            ITokenRegistry.TokenCategory.UNKNOWN,
            ITokenRegistry.TrustLevel.UNVERIFIED,
            false, ""
        );

        vm.stopPrank();

        assertEq(registry.tokenCount(), 3);
        assertTrue(registry.isRegistered(token1));
        assertTrue(registry.isRegistered(token2));
        assertTrue(registry.isRegistered(token3));
    }

    function test_RevertRegisterZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(TokenRegistry.InvalidTokenAddress.selector);
        registry.registerToken(
            address(0), "Zero", "ZERO", 18,
            ITokenRegistry.TokenCategory.NATIVE,
            ITokenRegistry.TrustLevel.UNVERIFIED,
            false, ""
        );
    }

    function test_RevertRegisterDuplicate() public {
        vm.startPrank(owner);

        registry.registerToken(
            token1, "Token 1", "TK1", 18,
            ITokenRegistry.TokenCategory.NATIVE,
            ITokenRegistry.TrustLevel.TRUSTED,
            true, ""
        );

        vm.expectRevert(TokenRegistry.TokenAlreadyRegistered.selector);
        registry.registerToken(
            token1, "Token 1 Again", "TK1", 18,
            ITokenRegistry.TokenCategory.NATIVE,
            ITokenRegistry.TrustLevel.TRUSTED,
            true, ""
        );

        vm.stopPrank();
    }

    function test_RevertRegisterInvalidDecimals() public {
        vm.prank(owner);
        vm.expectRevert(TokenRegistry.InvalidDecimals.selector);
        registry.registerToken(
            token1, "Bad Decimals", "BAD", 19, // > 18
            ITokenRegistry.TokenCategory.NATIVE,
            ITokenRegistry.TrustLevel.UNVERIFIED,
            false, ""
        );
    }

    function test_RevertUnauthorizedRegister() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        registry.registerToken(
            token1, "Token", "TK", 18,
            ITokenRegistry.TokenCategory.NATIVE,
            ITokenRegistry.TrustLevel.UNVERIFIED,
            false, ""
        );
    }

    // =========================================================================
    // Update Tests
    // =========================================================================

    function test_UpdateTokenMetadata() public {
        vm.startPrank(owner);

        registry.registerToken(
            token1, "Old Name", "OLD", 18,
            ITokenRegistry.TokenCategory.NATIVE,
            ITokenRegistry.TrustLevel.TRUSTED,
            true, ""
        );

        registry.updateTokenMetadata(token1, "New Name", "NEW", "https://new.uri");

        vm.stopPrank();

        ITokenRegistry.TokenInfo memory info = registry.getTokenInfo(token1);
        assertEq(info.name, "New Name");
        assertEq(info.symbol, "NEW");
        assertEq(info.logoURI, "https://new.uri");
    }

    function test_RevertUpdateUnregistered() public {
        vm.prank(owner);
        vm.expectRevert(TokenRegistry.TokenNotRegistered.selector);
        registry.updateTokenMetadata(token1, "Name", "SYM", "");
    }

    function test_SetCollateralStatus() public {
        vm.startPrank(owner);

        registry.registerToken(
            token1, "Token", "TK", 18,
            ITokenRegistry.TokenCategory.NATIVE,
            ITokenRegistry.TrustLevel.TRUSTED,
            false, ""
        );

        assertFalse(registry.isApprovedCollateral(token1));

        registry.setCollateralStatus(token1, true);
        assertTrue(registry.isApprovedCollateral(token1));

        registry.setCollateralStatus(token1, false);
        assertFalse(registry.isApprovedCollateral(token1));

        vm.stopPrank();
    }

    function test_SetTokenCategory() public {
        vm.startPrank(owner);

        registry.registerToken(
            token1, "Token", "TK", 18,
            ITokenRegistry.TokenCategory.NATIVE,
            ITokenRegistry.TrustLevel.TRUSTED,
            true, ""
        );

        registry.setTokenCategory(token1, ITokenRegistry.TokenCategory.BRIDGED);

        vm.stopPrank();

        ITokenRegistry.TokenInfo memory info = registry.getTokenInfo(token1);
        assertEq(uint256(info.category), uint256(ITokenRegistry.TokenCategory.BRIDGED));
    }

    function test_SetTrustLevel() public {
        vm.startPrank(owner);

        registry.registerToken(
            token1, "Token", "TK", 18,
            ITokenRegistry.TokenCategory.NATIVE,
            ITokenRegistry.TrustLevel.UNVERIFIED,
            false, ""
        );

        registry.setTrustLevel(token1, ITokenRegistry.TrustLevel.TRUSTED);

        vm.stopPrank();

        ITokenRegistry.TokenInfo memory info = registry.getTokenInfo(token1);
        assertEq(uint256(info.trustLevel), uint256(ITokenRegistry.TrustLevel.TRUSTED));
    }

    // =========================================================================
    // Removal Tests
    // =========================================================================

    function test_RemoveToken() public {
        vm.startPrank(owner);

        registry.registerToken(
            token1, "Token 1", "TK1", 18,
            ITokenRegistry.TokenCategory.NATIVE,
            ITokenRegistry.TrustLevel.TRUSTED,
            true, ""
        );

        assertTrue(registry.isRegistered(token1));
        assertEq(registry.tokenCount(), 1);

        registry.removeToken(token1);

        assertFalse(registry.isRegistered(token1));
        assertFalse(registry.isApprovedCollateral(token1));
        assertEq(registry.tokenCount(), 0);

        vm.stopPrank();
    }

    function test_RemoveMiddleToken() public {
        vm.startPrank(owner);

        // Register 3 tokens
        registry.registerToken(token1, "Token 1", "TK1", 18, ITokenRegistry.TokenCategory.NATIVE, ITokenRegistry.TrustLevel.TRUSTED, true, "");
        registry.registerToken(token2, "Token 2", "TK2", 18, ITokenRegistry.TokenCategory.NATIVE, ITokenRegistry.TrustLevel.TRUSTED, true, "");
        registry.registerToken(token3, "Token 3", "TK3", 18, ITokenRegistry.TokenCategory.NATIVE, ITokenRegistry.TrustLevel.TRUSTED, true, "");

        // Remove middle token
        registry.removeToken(token2);

        vm.stopPrank();

        assertEq(registry.tokenCount(), 2);
        assertTrue(registry.isRegistered(token1));
        assertFalse(registry.isRegistered(token2));
        assertTrue(registry.isRegistered(token3));

        // List should contain token1 and token3 (order may differ due to swap)
        address[] memory allTokens = registry.getAllTokens();
        assertEq(allTokens.length, 2);
    }

    function test_RevertRemoveUnregistered() public {
        vm.prank(owner);
        vm.expectRevert(TokenRegistry.TokenNotRegistered.selector);
        registry.removeToken(token1);
    }

    function test_RevertGetInfoUnregistered() public {
        vm.expectRevert(TokenRegistry.TokenNotRegistered.selector);
        registry.getTokenInfo(token1);
    }

    // =========================================================================
    // Query Tests
    // =========================================================================

    function test_GetAllTokens() public {
        vm.startPrank(owner);

        registry.registerToken(token1, "Token 1", "TK1", 18, ITokenRegistry.TokenCategory.NATIVE, ITokenRegistry.TrustLevel.TRUSTED, true, "");
        registry.registerToken(token2, "Token 2", "TK2", 18, ITokenRegistry.TokenCategory.BRIDGED, ITokenRegistry.TrustLevel.TRUSTED, true, "");

        vm.stopPrank();

        address[] memory tokens = registry.getAllTokens();
        assertEq(tokens.length, 2);
    }

    function test_GetTokensByCategory() public {
        vm.startPrank(owner);

        registry.registerToken(token1, "Native 1", "N1", 18, ITokenRegistry.TokenCategory.NATIVE, ITokenRegistry.TrustLevel.TRUSTED, true, "");
        registry.registerToken(token2, "Bridged 1", "B1", 18, ITokenRegistry.TokenCategory.BRIDGED, ITokenRegistry.TrustLevel.TRUSTED, true, "");
        registry.registerToken(token3, "Native 2", "N2", 18, ITokenRegistry.TokenCategory.NATIVE, ITokenRegistry.TrustLevel.TRUSTED, true, "");

        vm.stopPrank();

        address[] memory nativeTokens = registry.getTokensByCategory(ITokenRegistry.TokenCategory.NATIVE);
        address[] memory bridgedTokens = registry.getTokensByCategory(ITokenRegistry.TokenCategory.BRIDGED);

        assertEq(nativeTokens.length, 2);
        assertEq(bridgedTokens.length, 1);
    }

    function test_GetCollateralTokens() public {
        vm.startPrank(owner);

        registry.registerToken(token1, "Collateral 1", "C1", 18, ITokenRegistry.TokenCategory.NATIVE, ITokenRegistry.TrustLevel.TRUSTED, true, "");
        registry.registerToken(token2, "Non-Collateral", "NC", 18, ITokenRegistry.TokenCategory.NATIVE, ITokenRegistry.TrustLevel.TRUSTED, false, "");
        registry.registerToken(token3, "Collateral 2", "C2", 18, ITokenRegistry.TokenCategory.BRIDGED, ITokenRegistry.TrustLevel.TRUSTED, true, "");

        vm.stopPrank();

        address[] memory collaterals = registry.getCollateralTokens();
        assertEq(collaterals.length, 2);
    }

    function test_IsRegistered() public {
        assertFalse(registry.isRegistered(token1));

        vm.prank(owner);
        registry.registerToken(token1, "Token", "TK", 18, ITokenRegistry.TokenCategory.NATIVE, ITokenRegistry.TrustLevel.TRUSTED, true, "");

        assertTrue(registry.isRegistered(token1));
    }

    function test_IsApprovedCollateral() public {
        vm.startPrank(owner);

        registry.registerToken(token1, "Collateral", "COL", 18, ITokenRegistry.TokenCategory.NATIVE, ITokenRegistry.TrustLevel.TRUSTED, true, "");
        registry.registerToken(token2, "Not Collateral", "NC", 18, ITokenRegistry.TokenCategory.NATIVE, ITokenRegistry.TrustLevel.TRUSTED, false, "");

        vm.stopPrank();

        assertTrue(registry.isApprovedCollateral(token1));
        assertFalse(registry.isApprovedCollateral(token2));
        assertFalse(registry.isApprovedCollateral(token3)); // Unregistered
    }

    // =========================================================================
    // Access Control Tests
    // =========================================================================

    function test_RevertUnauthorizedUpdates() public {
        vm.prank(owner);
        registry.registerToken(token1, "Token", "TK", 18, ITokenRegistry.TokenCategory.NATIVE, ITokenRegistry.TrustLevel.TRUSTED, true, "");

        vm.startPrank(unauthorized);

        vm.expectRevert();
        registry.updateTokenMetadata(token1, "New", "NEW", "");

        vm.expectRevert();
        registry.setCollateralStatus(token1, false);

        vm.expectRevert();
        registry.setTokenCategory(token1, ITokenRegistry.TokenCategory.BRIDGED);

        vm.expectRevert();
        registry.setTrustLevel(token1, ITokenRegistry.TrustLevel.UNVERIFIED);

        vm.expectRevert();
        registry.removeToken(token1);

        vm.stopPrank();
    }

    // =========================================================================
    // Edge Cases
    // =========================================================================

    function test_EmptyRegistry() public view {
        address[] memory tokens = registry.getAllTokens();
        assertEq(tokens.length, 0);

        address[] memory collaterals = registry.getCollateralTokens();
        assertEq(collaterals.length, 0);

        address[] memory native = registry.getTokensByCategory(ITokenRegistry.TokenCategory.NATIVE);
        assertEq(native.length, 0);
    }

    function test_UpdateTimestamps() public {
        vm.startPrank(owner);

        uint256 registerTime = block.timestamp;
        registry.registerToken(token1, "Token", "TK", 18, ITokenRegistry.TokenCategory.NATIVE, ITokenRegistry.TrustLevel.TRUSTED, true, "");

        ITokenRegistry.TokenInfo memory info = registry.getTokenInfo(token1);
        assertEq(info.addedAt, registerTime);
        assertEq(info.updatedAt, registerTime);

        // Advance time and update
        uint256 updateTime = registerTime + 1 days;
        vm.warp(updateTime);
        vm.roll(block.number + 1);

        registry.updateTokenMetadata(token1, "New Token", "NTK", "");

        info = registry.getTokenInfo(token1);
        assertEq(info.addedAt, registerTime);
        assertEq(info.updatedAt, updateTime);

        vm.stopPrank();
    }

    // =========================================================================
    // Fuzz Tests
    // =========================================================================

    function testFuzz_RegisterToken(address token, uint8 decimals) public {
        vm.assume(token != address(0));
        decimals = uint8(bound(decimals, 0, 18));

        vm.prank(owner);
        registry.registerToken(
            token, "Fuzz Token", "FUZZ", decimals,
            ITokenRegistry.TokenCategory.NATIVE,
            ITokenRegistry.TrustLevel.UNVERIFIED,
            false, ""
        );

        assertTrue(registry.isRegistered(token));

        ITokenRegistry.TokenInfo memory info = registry.getTokenInfo(token);
        assertEq(info.decimals, decimals);
    }

    function testFuzz_MultipleRegistrations(uint8 count) public {
        count = uint8(bound(count, 1, 50));

        vm.startPrank(owner);

        for (uint8 i = 0; i < count; i++) {
            address token = address(uint160(0x10000 + i));
            registry.registerToken(
                token, "Token", "TK", 18,
                ITokenRegistry.TokenCategory.NATIVE,
                ITokenRegistry.TrustLevel.TRUSTED,
                i % 2 == 0, ""
            );
        }

        vm.stopPrank();

        assertEq(registry.tokenCount(), count);

        // Count collateral tokens (every even index)
        address[] memory collaterals = registry.getCollateralTokens();
        assertEq(collaterals.length, (count + 1) / 2);
    }
}
