/**
 * Set Chain SDK - V2 Contract ABIs
 *
 * Minimal ABI fragments for agent interactions with SSDC V2 contracts.
 * Only includes the functions agents actually call.
 */

export const wSSDCVaultV2Abi = [
  "function asset() view returns (address)",
  "function totalAssets() view returns (uint256)",
  "function totalSupply() view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function convertToAssets(uint256 shares) view returns (uint256)",
  "function convertToShares(uint256 assets) view returns (uint256)",
  "function previewDeposit(uint256 assets) view returns (uint256)",
  "function previewRedeem(uint256 shares) view returns (uint256)",
  "function deposit(uint256 assets, address receiver) returns (uint256)",
  "function redeem(uint256 shares, address receiver, address owner) returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function transfer(address to, uint256 amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function deployReserve(uint256 amount) external",
  "function recallReserve(uint256 amount) external",
  "function deployedReserveAssets() view returns (uint256)",
  "function reserveFloor() view returns (uint256)",
  "function maxDeployBps() view returns (uint256)",
  "function reserveManager() view returns (address)",
  "event Transfer(address indexed from, address indexed to, uint256 value)",
  "event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares)",
  "event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares)",
  "event ReserveDeployed(address indexed manager, uint256 amount, uint256 totalDeployed)",
  "event ReserveRecalled(address indexed manager, uint256 amount, uint256 totalDeployed)",
] as const;

export const navControllerV2Abi = [
  "function currentNAVRay() view returns (uint256)",
  "function tryCurrentNAVRay() view returns (uint256 navRay, bool stale)",
  "function navEpoch() view returns (uint256)",
  "function nav0Ray() view returns (uint256)",
  "function ratePerSecondRay() view returns (uint256)",
  "function maxStaleness() view returns (uint40)",
  "function lastKnownGoodNAV() view returns (uint256)",
  "function updateNAV(uint256 attestedCurrentNAVRay, int256 forwardRateRay, uint64 newEpoch) external",
] as const;

