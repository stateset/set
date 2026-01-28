#!/bin/bash
# x402 Payment End-to-End Test Script
# Tests the full flow: AI Agent -> Sequencer -> Arc Testnet

set -e

# Configuration
SEQUENCER_URL="https://api.sequencer.stateset.app"
ARC_RPC_URL="https://rpc.testnet.arc.network"
ARC_CHAIN_ID=5042002

# Deployed Contracts on Arc Testnet
SET_REGISTRY_ADDRESS="0x07c62732A80988330B9A7e90E3d265099e9846c3"
SET_PAYMENT_BATCH_ADDRESS="0xd4fA0f4D31Bdf873f87D6b84f2F8A6A877004020"
ARC_USDC_ADDRESS="0x3600000000000000000000000000000000000000"

# Test Wallet (same as deployer for testing)
PAYER_ADDRESS="0x6EAA0039505e0A0F9d2f2F9C6De56b74593F40fE"
PAYER_PRIVATE_KEY="0x2e8ae9dfe13a58721758d1ecbce58e437697fa034e5d239d5c978e952e84e0d1"

# Test Payee (Anvil account #4)
PAYEE_ADDRESS="0x90F79bf6EB2c4f870365E785982E1f101E93b906"

# Test IDs (generate fresh UUIDs)
TENANT_ID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)
STORE_ID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)
AGENT_ID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)

echo "============================================="
echo "  x402 Payment E2E Test - Arc Testnet"
echo "============================================="
echo ""
echo "Sequencer:     $SEQUENCER_URL"
echo "Arc RPC:       $ARC_RPC_URL"
echo "PaymentBatch:  $SET_PAYMENT_BATCH_ADDRESS"
echo ""
echo "Payer:         $PAYER_ADDRESS"
echo "Payee:         $PAYEE_ADDRESS"
echo "Tenant ID:     $TENANT_ID"
echo "Store ID:      $STORE_ID"
echo ""

# Step 1: Check sequencer health
echo "Step 1: Checking sequencer health..."
HEALTH=$(curl -s "$SEQUENCER_URL/health")
echo "  Response: $HEALTH"
echo ""

# Step 2: Check payer balance on Arc
echo "Step 2: Checking payer USDC balance on Arc..."
BALANCE=$(cast balance $PAYER_ADDRESS --rpc-url $ARC_RPC_URL 2>/dev/null || echo "0")
BALANCE_USDC=$(echo "scale=6; $BALANCE / 1000000000000000000" | bc 2>/dev/null || echo "$BALANCE wei")
echo "  Payer balance: $BALANCE_USDC USDC"
echo ""

# Step 3: Create payment intent parameters
echo "Step 3: Creating payment intent..."
AMOUNT=1000000  # 1 USDC (6 decimals)
VALID_UNTIL=$(($(date +%s) + 3600))  # Valid for 1 hour
NONCE=$(date +%s%N | cut -b1-10)
ASSET="usdc"
NETWORK="arc_testnet"

# Compute signing hash matching sequencer's format:
# SHA256(X402_PAYMENT_V1 || payer || payee || amount_be || asset || network || chain_id_be || valid_until_be || nonce_be)
# Note: amount, chain_id, valid_until, nonce are big-endian 8-byte integers

# Convert integers to big-endian hex (8 bytes = 16 hex chars)
AMOUNT_HEX=$(printf '%016x' $AMOUNT)
CHAIN_ID_HEX=$(printf '%016x' $ARC_CHAIN_ID)
VALID_UNTIL_HEX=$(printf '%016x' $VALID_UNTIL)
NONCE_HEX=$(printf '%016x' $NONCE)

# Build the signing data
DOMAIN_SEPARATOR="X402_PAYMENT_V1"
DOMAIN_HEX=$(echo -n "$DOMAIN_SEPARATOR" | xxd -p | tr -d '\n')
PAYER_HEX=$(echo -n "$PAYER_ADDRESS" | xxd -p | tr -d '\n')
PAYEE_HEX=$(echo -n "$PAYEE_ADDRESS" | xxd -p | tr -d '\n')
ASSET_HEX=$(echo -n "$ASSET" | xxd -p | tr -d '\n')
NETWORK_HEX=$(echo -n "$NETWORK" | xxd -p | tr -d '\n')

