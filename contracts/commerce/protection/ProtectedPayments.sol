// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ArbiterRegistry} from "./ArbiterRegistry.sol";

interface IVesInclusionVerifier {
    function verifyInclusion(bytes32 batchId, bytes32 leaf, bytes32[] calldata proof, uint256 index)
        external
        view
        returns (bool);
}

/// @title ProtectedPayments
/// @notice Stablecoin payments with card-network-style buyer protection:
///         disputes, merchant responses, negotiated or arbitrated partial
///         refunds, and chargebacks after the merchant has been paid, backed by
///         merchant reserves and a protection pool. Transfers stay final;
///         settlement terms carry the dispute rights. See docs/protected-payments.md.
/// @dev All settlement outputs (refunds, proceeds, bonds, fees) are credited and
///      pulled with `withdraw`, so one blocked recipient cannot freeze a dispute.
contract ProtectedPayments is AccessControl, ReentrancyGuard, EIP712 {
    using SafeERC20 for IERC20;

    bytes32 public constant UNDERWRITER_ROLE = keccak256("UNDERWRITER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    bytes32 public constant PAYMENT_TERMS_TYPEHASH = keccak256(
        "PaymentTerms(address buyer,address merchant,address token,uint128 amount,address arbiter,uint64 fulfillBy,uint32 protectionWindow,bytes32 orderRef,uint64 deadline)"
    );

    uint16 public constant MAX_TOTAL_FEE_BPS = 1000;
    uint32 public constant MAX_WINDOW = 365 days;

    enum Status {
        NONE,
        OPEN,
        DISPUTED,
        COMPLETED,
        REFUNDED
    }

    enum Stage {
        NONE,
        AWAITING_MERCHANT,
        ARBITRATION,
        CLOSED
    }

    /// @dev Card-network-style reason categories.
    enum DisputeReason {
        NONE,
        NOT_RECEIVED,
        NOT_AS_DESCRIBED,
        DEFECTIVE,
        UNAUTHORIZED,
        DUPLICATE,
        CANCELLED,
        OTHER
    }

    enum Outcome {
        NONE,
        MERCHANT_ACCEPTED,
        MERCHANT_DEFAULT,
        SETTLED,
        ARBITRATED,
        ARBITER_TIMEOUT
    }

    /// @notice Merchant-signed offer. `buyer == address(0)` lets anyone pay it.
    struct PaymentTerms {
        address buyer;
        address merchant;
        address token;
        uint128 amount;
        address arbiter;
        uint64 fulfillBy;
        uint32 protectionWindow;
        bytes32 orderRef;
        uint64 deadline;
    }

    struct Payment {
        address buyer;
        address merchant;
        address token;
        address arbiter;
        uint128 amount;
        uint128 held;
        uint128 reserveLocked;
        uint128 refunded;
        uint64 createdAt;
        uint64 fulfillBy;
        uint64 fulfilledAt;
        uint32 protectionWindow;
        uint16 protocolFeeBps;
        uint16 protectionFeeBps;
        Status status;
        bool instant;
        bytes32 orderRef;
    }

    struct Dispute {
        Stage stage;
        DisputeReason reason;
        Outcome outcome;
        bool reassigned;
        address arbiter;
        uint64 openedAt;
        uint64 deadline;
        uint128 requested;
        uint128 buyerBond;
        uint128 merchantFee;
        uint128 refundAwarded;
        // Settlement proposals are stored as amount + 1 so zero means "none".
        uint136 buyerProposal;
        uint136 merchantProposal;
    }

    struct TokenConfig {
        bool enabled;
        uint16 protocolFeeBps;
        uint16 protectionFeeBps;
        uint128 buyerDisputeBond;
        uint128 arbitrationFee;
    }

    struct Params {
        uint32 minProtectionWindow;
        uint32 maxProtectionWindow;
        uint32 merchantResponseWindow;
        uint32 arbitrationWindow;
        // Dispute monitoring: merchants whose disputes/payments ratio exceeds
        // maxDisputeRatioBps (after minPaymentsForRatio payments) lose instant
        // settlement until the ratio recovers. Zero disables the check.
        uint16 maxDisputeRatioBps;
        uint32 minPaymentsForRatio;
    }

    /// @notice Public dispute record, per merchant and per buyer. For merchants
    ///         `lost` counts disputes closed with any refund other than a
    ///         negotiated settlement; for buyers it counts outright arbitration losses.
    struct PartyStats {
        uint32 payments;
        uint32 disputes;
        uint32 lost;
    }

    struct MerchantRisk {
        bool instantSettlement;
        uint16 reserveRatioBps;
    }

    struct Reserve {
        uint128 free;
        uint128 locked;
        uint128 debt;
    }

    ArbiterRegistry public immutable arbiterRegistry;

    Params public params;
    address public defaultArbiter;
    address public feeRecipient;
    IVesInclusionVerifier public evidenceVerifier;
    bool public paymentsPaused;

    uint256 public nextPaymentId = 1;
    mapping(uint256 => Payment) internal _payments;
    mapping(uint256 => Dispute) internal _disputes;
    mapping(address => mapping(bytes32 => bool)) public orderRefUsed;

    mapping(address => TokenConfig) public tokenConfig;
    mapping(address => MerchantRisk) public merchantRisk;
    mapping(address => mapping(address => Reserve)) public reserves; // merchant => token
    mapping(address => uint256) public poolBalance; // token
    mapping(address => uint256) public protocolFeesAccrued; // token
    mapping(uint256 => uint128) public pendingClaims; // paymentId => unpaid buyer refund
    mapping(address => mapping(address => uint256)) public credits; // token => account
    mapping(address => PartyStats) public merchantStats;
    mapping(address => PartyStats) public buyerStats;

    error ZeroAddress();
    error Paused();
    error InvalidConfig();
    error TokenNotEnabled();
    error InvalidTerms();
    error TermsExpired();
    error OrderRefUsed();
    error BadSignature();
    error ArbiterNotEligible();
    error NoArbiter();
    error NotAuthorized();
    error InvalidStatus();
    error InvalidStage();
    error InvalidAmount();
    error InvalidEvidence();
    error DeadlineNotReached();
    error DeadlinePassed();
    error WindowOpen();
    error WindowClosed();
    error DebtOutstanding();
    error InsufficientReserve();
    error NothingToClaim();
    error UnsupportedTokenTransfer(uint256 expected, uint256 received);

    event PaymentCreated(
        uint256 indexed paymentId,
        address indexed buyer,
        address indexed merchant,
        address token,
        uint256 amount,
        address arbiter,
        bytes32 orderRef,
        bool instant,
        uint256 reserveLocked
    );
    event PaymentFulfilled(uint256 indexed paymentId, bytes32 evidenceHash, uint64 protectionEndsAt);
    event PaymentCompleted(uint256 indexed paymentId, uint256 merchantNet, uint256 protocolFee, uint256 protectionFee);
    event PaymentRefunded(uint256 indexed paymentId, uint256 amount, uint256 totalRefunded, bool full);
    event DisputeOpened(
        uint256 indexed paymentId, DisputeReason indexed reason, uint256 requested, uint256 bond, bytes32 evidenceHash
    );
    event DisputeContested(uint256 indexed paymentId, address indexed arbiter, uint256 fee, bytes32 evidenceHash);
    event SettlementProposed(uint256 indexed paymentId, address indexed by, uint256 refundAmount);
    event ArbiterReassigned(uint256 indexed paymentId, address indexed from, address indexed to);
    event DisputeClosed(uint256 indexed paymentId, Outcome indexed outcome, uint256 refundAwarded, bytes32 rulingHash);
    event VerifiedEvidenceAttached(uint256 indexed paymentId, address indexed by, bytes32 indexed batchId, bytes32 leaf);
    event ReserveDeposited(address indexed merchant, address indexed token, uint256 amount, uint256 debtRepaid);
    event ReserveWithdrawn(address indexed merchant, address indexed token, uint256 amount);
    event RefundSourced(
        uint256 indexed paymentId, uint256 fromLocked, uint256 fromFree, uint256 fromPool, uint256 pending
    );
    event PendingClaimPaid(uint256 indexed paymentId, uint256 amount, uint256 remaining);
    event Credited(address indexed token, address indexed account, uint256 amount);
    event Withdrawn(address indexed token, address indexed account, uint256 amount);
    event ProtocolFeesSwept(address indexed token, address indexed to, uint256 amount);
    event TokenConfigured(address indexed token, TokenConfig config);
    event ParamsUpdated(Params params);
    event MerchantRiskSet(address indexed merchant, bool instantSettlement, uint16 reserveRatioBps);
    event DefaultArbiterSet(address indexed arbiter);
    event FeeRecipientSet(address indexed feeRecipient);
    event EvidenceVerifierSet(address indexed verifier);
    event PaymentsPausedSet(bool paused);

    constructor(ArbiterRegistry arbiterRegistry_, address admin, address feeRecipient_, Params memory params_)
        EIP712("SetProtectedPayments", "1")
    {
        if (address(arbiterRegistry_) == address(0) || admin == address(0) || feeRecipient_ == address(0)) {
            revert ZeroAddress();
        }
        arbiterRegistry = arbiterRegistry_;
        feeRecipient = feeRecipient_;
        _setParams(params_);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UNDERWRITER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    // ═══ governance ═════════════════════════════════════════════════════════

    function setTokenConfig(address token, TokenConfig calldata config) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(0)) revert ZeroAddress();
        if (uint256(config.protocolFeeBps) + config.protectionFeeBps > MAX_TOTAL_FEE_BPS) revert InvalidConfig();
        tokenConfig[token] = config;
        emit TokenConfigured(token, config);
    }

    function setParams(Params calldata params_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setParams(params_);
    }

    function setDefaultArbiter(address arbiter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        defaultArbiter = arbiter;
        emit DefaultArbiterSet(arbiter);
    }

    function setFeeRecipient(address feeRecipient_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (feeRecipient_ == address(0)) revert ZeroAddress();
        feeRecipient = feeRecipient_;
        emit FeeRecipientSet(feeRecipient_);
    }

    function setEvidenceVerifier(IVesInclusionVerifier verifier) external onlyRole(DEFAULT_ADMIN_ROLE) {
        evidenceVerifier = verifier;
        emit EvidenceVerifierSet(address(verifier));
    }

    function setMerchantRisk(address merchant, bool instantSettlement, uint16 reserveRatioBps)
        external
        onlyRole(UNDERWRITER_ROLE)
    {
        if (merchant == address(0)) revert ZeroAddress();
        if (reserveRatioBps > 10_000) revert InvalidConfig();
        merchantRisk[merchant] = MerchantRisk(instantSettlement, reserveRatioBps);
        emit MerchantRiskSet(merchant, instantSettlement, reserveRatioBps);
    }

    /// @notice Blocks new payments only. Refunds, disputes, completions and
    ///         reserve deposits keep working so a pause cannot trap funds.
    function setPaymentsPaused(bool paused) external onlyRole(PAUSER_ROLE) {
        paymentsPaused = paused;
        emit PaymentsPausedSet(paused);
    }

    // ═══ payment ════════════════════════════════════════════════════════════

    /// @notice Pay a merchant-signed offer. The merchant is paid immediately when
    ///         its reserve covers the payment (instant mode); otherwise funds are
    ///         held until the protection window closes. Either way the buyer can
    ///         dispute until `fulfilledAt + protectionWindow`.
    function pay(PaymentTerms calldata terms, bytes calldata merchantSignature)
        external
        nonReentrant
        returns (uint256 paymentId)
    {
        if (paymentsPaused) revert Paused();
        TokenConfig memory cfg = tokenConfig[terms.token];
        if (!cfg.enabled) revert TokenNotEnabled();
        _validateTerms(terms);
        if (!SignatureChecker.isValidSignatureNow(terms.merchant, hashTerms(terms), merchantSignature)) {
            revert BadSignature();
        }
        orderRefUsed[terms.merchant][terms.orderRef] = true;

        _pull(terms.token, msg.sender, terms.amount);

        paymentId = nextPaymentId++;
        Payment storage p = _payments[paymentId];
        p.buyer = msg.sender;
        p.merchant = terms.merchant;
        p.token = terms.token;
        p.arbiter = terms.arbiter;
        p.amount = terms.amount;
        p.createdAt = uint64(block.timestamp);
        p.fulfillBy = terms.fulfillBy;
        p.protectionWindow = terms.protectionWindow;
        p.protocolFeeBps = cfg.protocolFeeBps;
        p.protectionFeeBps = cfg.protectionFeeBps;
        p.status = Status.OPEN;
        p.orderRef = terms.orderRef;

        // Gate on the merchant's record before this payment, then count it.
        if (!_tryInstantSettle(p)) {
            p.held = terms.amount;
        }
        merchantStats[terms.merchant].payments += 1;
        buyerStats[msg.sender].payments += 1;

        emit PaymentCreated(
            paymentId,
            msg.sender,
            terms.merchant,
            terms.token,
            terms.amount,
            terms.arbiter,
            terms.orderRef,
            p.instant,
            p.reserveLocked
        );
    }

    /// @notice Merchant records fulfillment, starting the protection window.
    function markFulfilled(uint256 paymentId, bytes32 evidenceHash) external {
        Payment storage p = _payments[paymentId];
        if (msg.sender != p.merchant) revert NotAuthorized();
        if (p.status != Status.OPEN || p.fulfilledAt != 0) revert InvalidStatus();
        if (evidenceHash == bytes32(0)) revert InvalidEvidence();
        if (block.timestamp > p.fulfillBy) revert DeadlinePassed();
        p.fulfilledAt = uint64(block.timestamp);
        emit PaymentFulfilled(paymentId, evidenceHash, uint64(block.timestamp) + p.protectionWindow);
    }

    /// @notice Buyer waives the remaining protection and completes the payment.
    function confirm(uint256 paymentId) external nonReentrant {
        Payment storage p = _payments[paymentId];
        if (msg.sender != p.buyer) revert NotAuthorized();
        if (p.status != Status.OPEN) revert InvalidStatus();
        _complete(paymentId, p);
    }

    /// @notice Anyone completes a fulfilled payment once its protection window closes.
    function finalize(uint256 paymentId) external nonReentrant {
        Payment storage p = _payments[paymentId];
        if (p.status != Status.OPEN || p.fulfilledAt == 0) revert InvalidStatus();
        if (block.timestamp < protectionEndsAt(paymentId)) revert WindowOpen();
        _complete(paymentId, p);
    }

    /// @notice Full refund of an order the merchant never fulfilled. The buyer may
    ///         call after `fulfillBy`; anyone may after `fulfillBy + protectionWindow`.
    function cancelUnfulfilled(uint256 paymentId) external nonReentrant {
        Payment storage p = _payments[paymentId];
        if (p.status != Status.OPEN || p.fulfilledAt != 0) revert InvalidStatus();
        if (block.timestamp <= p.fulfillBy) revert DeadlineNotReached();
        if (msg.sender != p.buyer && block.timestamp < uint256(p.fulfillBy) + p.protectionWindow) {
            revert NotAuthorized();
        }
        _refund(paymentId, p, p.amount - p.refunded);
        _closeRefunded(p);
    }

    /// @notice Voluntary merchant refund (returns, goodwill, cancellations).
    ///         Held payments refund from escrow; instant payments are funded from
    ///         the merchant's wallet.
    function merchantRefund(uint256 paymentId, uint128 amount) external nonReentrant {
        Payment storage p = _payments[paymentId];
        if (msg.sender != p.merchant) revert NotAuthorized();
        if (p.status != Status.OPEN) revert InvalidStatus();
        if (amount == 0 || amount > p.amount - p.refunded) revert InvalidAmount();

        p.refunded += amount;
        if (p.instant) {
            _pull(p.token, msg.sender, amount);
        } else {
            p.held -= amount;
        }
        _credit(p.token, p.buyer, amount);
        bool full = p.refunded == p.amount;
        emit PaymentRefunded(paymentId, amount, p.refunded, full);
        if (full) _closeRefunded(p);
    }

    // ═══ disputes ═══════════════════════════════════════════════════════════

    /// @notice Buyer disputes up to the non-refunded amount, posting the network
    ///         dispute bond. Open until the protection window closes.
    function openDispute(uint256 paymentId, DisputeReason reason, uint128 requested, bytes32 evidenceHash)
        external
        nonReentrant
    {
        Payment storage p = _payments[paymentId];
        if (msg.sender != p.buyer) revert NotAuthorized();
        if (p.status != Status.OPEN) revert InvalidStatus();
        if (reason == DisputeReason.NONE) revert InvalidConfig();
        if (requested == 0 || requested > p.amount - p.refunded) revert InvalidAmount();
        if (evidenceHash == bytes32(0)) revert InvalidEvidence();
        if (p.fulfilledAt != 0 && block.timestamp >= protectionEndsAt(paymentId)) revert WindowClosed();

        uint128 bond = tokenConfig[p.token].buyerDisputeBond;
        if (bond > 0) _pull(p.token, msg.sender, bond);

        p.status = Status.DISPUTED;
        merchantStats[p.merchant].disputes += 1;
        buyerStats[msg.sender].disputes += 1;
        Dispute storage d = _disputes[paymentId];
        d.stage = Stage.AWAITING_MERCHANT;
        d.reason = reason;
        d.openedAt = uint64(block.timestamp);
        d.deadline = uint64(block.timestamp) + params.merchantResponseWindow;
        d.requested = requested;
        d.buyerBond = bond;

        emit DisputeOpened(paymentId, reason, requested, bond, evidenceHash);
    }

    /// @notice Merchant concedes the claim in full.
    function acceptDispute(uint256 paymentId) external nonReentrant {
        (Payment storage p, Dispute storage d) = _activeDispute(paymentId, Stage.AWAITING_MERCHANT);
        if (msg.sender != p.merchant) revert NotAuthorized();
        _closeDispute(paymentId, p, d, d.requested, Outcome.MERCHANT_ACCEPTED, bytes32(0));
    }

    /// @notice Merchant contests the claim, paying the arbitration fee. The case
    ///         goes to the arbiter named in the signed terms, or the network
    ///         default if that arbiter is no longer eligible.
    function contest(uint256 paymentId, bytes32 evidenceHash) external nonReentrant {
        (Payment storage p, Dispute storage d) = _activeDispute(paymentId, Stage.AWAITING_MERCHANT);
        if (msg.sender != p.merchant) revert NotAuthorized();
        if (block.timestamp >= d.deadline) revert DeadlinePassed();
        if (evidenceHash == bytes32(0)) revert InvalidEvidence();

        address arbiter = p.arbiter;
        if (arbiter == address(0) || !arbiterRegistry.isEligible(arbiter)) {
            arbiter = defaultArbiter;
            if (arbiter == address(0) || !arbiterRegistry.isEligible(arbiter)) revert NoArbiter();
        }
        if (arbiter == p.buyer || arbiter == p.merchant) revert NoArbiter();

        uint128 fee = tokenConfig[p.token].arbitrationFee;
        if (fee > 0) _pull(p.token, msg.sender, fee);
        arbiterRegistry.openCase(arbiter);

        d.stage = Stage.ARBITRATION;
        d.arbiter = arbiter;
        d.merchantFee = fee;
        d.deadline = uint64(block.timestamp) + params.arbitrationWindow;

        emit DisputeContested(paymentId, arbiter, fee, evidenceHash);
    }

    /// @notice A merchant that does not respond in time loses the claim, as with
    ///         a card chargeback that is not represented.
    function executeDefault(uint256 paymentId) external nonReentrant {
        (Payment storage p, Dispute storage d) = _activeDispute(paymentId, Stage.AWAITING_MERCHANT);
        if (block.timestamp < d.deadline) revert DeadlineNotReached();
        _closeDispute(paymentId, p, d, d.requested, Outcome.MERCHANT_DEFAULT, bytes32(0));
    }

    /// @notice Either party proposes a refund amount. Matching proposals from
    ///         both parties settle the dispute immediately, before or during
    ///         arbitration; the arbitration fee is returned to the merchant.
    function proposeSettlement(uint256 paymentId, uint128 refundAmount) external nonReentrant {
        Payment storage p = _payments[paymentId];
        Dispute storage d = _disputes[paymentId];
        if (p.status != Status.DISPUTED) revert InvalidStatus();
        if (d.stage != Stage.AWAITING_MERCHANT && d.stage != Stage.ARBITRATION) revert InvalidStage();
        if (refundAmount > p.amount - p.refunded) revert InvalidAmount();

        uint136 encoded = uint136(refundAmount) + 1;
        uint136 counter;
        if (msg.sender == p.buyer) {
            d.buyerProposal = encoded;
            counter = d.merchantProposal;
        } else if (msg.sender == p.merchant) {
            d.merchantProposal = encoded;
            counter = d.buyerProposal;
        } else {
            revert NotAuthorized();
        }
        emit SettlementProposed(paymentId, msg.sender, refundAmount);

        if (counter == encoded) {
            if (d.stage == Stage.ARBITRATION) {
                arbiterRegistry.closeCase(d.arbiter, ArbiterRegistry.CaseOutcome.WITHDRAWN);
                _refundArbitrationFee(p, d);
            }
            _closeDispute(paymentId, p, d, refundAmount, Outcome.SETTLED, bytes32(0));
        }
    }

    /// @notice The case arbiter rules any refund from zero to the amount claimed.
    function resolve(uint256 paymentId, uint128 refundAmount, bytes32 rulingHash) external nonReentrant {
        (Payment storage p, Dispute storage d) = _activeDispute(paymentId, Stage.ARBITRATION);
        if (msg.sender != d.arbiter) revert NotAuthorized();
        if (block.timestamp >= d.deadline) revert DeadlinePassed();
        if (refundAmount > d.requested) revert InvalidAmount();
        if (rulingHash == bytes32(0)) revert InvalidEvidence();

        arbiterRegistry.closeCase(d.arbiter, ArbiterRegistry.CaseOutcome.RESOLVED);
        if (d.merchantFee > 0) {
            _credit(p.token, d.arbiter, d.merchantFee);
            d.merchantFee = 0;
        }
        _closeDispute(paymentId, p, d, refundAmount, Outcome.ARBITRATED, rulingHash);
    }

    /// @notice Anyone enforces a missed arbiter deadline: the arbiter is slashed,
    ///         the case moves once to the default arbiter, and a second miss
    ///         refunds the buyer's claim.
    function arbiterTimeout(uint256 paymentId) external nonReentrant {
        (Payment storage p, Dispute storage d) = _activeDispute(paymentId, Stage.ARBITRATION);
        if (block.timestamp < d.deadline) revert DeadlineNotReached();

        address missed = d.arbiter;
        arbiterRegistry.closeCase(missed, ArbiterRegistry.CaseOutcome.MISSED);

        address fallbackArbiter = defaultArbiter;
        if (
            !d.reassigned && fallbackArbiter != address(0) && fallbackArbiter != missed
                && fallbackArbiter != p.buyer && fallbackArbiter != p.merchant
                && arbiterRegistry.isEligible(fallbackArbiter)
        ) {
            arbiterRegistry.openCase(fallbackArbiter);
            d.reassigned = true;
            d.arbiter = fallbackArbiter;
            d.deadline = uint64(block.timestamp) + params.arbitrationWindow;
            emit ArbiterReassigned(paymentId, missed, fallbackArbiter);
            return;
        }

        _refundArbitrationFee(p, d);
        _closeDispute(paymentId, p, d, d.requested, Outcome.ARBITER_TIMEOUT, bytes32(0));
    }

    /// @notice Attach a VES event anchored in SetRegistry as evidence. The
    ///         contract proves inclusion; the arbiter interprets the event.
    function attachVerifiedEvidence(
        uint256 paymentId,
        bytes32 batchId,
        bytes32 leaf,
        bytes32[] calldata proof,
        uint256 index
    ) external {
        Payment storage p = _payments[paymentId];
        if (p.status != Status.OPEN && p.status != Status.DISPUTED) revert InvalidStatus();
        if (msg.sender != p.buyer && msg.sender != p.merchant && msg.sender != _disputes[paymentId].arbiter) {
            revert NotAuthorized();
        }
        IVesInclusionVerifier verifier = evidenceVerifier;
        if (address(verifier) == address(0) || !verifier.verifyInclusion(batchId, leaf, proof, index)) {
            revert InvalidEvidence();
        }
        emit VerifiedEvidenceAttached(paymentId, msg.sender, batchId, leaf);
    }

    // ═══ merchant reserve & protection pool ═════════════════════════════════

    /// @notice Deposit reserve. Outstanding debt to the protection pool is repaid first.
    function depositReserve(address token, uint128 amount) external nonReentrant {
        if (!tokenConfig[token].enabled) revert TokenNotEnabled();
        if (amount == 0) revert InvalidAmount();
        _pull(token, msg.sender, amount);
        Reserve storage r = reserves[msg.sender][token];
        uint128 repaid = amount < r.debt ? amount : r.debt;
        r.debt -= repaid;
        poolBalance[token] += repaid;
        r.free += amount - repaid;
        emit ReserveDeposited(msg.sender, token, amount, repaid);
    }

    function withdrawReserve(address token, uint128 amount) external nonReentrant {
        Reserve storage r = reserves[msg.sender][token];
        if (r.debt != 0) revert DebtOutstanding();
        if (amount == 0 || amount > r.free) revert InsufficientReserve();
        r.free -= amount;
        IERC20(token).safeTransfer(msg.sender, amount);
        emit ReserveWithdrawn(msg.sender, token, amount);
    }

    /// @notice Anyone may top up the protection pool.
    function fundPool(address token, uint128 amount) external nonReentrant {
        if (!tokenConfig[token].enabled) revert TokenNotEnabled();
        _pull(token, msg.sender, amount);
        poolBalance[token] += amount;
    }

    /// @notice Pay down a buyer refund that reserves and the pool could not cover
    ///         when it was awarded. Anyone may call as the pool refills.
    function claimPending(uint256 paymentId) external nonReentrant {
        uint128 owed = pendingClaims[paymentId];
        Payment storage p = _payments[paymentId];
        uint256 pool = poolBalance[p.token];
        if (owed == 0 || pool == 0) revert NothingToClaim();
        uint128 paid = pool < owed ? uint128(pool) : owed;
        poolBalance[p.token] = pool - paid;
        pendingClaims[paymentId] = owed - paid;
        _credit(p.token, p.buyer, paid);
        emit PendingClaimPaid(paymentId, paid, owed - paid);
    }

    function withdraw(address token) external nonReentrant {
        uint256 amount = credits[token][msg.sender];
        if (amount == 0) revert NothingToClaim();
        credits[token][msg.sender] = 0;
        IERC20(token).safeTransfer(msg.sender, amount);
        emit Withdrawn(token, msg.sender, amount);
    }

    function sweepProtocolFees(address token) external nonReentrant {
        uint256 amount = protocolFeesAccrued[token];
        if (amount == 0) revert NothingToClaim();
        protocolFeesAccrued[token] = 0;
        IERC20(token).safeTransfer(feeRecipient, amount);
        emit ProtocolFeesSwept(token, feeRecipient, amount);
    }

    // ═══ views ══════════════════════════════════════════════════════════════

    function hashTerms(PaymentTerms calldata terms) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    PAYMENT_TERMS_TYPEHASH,
                    terms.buyer,
                    terms.merchant,
                    terms.token,
                    terms.amount,
                    terms.arbiter,
                    terms.fulfillBy,
                    terms.protectionWindow,
                    terms.orderRef,
                    terms.deadline
                )
            )
        );
    }

    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function getPayment(uint256 paymentId) external view returns (Payment memory) {
        return _payments[paymentId];
    }

    function getDispute(uint256 paymentId) external view returns (Dispute memory) {
        return _disputes[paymentId];
    }

    /// @notice End of the dispute window, or 0 while unfulfilled (disputable any time).
    function protectionEndsAt(uint256 paymentId) public view returns (uint64) {
        Payment storage p = _payments[paymentId];
        if (p.fulfilledAt == 0) return 0;
        return p.fulfilledAt + p.protectionWindow;
    }

    /// @notice Instant-settlement exposure a merchant can still take for `token`.
    function instantCapacity(address merchant, address token) external view returns (uint256) {
        MerchantRisk memory risk = merchantRisk[merchant];
        Reserve memory r = reserves[merchant][token];
        if (!risk.instantSettlement || r.debt != 0 || disputeRatioExceeded(merchant)) return 0;
        if (risk.reserveRatioBps == 0) return type(uint256).max;
        return (uint256(r.free) * 10_000) / risk.reserveRatioBps;
    }

    /// @notice Merchant disputes per payment, in basis points.
    function disputeRatioBps(address merchant) public view returns (uint256) {
        PartyStats memory st = merchantStats[merchant];
        if (st.payments == 0) return 0;
        return (uint256(st.disputes) * 10_000) / st.payments;
    }

    /// @notice True when dispute monitoring has revoked instant settlement.
    function disputeRatioExceeded(address merchant) public view returns (bool) {
        Params memory pr = params;
        if (pr.maxDisputeRatioBps == 0) return false;
        PartyStats memory st = merchantStats[merchant];
        if (st.payments < pr.minPaymentsForRatio || st.payments == 0) return false;
        return uint256(st.disputes) * 10_000 > uint256(st.payments) * pr.maxDisputeRatioBps;
    }

    // ═══ internals ══════════════════════════════════════════════════════════

    function _validateTerms(PaymentTerms calldata terms) internal view {
        if (terms.amount == 0 || terms.merchant == address(0) || terms.merchant == msg.sender) revert InvalidTerms();
        if (terms.buyer != address(0) && terms.buyer != msg.sender) revert InvalidTerms();
        if (block.timestamp > terms.deadline) revert TermsExpired();
        if (terms.fulfillBy <= block.timestamp) revert InvalidTerms();
        Params memory pr = params;
        if (terms.protectionWindow < pr.minProtectionWindow || terms.protectionWindow > pr.maxProtectionWindow) {
            revert InvalidTerms();
        }
        if (orderRefUsed[terms.merchant][terms.orderRef]) revert OrderRefUsed();
        if (terms.arbiter != address(0)) {
            if (terms.arbiter == terms.merchant || terms.arbiter == msg.sender) revert ArbiterNotEligible();
            if (!arbiterRegistry.isEligible(terms.arbiter)) revert ArbiterNotEligible();
        }
    }

    function _tryInstantSettle(Payment storage p) internal returns (bool) {
        MerchantRisk memory risk = merchantRisk[p.merchant];
        if (!risk.instantSettlement || disputeRatioExceeded(p.merchant)) return false;
        Reserve storage r = reserves[p.merchant][p.token];
        if (r.debt != 0) return false;
        uint256 lock = (uint256(p.amount) * risk.reserveRatioBps + 9999) / 10_000;
        if (lock > r.free) return false;

        r.free -= uint128(lock);
        r.locked += uint128(lock);
        p.reserveLocked = uint128(lock);
        p.instant = true;

        (uint256 protocolFee, uint256 protectionFee) = _fees(p, p.amount);
        protocolFeesAccrued[p.token] += protocolFee;
        poolBalance[p.token] += protectionFee;
        IERC20(p.token).safeTransfer(p.merchant, p.amount - protocolFee - protectionFee);
        return true;
    }

    function _activeDispute(uint256 paymentId, Stage stage)
        internal
        view
        returns (Payment storage p, Dispute storage d)
    {
        p = _payments[paymentId];
        d = _disputes[paymentId];
        if (p.status != Status.DISPUTED) revert InvalidStatus();
        if (d.stage != stage) revert InvalidStage();
    }

    function _closeDispute(
        uint256 paymentId,
        Payment storage p,
        Dispute storage d,
        uint128 refundAmount,
        Outcome outcome,
        bytes32 rulingHash
    ) internal {
        d.stage = Stage.CLOSED;
        d.outcome = outcome;
        d.refundAwarded = refundAmount;

        bool buyerLost = outcome == Outcome.ARBITRATED && refundAmount == 0;
        if (buyerLost) {
            buyerStats[p.buyer].lost += 1;
        } else if (refundAmount > 0 && outcome != Outcome.SETTLED) {
            merchantStats[p.merchant].lost += 1;
        }

        uint128 bond = d.buyerBond;
        if (bond > 0) {
            // The bond is forfeited to the merchant only when an arbiter awards nothing.
            _credit(p.token, buyerLost ? p.merchant : p.buyer, bond);
            d.buyerBond = 0;
        }

        emit DisputeClosed(paymentId, outcome, refundAmount, rulingHash);

        if (refundAmount > 0) _refund(paymentId, p, refundAmount);
        if (p.refunded == p.amount) {
            _closeRefunded(p);
        } else {
            _complete(paymentId, p);
        }
    }

    function _refundArbitrationFee(Payment storage p, Dispute storage d) internal {
        if (d.merchantFee > 0) {
            _credit(p.token, p.merchant, d.merchantFee);
            d.merchantFee = 0;
        }
    }

    /// @dev Credits `amount` to the buyer. Held payments pay from escrow. Instant
    ///      payments pay from the payment's locked reserve, then free reserve, then
    ///      the pool (as merchant debt), and record any remainder as a pending claim.
    function _refund(uint256 paymentId, Payment storage p, uint128 amount) internal {
        p.refunded += amount;
        uint128 payable_ = amount;

        if (!p.instant) {
            p.held -= amount;
        } else {
            Reserve storage r = reserves[p.merchant][p.token];
            uint128 fromLocked = amount < p.reserveLocked ? amount : p.reserveLocked;
            p.reserveLocked -= fromLocked;
            r.locked -= fromLocked;
            uint128 rest = amount - fromLocked;

            uint128 fromFree = rest < r.free ? rest : r.free;
            r.free -= fromFree;
            rest -= fromFree;

            uint256 pool = poolBalance[p.token];
            uint128 fromPool = rest < pool ? rest : uint128(pool);
            poolBalance[p.token] = pool - fromPool;
            rest -= fromPool;

            // Pool advances and unpaid remainders are both merchant debt; repayment
            // refills the pool, from which pending claims are paid.
            r.debt += fromPool + rest;
            if (rest > 0) pendingClaims[paymentId] += rest;
            payable_ = amount - rest;
            emit RefundSourced(paymentId, fromLocked, fromFree, fromPool, rest);
        }

        if (payable_ > 0) _credit(p.token, p.buyer, payable_);
        emit PaymentRefunded(paymentId, amount, p.refunded, p.refunded == p.amount);
    }

    function _complete(uint256 paymentId, Payment storage p) internal {
        p.status = Status.COMPLETED;
        uint256 net;
        uint256 protocolFee;
        uint256 protectionFee;
        if (p.instant) {
            _unlockReserve(p);
        } else {
            uint128 held = p.held;
            p.held = 0;
            (protocolFee, protectionFee) = _fees(p, held);
            protocolFeesAccrued[p.token] += protocolFee;
            poolBalance[p.token] += protectionFee;
            net = held - protocolFee - protectionFee;
            if (net > 0) _credit(p.token, p.merchant, net);
        }
        emit PaymentCompleted(paymentId, net, protocolFee, protectionFee);
    }

    function _closeRefunded(Payment storage p) internal {
        p.status = Status.REFUNDED;
        if (p.instant) _unlockReserve(p);
    }

    function _unlockReserve(Payment storage p) internal {
        uint128 locked = p.reserveLocked;
        if (locked == 0) return;
        p.reserveLocked = 0;
        Reserve storage r = reserves[p.merchant][p.token];
        r.locked -= locked;
        r.free += locked;
    }

    function _fees(Payment storage p, uint256 amount) internal view returns (uint256 protocolFee, uint256 protectionFee) {
        protocolFee = (amount * p.protocolFeeBps) / 10_000;
        protectionFee = (amount * p.protectionFeeBps) / 10_000;
    }

    function _credit(address token, address account, uint256 amount) internal {
        credits[token][account] += amount;
        emit Credited(token, account, amount);
    }

    function _pull(address token, address from, uint256 amount) internal {
        uint256 before = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(from, address(this), amount);
        uint256 received = IERC20(token).balanceOf(address(this)) - before;
        if (received != amount) revert UnsupportedTokenTransfer(amount, received);
    }

    function _setParams(Params memory p) internal {
        if (
            p.minProtectionWindow == 0 || p.minProtectionWindow > p.maxProtectionWindow
                || p.maxProtectionWindow > MAX_WINDOW || p.merchantResponseWindow == 0 || p.arbitrationWindow == 0
                || p.maxDisputeRatioBps > 10_000
        ) revert InvalidConfig();
        params = p;
        emit ParamsUpdated(p);
    }
}
