import {
  isRazorpayTestKeyId,
  razorpayBasicAuth,
  verifyHmacSha256Hex,
} from "./razorpay.ts";

Deno.test("accepts only Razorpay test key ids", () => {
  if (!isRazorpayTestKeyId("rzp_test_example")) {
    throw new Error("Expected test key to be accepted");
  }
  if (isRazorpayTestKeyId("rzp_live_example")) {
    throw new Error("Expected live key to be rejected");
  }
});

Deno.test("builds Razorpay Basic authentication header", () => {
  const expected = `Basic ${btoa("key:secret")}`;
  if (razorpayBasicAuth("key", "secret") !== expected) {
    throw new Error("Unexpected Basic authentication header");
  }
});

Deno.test("verifies HMAC SHA-256 signatures without string comparison", async () => {
  const valid = await verifyHmacSha256Hex(
    "secret",
    "order_123|pay_123",
    "13f113268a0357923e6390e6773754dc39c991f05a999bcaf04c161c59aeaaf8",
  );
  const invalid = await verifyHmacSha256Hex(
    "secret",
    "order_123|pay_123",
    "0".repeat(64),
  );
  if (!valid || invalid) throw new Error("HMAC verification failed");
});
