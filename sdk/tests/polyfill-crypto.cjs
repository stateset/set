"use strict";

const cryptoModule = require("crypto");
const webcrypto = cryptoModule.webcrypto;

if (
  typeof cryptoModule.getRandomValues !== "function" &&
  webcrypto &&
  typeof webcrypto.getRandomValues === "function"
) {
  cryptoModule.getRandomValues = webcrypto.getRandomValues.bind(webcrypto);
}

// Keep vitest runnable on Node versions where globalThis.crypto is missing
// or exposed without Web Crypto methods like getRandomValues.
if (
  typeof globalThis.crypto === "undefined" ||
  typeof globalThis.crypto.getRandomValues !== "function"
) {
  globalThis.crypto = webcrypto;
}
