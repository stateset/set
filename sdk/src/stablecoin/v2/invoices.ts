import { ZeroHash } from "ethers";
import { SDKError, SDKErrorCode } from "../../errors.js";
import { validateBytes32, validateNonZeroAddress, validatePositiveAmount } from "../../utils/validation.js";

export interface MerchantInvoice {
  chainId: bigint;
  accountAddress: string;
  merchant: string;
  vault: string;
  orderId: string;
  assets: bigint;
  deadline: bigint;
}

/**
 * Build the exact EIP-712 merchant invoice for the signature-required account.
 * Does not submit/sign, authenticate a checkout, query chain configuration or
 * assert that a signature is valid. Use reviewed deployment addresses and obtain
 * the merchant's signature; a session key cannot sign on the merchant's behalf.
 */
export function buildMerchantInvoiceTypedData(invoice: MerchantInvoice) {
  for (const [name, value, bits] of [
    ["chainId", invoice.chainId, 256n],
    ["assets", invoice.assets, 256n],
    ["deadline", invoice.deadline, 40n],
  ] as const) {
    validatePositiveAmount(value, name);
    if (value >= 1n << bits) {
      throw new SDKError(SDKErrorCode.VALIDATION_ERROR, `${name} exceeds uint${bits}`);
    }
  }
  const orderId = validateBytes32(invoice.orderId, "orderId");
  if (orderId === ZeroHash) throw new SDKError(SDKErrorCode.VALIDATION_ERROR, "orderId cannot be zero");
  const accountAddress = validateNonZeroAddress(invoice.accountAddress, "accountAddress");
  const merchant = validateNonZeroAddress(invoice.merchant, "merchant");
  if (accountAddress === merchant) {
    throw new SDKError(SDKErrorCode.VALIDATION_ERROR, "merchant cannot be the payment account");
  }
  return {
    domain: { name: "AgentPaymentAccountV2", version: "1", chainId: invoice.chainId, verifyingContract: accountAddress },
    types: {
      Invoice: [
        { name: "orderId", type: "bytes32" },
        { name: "merchant", type: "address" },
        { name: "vault", type: "address" },
        { name: "assets", type: "uint256" },
        { name: "deadline", type: "uint40" },
      ],
    },
    value: { orderId, merchant, vault: validateNonZeroAddress(invoice.vault, "vault"), assets: invoice.assets, deadline: invoice.deadline },
  };
}
