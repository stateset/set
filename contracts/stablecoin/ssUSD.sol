// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IssUSD.sol";
import "./interfaces/INAVOracle.sol";

/**
 * @title ssUSD (Set Stablecoin USD)
 * @notice Rebasing stablecoin backed by T-Bills
 * @dev Internal shares-based accounting, external rebasing balanceOf
 *
 * Key mechanics:
 * - _shares[account]: Fixed internal accounting (only changes on transfer/mint/burn)
 * - balanceOf(account): Returns shares × NAV per share (rebases with yield)
 * - totalSupply(): Returns total shares × NAV per share
 *
 * This design allows yield distribution without gas costs per holder.
 */
contract ssUSD is
    IssUSD,
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    // =========================================================================
    // Constants
    // =========================================================================

    /// @notice Precision for calculations
    uint256 public constant PRECISION = 1e18;

    /// @notice Token decimals
    uint8 public constant DECIMALS = 18;

    // =========================================================================
    // Storage
    // =========================================================================

    /// @notice Token name
    string private _name;

    /// @notice Token symbol
    string private _symbol;

    /// @notice Shares per account
    mapping(address => uint256) private _shares;

    /// @notice Allowances (in amount terms, not shares)
    mapping(address => mapping(address => uint256)) private _allowances;

    /// @notice Total shares outstanding
    uint256 private _totalShares;

    /// @notice NAV oracle contract
    address public navOracle;

    /// @notice Treasury vault (only address that can mint/burn)
    address public treasuryVault;

    // =========================================================================
    // Errors
    // =========================================================================

    error NotTreasuryVault();
    error TransferToZeroAddress();
    error TransferFromZeroAddress();
    error TransferAmountExceedsBalance();
    error TransferSharesExceedsBalance();
    error ApproveToZeroAddress();
    error ApproveFromZeroAddress();
    error InsufficientAllowance();
    error MintToZeroAddress();
    error BurnFromZeroAddress();
    error BurnAmountExceedsBalance();

    // =========================================================================
    // Modifiers
    // =========================================================================

    modifier onlyTreasury() {
        if (msg.sender != treasuryVault) revert NotTreasuryVault();
        _;
    }

    // =========================================================================
    // Initialization
    // =========================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize ssUSD
     * @param owner_ Owner address
     * @param navOracle_ NAV oracle address
     */
    function initialize(
        address owner_,
        address navOracle_
    ) public initializer {
        __Ownable_init(owner_);
        __UUPSUpgradeable_init();

        _name = "Set Stablecoin USD";
        _symbol = "ssUSD";
        navOracle = navOracle_;
    }

    // =========================================================================
    // ERC20 Interface (Rebasing)
    // =========================================================================

    /**
     * @notice Token name
     */
    function name() external view returns (string memory) {
        return _name;
    }

    /**
     * @notice Token symbol
     */
    function symbol() external view returns (string memory) {
        return _symbol;
    }

    /**
     * @notice Token decimals
     */
    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }

    /**
     * @notice Total supply (rebasing)
     * @dev Returns total shares × NAV per share
     */
    function totalSupply() external view returns (uint256) {
        return _sharesToAmount(_totalShares);
    }

    /**
     * @notice Balance of account (rebasing)
     * @dev Returns shares × NAV per share
     */
    function balanceOf(address account) external view returns (uint256) {
        return _sharesToAmount(_shares[account]);
    }

    /**
     * @notice Transfer tokens
     */
    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    /**
     * @notice Get allowance
     */
    function allowance(
        address owner_,
        address spender
    ) external view returns (uint256) {
        return _allowances[owner_][spender];
    }

    /**
     * @notice Approve spender
     */
    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    /**
     * @notice Transfer from another account
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

    // =========================================================================
    // Shares Interface
    // =========================================================================

    /**
     * @notice Get shares of account
     */
    function sharesOf(address account) external view returns (uint256) {
        return _shares[account];
    }

    /**
     * @notice Get total shares
     */
    function totalShares() external view returns (uint256) {
        return _totalShares;
    }

    /**
     * @notice Convert amount to shares
     */
    function getSharesByAmount(uint256 amount) external view returns (uint256) {
        return _amountToShares(amount);
    }

    /**
     * @notice Convert shares to amount
     */
    function getAmountByShares(uint256 shares) external view returns (uint256) {
        return _sharesToAmount(shares);
    }

    /**
     * @notice Transfer shares directly
     */
    function transferShares(address to, uint256 shares) external returns (bool) {
        _transferShares(msg.sender, to, shares);
        return true;
    }

    /**
     * @notice Transfer shares from another account
     */
    function transferSharesFrom(
        address from,
        address to,
        uint256 shares
    ) external returns (bool) {
        uint256 amount = _sharesToAmount(shares);
        _spendAllowance(from, msg.sender, amount);
        _transferShares(from, to, shares);
        return true;
    }

    // =========================================================================
    // Minting/Burning (Treasury Only)
    // =========================================================================

    /**
     * @notice Mint shares
     * @param to Recipient
     * @param shares Shares to mint
     */
    function mintShares(address to, uint256 shares) external onlyTreasury {
        if (to == address(0)) revert MintToZeroAddress();

        _totalShares += shares;
        _shares[to] += shares;

        uint256 amount = _sharesToAmount(shares);
        emit Transfer(address(0), to, amount);
        emit SharesMinted(to, shares, amount);
    }

    /**
     * @notice Burn shares
     * @param from Account to burn from
     * @param shares Shares to burn
     */
    function burnShares(address from, uint256 shares) external onlyTreasury {
        if (from == address(0)) revert BurnFromZeroAddress();
        if (_shares[from] < shares) revert BurnAmountExceedsBalance();

        _shares[from] -= shares;
        _totalShares -= shares;

        uint256 amount = _sharesToAmount(shares);
        emit Transfer(from, address(0), amount);
        emit SharesBurned(from, shares, amount);
    }

    // =========================================================================
    // NAV Interface
    // =========================================================================

    /**
     * @notice Get current NAV per share
     */
    function getNavPerShare() external view returns (uint256) {
        return _getNavPerShare();
    }

    // =========================================================================
    // Admin Functions
    // =========================================================================

    /**
     * @notice Set treasury vault
     */
    function setTreasuryVault(address treasuryVault_) external onlyOwner {
        treasuryVault = treasuryVault_;
        emit TreasuryVaultUpdated(treasuryVault_);
    }

    /**
     * @notice Set NAV oracle
     */
    function setNavOracle(address navOracle_) external onlyOwner {
        navOracle = navOracle_;
    }

    // =========================================================================
    // Internal Functions
    // =========================================================================

    /**
     * @dev Get NAV per share from oracle
     */
    function _getNavPerShare() internal view returns (uint256) {
        if (navOracle == address(0)) {
            return PRECISION; // $1.00 default
        }
        return INAVOracle(navOracle).getCurrentNAVPerShare();
    }

    /**
     * @dev Convert amount to shares
     */
    function _amountToShares(uint256 amount) internal view returns (uint256) {
        uint256 nav = _getNavPerShare();
        return (amount * PRECISION) / nav;
    }

    /**
     * @dev Convert shares to amount
     */
    function _sharesToAmount(uint256 shares) internal view returns (uint256) {
        uint256 nav = _getNavPerShare();
        return (shares * nav) / PRECISION;
    }

    /**
     * @dev Transfer tokens (converts amount to shares internally)
     */
    function _transfer(address from, address to, uint256 amount) internal {
        if (from == address(0)) revert TransferFromZeroAddress();
        if (to == address(0)) revert TransferToZeroAddress();

        uint256 sharesToTransfer = _amountToShares(amount);

        if (_shares[from] < sharesToTransfer) {
            revert TransferAmountExceedsBalance();
        }

        _shares[from] -= sharesToTransfer;
        _shares[to] += sharesToTransfer;

        emit Transfer(from, to, amount);
        emit SharesTransferred(from, to, sharesToTransfer);
    }

    /**
     * @dev Transfer shares directly
     */
    function _transferShares(address from, address to, uint256 shares) internal {
        if (from == address(0)) revert TransferFromZeroAddress();
        if (to == address(0)) revert TransferToZeroAddress();
        if (_shares[from] < shares) revert TransferSharesExceedsBalance();

        _shares[from] -= shares;
        _shares[to] += shares;

        uint256 amount = _sharesToAmount(shares);
        emit Transfer(from, to, amount);
        emit SharesTransferred(from, to, shares);
    }

    /**
     * @dev Approve spender
     */
    function _approve(address owner_, address spender, uint256 amount) internal {
        if (owner_ == address(0)) revert ApproveFromZeroAddress();
        if (spender == address(0)) revert ApproveToZeroAddress();

        _allowances[owner_][spender] = amount;
        emit Approval(owner_, spender, amount);
    }

    /**
     * @dev Spend allowance
     */
    function _spendAllowance(
        address owner_,
        address spender,
        uint256 amount
    ) internal {
        uint256 currentAllowance = _allowances[owner_][spender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) revert InsufficientAllowance();
            _allowances[owner_][spender] = currentAllowance - amount;
        }
    }

    // =========================================================================
    // Upgrade
    // =========================================================================

    /**
     * @dev Authorize upgrade (owner only)
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