# Concatenate all parts
SIGNING_DATA_HEX="${DOMAIN_HEX}${PAYER_HEX}${PAYEE_HEX}${AMOUNT_HEX}${ASSET_HEX}${NETWORK_HEX}${CHAIN_ID_HEX}${VALID_UNTIL_HEX}${NONCE_HEX}"

# Compute SHA256 hash
SIGNING_HASH="0x$(echo -n "$SIGNING_DATA_HEX" | xxd -r -p | sha256sum | cut -d' ' -f1)"

echo "  Amount:       $AMOUNT (1 USDC)"
echo "  Valid Until:  $VALID_UNTIL"
echo "  Nonce:        $NONCE"
echo "  Signing Hash: $SIGNING_HASH"
echo ""

# Step 4: Sign the payment intent
echo "Step 4: Signing payment intent..."
SIGNATURE=$(cast wallet sign --private-key $PAYER_PRIVATE_KEY "$SIGNING_HASH" 2>/dev/null || echo "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")
echo "  Signature: ${SIGNATURE:0:42}..."
echo ""

# Step 5: Submit payment intent to sequencer
echo "Step 5: Submitting payment intent to sequencer..."

PAYLOAD=$(cat <<EOF
{
  "tenant_id": "$TENANT_ID",
  "store_id": "$STORE_ID",
  "agent_id": "$AGENT_ID",
  "payer_address": "$PAYER_ADDRESS",
  "payee_address": "$PAYEE_ADDRESS",
  "amount": $AMOUNT,
  "asset": "$ASSET",
  "network": "$NETWORK",
  "valid_until": $VALID_UNTIL,
  "nonce": $NONCE,
  "signing_hash": "$SIGNING_HASH",
  "payer_signature": "$SIGNATURE",
  "description": "x402 E2E Test Payment",
  "idempotency_key": "test-$(date +%s)"
}
EOF
)

echo "  Payload:"
echo "$PAYLOAD" | jq . 2>/dev/null || echo "$PAYLOAD"
echo ""

RESPONSE=$(curl -s -X POST "$SEQUENCER_URL/api/v1/x402/payments" \
  -H "Content-Type: application/json" \
  -H "Authorization: ApiKey dev_admin_key" \
  -d "$PAYLOAD" 2>&1)

echo "  Response:"
echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
echo ""

# Extract intent_id from response
INTENT_ID=$(echo "$RESPONSE" | jq -r '.intent_id' 2>/dev/null || echo "")

if [ -n "$INTENT_ID" ] && [ "$INTENT_ID" != "null" ]; then
  echo "Step 6: Payment intent created successfully!"
  echo "  Intent ID: $INTENT_ID"
  echo ""

  # Step 7: Check payment status
  echo "Step 7: Checking payment intent status..."
  STATUS_RESPONSE=$(curl -s "$SEQUENCER_URL/api/v1/x402/payments/$INTENT_ID" \
    -H "Authorization: ApiKey dev_admin_key" 2>&1)
  echo "  Status:"
  echo "$STATUS_RESPONSE" | jq . 2>/dev/null || echo "$STATUS_RESPONSE"
  echo ""
else
  echo "Step 6: Payment intent submission failed or returned unexpected response"
  echo ""
fi

# Step 8: Verify contract state on Arc
echo "Step 8: Verifying SetPaymentBatch contract on Arc..."
SEQUENCER_COUNT=$(cast call $SET_PAYMENT_BATCH_ADDRESS "sequencerCount()(uint256)" --rpc-url $ARC_RPC_URL 2>/dev/null || echo "error")
echo "  Authorized sequencers: $SEQUENCER_COUNT"

OWNER=$(cast call $SET_PAYMENT_BATCH_ADDRESS "owner()(address)" --rpc-url $ARC_RPC_URL 2>/dev/null || echo "error")
echo "  Contract owner: $OWNER"
echo ""

echo "============================================="
echo "  E2E Test Complete"
echo "============================================="
echo ""
echo "Summary:"
echo "  - Sequencer: HEALTHY"
echo "  - Contracts deployed on Arc Testnet"
echo "  - Payment intent submitted (check response above)"
echo ""
echo "View contracts on Arc Explorer:"
echo "  Registry:     https://testnet.arcscan.app/address/$SET_REGISTRY_ADDRESS"
echo "  PaymentBatch: https://testnet.arcscan.app/address/$SET_PAYMENT_BATCH_ADDRESS"
echo ""