export const yieldEscrowV2Abi = [
  "function fundEscrowFor(address buyer, address refundRecipient, address merchant, tuple(uint256 assetsDue, uint40 expiry, uint40 releaseAfter, uint40 maxNavAge, uint256 maxSharesIn, bool requiresFulfillment, uint8 fulfillmentType, uint8 requiredMilestones, uint40 challengeWindow, uint40 arbiterDeadline, uint8 disputeTimeoutResolution) terms, uint16 buyerBps) returns (uint256 escrowId, uint256 sharesLocked, uint256 committedAssets)",
  "function submitFulfillment(uint256 escrowId, bytes32 evidenceHash, uint8 milestoneNumber) external",
  "function release(uint256 escrowId) external",
  "function refund(uint256 escrowId) external",
  "function dispute(uint256 escrowId, uint8 reason, bytes32 reasonHash) external",
  "function disputeMilestone(uint256 escrowId, uint8 reason, uint8 milestoneNumber, bytes32 reasonHash) external",
  "function resolveDispute(uint256 escrowId, uint8 resolution, bytes32 evidenceHash) external",
  "function executeTimeout(uint256 escrowId) external",
  "function previewReleaseSplit(uint256 escrowId) view returns (tuple(uint256 totalShares, uint256 principalShares, uint256 grossYieldShares, uint256 reserveShares, uint256 feeShares, uint256 buyerYieldShares, uint256 merchantYieldShares))",
  "function previewSettlement(uint256 escrowId) view returns (tuple(uint8 status, bool releaseAfterPassed, bool fulfillmentSubmitted, bool fulfillmentComplete, bool disputeActive, bool disputeResolved, bool disputeTimedOut, bool requiresArbiterResolution, bool canBuyerRelease, bool canMerchantRelease, bool canArbiterRelease, bool canBuyerRefund, bool canArbiterRefund, bool canArbiterResolve, uint8 buyerReleaseMode, uint8 merchantReleaseMode, uint8 arbiterReleaseMode, uint8 buyerRefundMode, uint8 arbiterRefundMode, uint8 requiredMilestones, uint8 completedMilestones, uint8 nextMilestoneNumber, uint8 disputedMilestone, uint40 challengeWindowEndsAt, uint40 disputeWindowEndsAt))",
  "function escrows(uint256) view returns (address buyer, address merchant, address refundRecipient, uint256 sharesHeld, uint256 principalAssetsSnapshot, uint256 committedAssets, uint40 releaseAfter, uint16 buyerBps, uint8 status, bool requiresFulfillment, uint8 fulfillmentType, bool disputed, uint8 disputeReason, uint40 fulfilledAt, bytes32 fulfillmentEvidence, uint8 resolution, uint40 resolvedAt, bytes32 resolutionEvidence, uint40 challengeWindow, uint40 arbiterDeadline, uint8 timeoutResolution, uint40 disputedAt, uint8 settlementMode, uint40 settledAt)",
  "function nextEscrowId() view returns (uint256)",
  "function escrowCompletedMilestones(uint256 escrowId) view returns (uint8)",
  "function escrowRequiredMilestones(uint256 escrowId) view returns (uint8)",
  "event EscrowFunded(uint256 indexed escrowId, address indexed buyer, address indexed merchant, address refundRecipient, uint256 sharesIn, uint256 principalAssetsSnapshot, uint256 committedAssets, uint40 releaseAfter)",
  "event EscrowFulfillmentSubmitted(uint256 indexed escrowId, address indexed actor, uint8 indexed fulfillmentType, uint8 milestoneNumber, uint8 requiredMilestones, bytes32 evidenceHash, bool fulfillmentComplete, uint40 fulfilledAt)",
  "event EscrowReleased(uint256 indexed escrowId, address indexed actor, uint8 indexed settlementMode, uint256 totalShares, uint256 principalShares, uint256 buyerYieldShares, uint256 merchantYieldShares, uint256 reserveShares, uint256 feeShares)",
  "event EscrowRefunded(uint256 indexed escrowId, address indexed actor, address indexed recipient, uint8 settlementMode, uint256 sharesReturned)",
  "event EscrowDisputed(uint256 indexed escrowId, address indexed actor, uint8 indexed disputeReason, uint8 disputedMilestone, bytes32 reasonHash)",
  "event EscrowTimeoutExecuted(uint256 indexed escrowId, address indexed executor, uint8 indexed settlementMode, uint8 resolution)",
] as const;

export const ssdcClaimQueueV2Abi = [
  "function requestRedeem(uint256 shares, address receiver) returns (uint256 claimId)",
  "function claim(uint256 claimId) external",
  "function cancel(uint256 claimId, address receiver) external",
  "function claimStatus(uint256 claimId) view returns (uint8)",
  "function claimAssets(uint256 claimId) view returns (uint256)",
  "event RedeemRequested(uint256 indexed claimId, address indexed receiver, uint256 shares, uint256 assets)",
  "event ClaimSkipped(uint256 indexed claimId, uint256 assetsNeeded, uint256 availableBuffer)",
] as const;

export const ssdcPolicyModuleV2Abi = [
  "function policies(address) view returns (uint256 perTxLimitAssets, uint256 dailyLimitAssets, uint256 spentTodayAssets, uint40 dayStart, uint256 minAssetsFloor, uint256 committedAssets, uint40 sessionExpiry, bool enforceMerchantAllowlist, bool exists)",
  "function merchantAllowlist(address agent, address merchant) view returns (bool)",
  "function setPolicy(address agent, uint256 perTxLimitAssets, uint256 dailyLimitAssets, uint256 minAssetsFloor, uint40 sessionExpiry, bool enforceMerchantAllowlist) external",
  "function setMerchantAllowed(address agent, address merchant, bool allowed) external",
  "function consumeSpend(address agent, address merchant, uint256 assets) external",
  "function consumeGasSpend(address agent, uint256 assets) external",
  "function reserveCommittedSpend(address agent, uint256 assets) external",
  "function releaseCommittedSpend(address agent, uint256 assets) external",
  "event PolicyUpdated(address indexed agent, uint256 perTxLimitAssets, uint256 dailyLimitAssets, uint256 minAssetsFloor, uint40 sessionExpiry, bool enforceMerchantAllowlist)",
  "event PolicySpendConsumed(address indexed agent, uint256 assetsConsumed, uint256 spentTodayAssets)",
  "event PolicyGasSpendConsumed(address indexed agent, uint256 assetsConsumed, uint256 spentTodayAssets)",
] as const;

