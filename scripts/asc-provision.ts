#!/usr/bin/env -S deno run --allow-read --allow-write --allow-run --allow-env --allow-net
// ===================================================================
// asc-provision — register com.pibulus.talktype and mint TalkType.provisionprofile
// via the App Store Connect API, reusing active team certificates already in
// the login keychain whenever present (zero unnecessary cert churn).
// ===================================================================
// USAGE:
//   ASC_ISSUER_ID=<uuid> deno run -A scripts/asc-provision.ts --check
//   ASC_ISSUER_ID=<uuid> deno run -A scripts/asc-provision.ts
// ===================================================================

const API = "https://api.appstoreconnect.apple.com/v1";
const TEAM_ID = "V433H655PN";
const BUNDLE_ID = "com.pibulus.talktype";
const APP_NAME = "TalkType";
const PROFILE_NAME = "TalkType MAS 2026";
const WORK_DIR = ".asc-work";
const PROFILE_OUT = "TalkType.provisionprofile";

const args = new Set(Deno.args);
const CHECK_ONLY = args.has("--check");

const say = (s: string) => console.log(s);
const ok = (s: string) => console.log(`  \x1b[32m✓\x1b[0m ${s}`);
const warn = (s: string) => console.log(`  \x1b[33m!\x1b[0m ${s}`);
const die = (s: string): never => {
  console.error(`\x1b[31m✗\x1b[0m ${s}`);
  Deno.exit(1);
};

function b64url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToBytes(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  const raw = atob(body);
  const buf = new ArrayBuffer(raw.length);
  const view = new Uint8Array(buf);
  for (let i = 0; i < raw.length; i++) view[i] = raw.charCodeAt(i);
  return buf;
}

async function makeJwt(keyPem: string, keyId: string, issuerId: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToBytes(keyPem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const enc = new TextEncoder();
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(enc.encode(JSON.stringify({ alg: "ES256", kid: keyId, typ: "JWT" })));
  const claims = b64url(enc.encode(JSON.stringify({
    iss: issuerId,
    iat: now,
    exp: now + 600,
    aud: "appstoreconnect-v1",
  })));
  const signingInput = `${header}.${claims}`;
  const sig = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, enc.encode(signingInput)),
  );
  return `${signingInput}.${b64url(sig)}`;
}

async function loadKeyId(): Promise<string> {
  const fromEnv = Deno.env.get("ASC_KEY_ID");
  if (fromEnv) return fromEnv;
  const home = Deno.env.get("HOME")!;
  for (const dir of [`${home}/.appstoreconnect/private_keys`, `${home}/.private_keys`]) {
    try {
      for await (const entry of Deno.readDir(dir)) {
        const m = entry.name.match(/^AuthKey_([A-Z0-9]{10})\.p8$/);
        if (m) return m[1];
      }
    } catch { /* ignore */ }
  }
  return die("No AuthKey_XXXXXXXXXX.p8 found in ~/.appstoreconnect/private_keys/");
}

async function loadKeyPem(keyId: string): Promise<string> {
  const home = Deno.env.get("HOME")!;
  for (const p of [
    `${home}/.appstoreconnect/private_keys/AuthKey_${keyId}.p8`,
    `${home}/.private_keys/AuthKey_${keyId}.p8`,
  ]) {
    try {
      return await Deno.readTextFile(p);
    } catch { /* next */ }
  }
  return die(`Cannot read AuthKey_${keyId}.p8`);
}

let TOKEN = "";
async function api(path: string, init: { method?: string; body?: unknown } = {}) {
  const res = await fetch(`${API}${path}`, {
    method: init.method ?? "GET",
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      "Content-Type": "application/json",
    },
    body: init.body ? JSON.stringify(init.body) : undefined,
  });
  const text = await res.text();
  let json: any = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = { raw: text };
  }
  return { status: res.status, json };
}

function apiError(what: string, r: { status: number; json: any }): never {
  const detail = r.json?.errors?.map((e: any) => `${e.title}: ${e.detail}`).join("; ") ??
    JSON.stringify(r.json);
  return die(`${what} failed (HTTP ${r.status}) — ${detail}`);
}

async function sha1Hex(bytes: Uint8Array): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-1", bytes));
  return Array.from(digest).map((b) => b.toString(16).padStart(2, "0")).join("").toUpperCase();
}

async function localIdentityHashes(): Promise<Set<string>> {
  const out = await new Deno.Command("security", { args: ["find-identity", "-v"] }).output();
  const txt = new TextDecoder().decode(out.stdout).toUpperCase();
  const set = new Set<string>();
  for (const m of txt.matchAll(/\b([0-9A-F]{40})\b/g)) set.add(m[1]);
  return set;
}

const keyId = await loadKeyId();
const issuerId = Deno.env.get("ASC_ISSUER_ID") ?? die("ASC_ISSUER_ID is not set");
TOKEN = await makeJwt(await loadKeyPem(keyId), keyId, issuerId);
ok(`Loaded App Store Connect key ${keyId} (${TEAM_ID})`);

