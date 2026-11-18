import { accessToken } from "./google_auth.ts";

function assert(cond: unknown, msg: string): asserts cond {
  if (!cond) throw new Error(msg);
}

function fromB64url(s: string): Uint8Array<ArrayBuffer> {
  const b = atob(s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4));
  return Uint8Array.from(b, (c) => c.charCodeAt(0));
}

Deno.test("signs an RS256 JWT bearer assertion that verifies with the public key", async () => {
  const pair = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  );
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  let bin = "";
  for (const b of pkcs8) bin += String.fromCharCode(b);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(bin).replace(/(.{64})/g, "$1\n")}\n-----END PRIVATE KEY-----\n`;

  let assertion = "";
  const realFetch = globalThis.fetch;
  globalThis.fetch = (async (_url: string, init?: RequestInit) => {
    assertion = new URLSearchParams(init!.body as string).get("assertion")!;
    return new Response(JSON.stringify({ access_token: "ya29.test" }), { status: 200 });
  }) as typeof fetch;
  try {
    const token = await accessToken({ client_email: "push@example.iam.gserviceaccount.com", private_key: pem }, "scope-x");
    assert(token === "ya29.test", "returns the access token");
  } finally {
    globalThis.fetch = realFetch;
  }

  const [h, c, sig] = assertion.split(".");
  const claims = JSON.parse(new TextDecoder().decode(fromB64url(c)));
  assert(claims.iss === "push@example.iam.gserviceaccount.com", "issuer is the service account");
  assert(claims.scope === "scope-x", "scope is passed");
  assert(claims.exp - claims.iat === 3600, "valid for one hour");
  const ok = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    pair.publicKey,
    fromB64url(sig),
    new TextEncoder().encode(`${h}.${c}`),
  );
  assert(ok, "signature verifies");
});