export const groundingRegistryV2Abi = [
  "function totalShares(address agent) view returns (uint256)",
  "function currentAssets(address agent) view returns (uint256)",
  "function isGroundedNow(address agent) view returns (bool)",
  "function poke(address agent) external",
] as const;

export const yieldPaymasterV2Abi = [
  "function gasTankShares(address agent) view returns (uint256)",
  "function topUpGasTankFor(address agent, uint256 shares) external",
  "function withdrawGasTank(uint256 shares, address to) external",
  "function previewChargeShares(uint256 gasCostWei) view returns (uint256 shares)",
] as const;

export const ssdcVaultGatewayV2Abi = [
  "function deposit(uint256 assets, address receiver, uint256 minSharesOut) returns (uint256 sharesOut)",
  "function mint(uint256 shares, address receiver, uint256 maxAssetsIn) returns (uint256 assetsIn)",
  "function withdraw(uint256 assets, address receiver, address owner, uint256 maxSharesBurned) returns (uint256 sharesBurned)",
  "function redeem(uint256 shares, address receiver, address owner, uint256 minAssetsOut) returns (uint256 assetsOut)",
  "function depositToGasTank(address paymaster, uint256 assets, address agent, uint256 minSharesOut) returns (uint256 sharesOut)",
  "function depositToEscrow(address escrow, address merchant, tuple(uint256 assetsDue, uint40 expiry, uint40 releaseAfter, uint40 maxNavAge, uint256 maxSharesIn, bool requiresFulfillment, uint8 fulfillmentType, uint8 requiredMilestones, uint40 challengeWindow, uint40 arbiterDeadline, uint8 disputeTimeoutResolution) terms, uint16 buyerBps, uint256 maxAssetsIn) returns (uint256 escrowId, uint256 sharesOut, uint256 assetsIn)",
  "event GatewayDeposit(address indexed caller, address indexed receiver, uint256 assetsIn, uint256 sharesOut)",
  "event GatewayEscrowFunded(address indexed caller, address indexed escrow, uint256 indexed escrowId, address merchant, uint256 assetsIn, uint256 sharesOut)",
] as const;

export const wssdcCrossChainBridgeV2Abi = [
  "function bridgeOut(uint32 dstChain, bytes32 recipient, uint256 shares) returns (bytes32 msgId)",
  "function canBridge(uint32 dstChain, uint256 shares) view returns (bool)",
  "function remainingMintCapacityShares() view returns (uint256)",
  "event BridgeOut(bytes32 indexed msgId, address indexed from, uint32 indexed dstChain, bytes32 recipient, uint256 shares)",
  "event BridgeIn(bytes32 indexed msgId, address indexed to, uint32 indexed srcChain, uint256 shares)",
] as const;

export const ssdcStatusLensV2Abi = [
  "function getStatus() view returns (tuple(bool transfersAllowed, bool navFresh, bool navConversionsAllowed, bool mintDepositAllowed, bool redeemWithdrawAllowed, bool requestRedeemAllowed, bool processQueueAllowed, bool bridgingAllowed, bool escrowOpsPaused, bool paymasterPaused))",
] as const;

export const erc20Abi = [
  "function balanceOf(address) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function transfer(address to, uint256 amount) returns (bool)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
] as const;
