/** EIP-712 payment terms a merchant signs for ProtectedPayments. */

import { ZeroAddress, ZeroHash } from "ethers";
import { SDKError, SDKErrorCode } from "../errors.js";
import {
  validateAddress,
  validateBytes32,
  validateNonZeroAddress,
  validatePositiveAmount,
} from "../utils/validation.js";

/** Merchant-signed payment offer. `buyer` may be the zero address for open offers. */
export interface ProtectedPaymentTerms {
  chainId: bigint;
  contractAddress: string;
  buyer: string;
  merchant: string;
  token: string;
  amount: bigint;
  /** Named arbiter, or the zero address to use the network default. */
  arbiter: string;
  fulfillBy: bigint;
  protectionWindow: bigint;
  orderRef: string;
  deadline: bigint;
}

/**
 * Build the EIP-712 payload a merchant signs to offer a protected payment.
 * Does not check chain state: arbiter eligibility, window bounds, token
 * allowlisting and order-reference reuse are enforced on-chain by `pay`.
 */
export function buildProtectedPaymentTypedData(terms: ProtectedPaymentTerms) {
  for (const [name, value, bits] of [
    ["chainId", terms.chainId, 256n],
    ["amount", terms.amount, 128n],
    ["fulfillBy", terms.fulfillBy, 64n],
    ["protectionWindow", terms.protectionWindow, 32n],
    ["deadline", terms.deadline, 64n],
  ] as const) {
    validatePositiveAmount(value, name);
    if (value >= 1n << bits) {
      throw new SDKError(SDKErrorCode.VALIDATION_ERROR, `${name} exceeds uint${bits}`);
    }
  }
  const orderRef = validateBytes32(terms.orderRef, "orderRef");
  if (orderRef === ZeroHash) throw new SDKError(SDKErrorCode.VALIDATION_ERROR, "orderRef cannot be zero");
  const contractAddress = validateNonZeroAddress(terms.contractAddress, "contractAddress");
  const merchant = validateNonZeroAddress(terms.merchant, "merchant");
  const buyer = validateAddress(terms.buyer, "buyer");
  const arbiter = validateAddress(terms.arbiter, "arbiter");
  if (buyer === merchant) throw new SDKError(SDKErrorCode.VALIDATION_ERROR, "buyer cannot be the merchant");
  if (arbiter !== ZeroAddress && (arbiter === merchant || arbiter === buyer)) {
    throw new SDKError(SDKErrorCode.VALIDATION_ERROR, "arbiter cannot be a party to the payment");
  }
  return {
    domain: { name: "SetProtectedPayments", version: "1", chainId: terms.chainId, verifyingContract: contractAddress },
    types: {
      PaymentTerms: [
        { name: "buyer", type: "address" },
        { name: "merchant", type: "address" },
        { name: "token", type: "address" },
        { name: "amount", type: "uint128" },
        { name: "arbiter", type: "address" },
        { name: "fulfillBy", type: "uint64" },
        { name: "protectionWindow", type: "uint32" },
        { name: "orderRef", type: "bytes32" },
        { name: "deadline", type: "uint64" },
      ],
    },
    value: {
      buyer,
      merchant,
      token: validateNonZeroAddress(terms.token, "token"),
      amount: terms.amount,
      arbiter,
      fulfillBy: terms.fulfillBy,
      protectionWindow: terms.protectionWindow,
      orderRef,
      deadline: terms.deadline,
    },
  };
}
