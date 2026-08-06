const encoder = new TextEncoder();

function hexBytes(value: string): Uint8Array<ArrayBuffer> | null {
  if (!/^[0-9a-f]{64}$/i.test(value)) return null;
  const bytes = new Uint8Array(value.length / 2);
  for (let index = 0; index < value.length; index += 2) {
    bytes[index / 2] = Number.parseInt(value.slice(index, index + 2), 16);
  }
  return bytes;
}

export function isRazorpayTestKeyId(keyId: string): boolean {
  return keyId.trim().startsWith("rzp_test_");
}

export function razorpayBasicAuth(keyId: string, keySecret: string): string {
  return `Basic ${btoa(`${keyId}:${keySecret}`)}`;
}

export async function verifyHmacSha256Hex(
  secret: string,
  message: string,
  signature: string,
): Promise<boolean> {
  const signatureBytes = hexBytes(signature.trim());
  if (secret.length === 0 || !signatureBytes) return false;

  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
  return crypto.subtle.verify(
    "HMAC",
    key,
    signatureBytes,
    encoder.encode(message),
  );
}