const keychainHashes = await localIdentityHashes();

// 1. Bundle ID
const bundles = await api(`/bundleIds?filter[identifier]=${encodeURIComponent(BUNDLE_ID)}`);
if (bundles.status !== 200) apiError("Listing bundleIds", bundles);
let bundleResource = bundles.json.data?.[0];
if (!bundleResource) {
  if (CHECK_ONLY) {
    warn(`App ID ${BUNDLE_ID} is not registered yet`);
  } else {
    const created = await api("/bundleIds", {
      method: "POST",
      body: {
        data: {
          type: "bundleIds",
          attributes: { identifier: BUNDLE_ID, name: APP_NAME, platform: "MAC_OS" },
        },
      },
    });
    if (created.status >= 300) apiError("Registering App ID", created);
    bundleResource = created.json.data;
    ok(`Registered App ID ${BUNDLE_ID} (${bundleResource.id})`);
  }
} else {
  ok(`App ID ${BUNDLE_ID} exists (${bundleResource.id})`);
}

// 2. Match active Apple certificates against local Keychain private-key identities
const certs = await api("/certificates?limit=200");
if (certs.status !== 200) apiError("Listing certificates", certs);

let matchedDist: { id: string; sha1: string; der: Uint8Array } | null = null;
let matchedInstaller: { id: string; sha1: string; der: Uint8Array } | null = null;

for (const c of certs.json.data ?? []) {
  const type = c.attributes.certificateType;
  const der = Uint8Array.from(atob(c.attributes.certificateContent), (ch) => ch.charCodeAt(0));
  const sha1 = await sha1Hex(der);
  if (!keychainHashes.has(sha1)) continue;
  if ((type === "DISTRIBUTION" || type === "MAC_APP_DISTRIBUTION") && !matchedDist) {
    matchedDist = { id: c.id, sha1, der };
  }
  if (type === "MAC_INSTALLER_DISTRIBUTION" && !matchedInstaller) {
    matchedInstaller = { id: c.id, sha1, der };
  }
}

if (!matchedDist) {
  die("No active Apple Distribution certificate in App Store Connect matches a private key in login keychain.");
}
ok(`Matched active Apple Distribution cert ${matchedDist.id} (SHA-1 ${matchedDist.sha1})`);

if (!matchedInstaller) {
  die("No active Mac Installer Distribution certificate in App Store Connect matches a private key in login keychain.");
}
ok(`Matched active Mac Installer cert ${matchedInstaller.id} (SHA-1 ${matchedInstaller.sha1})`);

if (CHECK_ONLY) {
  say("\n--check complete: nothing modified.");
  Deno.exit(0);
}

// 3. Persist exact active .cer files so build.sh resolves non-revoked certs deterministically
await Deno.mkdir(WORK_DIR, { recursive: true });
await Deno.writeFile(`${WORK_DIR}/distribution.cer`, matchedDist.der);
await Deno.writeFile(`${WORK_DIR}/mac_installer_distribution.cer`, matchedInstaller.der);
ok(`Wrote active certificate pins to ${WORK_DIR}/`);

// 4. Create / refresh Mac App Store provisioning profile for com.pibulus.talktype
//
// Create first, retire second. The old order deleted every same-name profile and
// then created one, so any failure in between (rate limit, network, a bad cert
// relationship) left the account with zero profiles. Minting first means a failed
// run leaves the previous profile intact. Only Mac App Store profiles are pruned.
const existingProfiles = await api(`/profiles?filter[name]=${encodeURIComponent(PROFILE_NAME)}`);
const superseded = (existingProfiles.json?.data ?? []).filter(
  (p: { attributes?: { profileType?: string } }) => p?.attributes?.profileType === "MAC_APP_STORE",
);

const prof = await api("/profiles", {
  method: "POST",
  body: {
    data: {
      type: "profiles",
      attributes: { name: PROFILE_NAME, profileType: "MAC_APP_STORE" },
      relationships: {
        bundleId: { data: { type: "bundleIds", id: bundleResource.id } },
        certificates: { data: [{ type: "certificates", id: matchedDist.id }] },
      },
    },
  },
});
if (prof.status >= 300) apiError("Creating MAC_APP_STORE profile", prof);

for (const old of superseded) {
  if (old.id === prof.json.data.id) continue;
  const del = await api(`/profiles/${old.id}`, { method: "DELETE" });
  if (del.status < 300) warn(`Pruned superseded profile ${old.id} (${PROFILE_NAME})`);
}

const profileBytes = Uint8Array.from(
  atob(prof.json.data.attributes.profileContent),
  (c) => c.charCodeAt(0),
);
await Deno.writeFile(PROFILE_OUT, profileBytes);
ok(`Wrote ${PROFILE_OUT} (${profileBytes.length} bytes)`);
