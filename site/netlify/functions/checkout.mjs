// Square checkout for TalkType for Mac.
//
// POST /api/checkout → a Square Payment Link whose redirect lands on
// /thanks.html?checkout_id=… . No card ever touches this site: Square hosts the
// form, the site only asks Square to mint the link.
//
// Netlify function shape (v2): `export default async (request) => Response`.
// The same module runs under Deno or Node 18+ — only `process.env` needs
// swapping for `Deno.env` if it is ever hosted there.
//
// Env:
//   SQUARE_ACCESS_TOKEN   required
//   SQUARE_LOCATION_ID    required
//   SQUARE_ENVIRONMENT    "production" | "sandbox"  (sandbox unless told)
//   SQUARE_API_VERSION    optional, defaults below
//   SITE_URL              optional; otherwise the request origin is used, which
//                         keeps the redirect on whichever host sold the app

export const PRODUCT = {
  id: 'talktype-mac',
  name: 'TalkType for Mac (Lifetime)',
  amountCents: 2900, // A$29.00 one-time price. Mirror it in site HTML.
  currency: 'AUD'
};

const SANDBOX_BASE = 'https://connect.squareupsandbox.com';
const PRODUCTION_BASE = 'https://connect.squareup.com';
const DEFAULT_VERSION = '2026-01-22';
const DEFAULT_SITE = 'https://mac.talktype.app';
const ALLOWED_ORIGINS = new Set([
  'https://mac.talktype.app',
  'https://talktype.app'
]);

function resolveSiteUrl(context, request) {
  const netlifySite = context?.site?.url?.replace(/\/$/, '');
  if (netlifySite && /^https:\/\/[a-z0-9.-]+$/i.test(netlifySite)) {
    return netlifySite;
  }
  const origin = request.headers.get('origin')?.replace(/\/$/, '');
  if (origin && ALLOWED_ORIGINS.has(origin)) {
    return origin;
  }
  return DEFAULT_SITE;
}

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' }
  });

function config(env) {
  const environment = env.SQUARE_ENVIRONMENT === 'production' ? 'production' : 'sandbox';
  return {
    token: env.SQUARE_ACCESS_TOKEN || '',
    locationId: env.SQUARE_LOCATION_ID || '',
    environment,
    baseUrl: environment === 'production' ? PRODUCTION_BASE : SANDBOX_BASE,
    apiVersion: env.SQUARE_API_VERSION || DEFAULT_VERSION,
    siteUrl: (env.SITE_URL || DEFAULT_SITE).replace(/\/$/, '')
  };
}

// An AU seller location charges AUD. Ask Square rather than assume it, because
// a location can change currency and a wrong currency is an instant 400.
async function chargeCurrency(cfg) {
  try {
    const res = await fetch(`${cfg.baseUrl}/v2/locations/${encodeURIComponent(cfg.locationId)}`, {
      headers: { authorization: `Bearer ${cfg.token}`, 'square-version': cfg.apiVersion }
    });
    const payload = await res.json().catch(() => ({}));
    const currency = payload?.location?.currency;
    if (res.ok && typeof currency === 'string' && /^[A-Z]{3}$/.test(currency)) return currency;
  } catch (error) {
    console.error('[talktype-checkout] location lookup failed', error);
  }
  return PRODUCT.currency;
}

export async function createSquareCheckout(env = process.env) {
  const cfg = config(env);
  if (!cfg.token || !cfg.locationId) {
    const error = new Error('Square is not configured');
    error.code = 'unconfigured';
    throw error;
  }

  const checkoutId = crypto.randomUUID();
  const currency = await chargeCurrency(cfg);
  const redirectUrl = `${cfg.siteUrl}/thanks.html?checkout_id=${encodeURIComponent(checkoutId)}`;

  const res = await fetch(`${cfg.baseUrl}/v2/online-checkout/payment-links`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${cfg.token}`,
      'square-version': cfg.apiVersion,
      'content-type': 'application/json'
    },
    body: JSON.stringify({
      idempotency_key: checkoutId,
      description: `${PRODUCT.name} (${checkoutId})`,
      quick_pay: {
        name: PRODUCT.name,
        price_money: { amount: PRODUCT.amountCents, currency },
        location_id: cfg.locationId
      },
      checkout_options: {
        redirect_url: redirectUrl,
        merchant_support_email: 'pibulus@gmail.com',
        ask_for_shipping_address: false,
        accepted_payment_methods: { apple_pay: true, google_pay: true }
      },
      payment_note: `${PRODUCT.name} ${checkoutId}`
    })
  });

  const payload = await res.json().catch(() => ({}));
  if (!res.ok || !payload?.payment_link?.url) {
    console.error('[talktype-checkout] Square refused', res.status, payload);
    const error = new Error('Square refused the checkout request');
    error.code = 'refused';
    error.status = res.status;
    error.details = payload?.errors || null;
    throw error;
  }

  return {
    checkoutId,
    checkoutUrl: payload.payment_link.long_url || payload.payment_link.url,
    amount: PRODUCT.amountCents,
    currency,
    environment: cfg.environment
  };
}

export default async function handler(request, context) {
  if (request.method !== 'POST') {
    return json({ error: 'POST only' }, 405);
  }

  // Netlify exposes the deploy URL here; it keeps the redirect correct on
  // branch deploys without hardcoding the host.
  const baseEnv = typeof process !== 'undefined'
    ? process.env
    : (globalThis.Deno?.env?.toObject?.() || {});
  const env = { ...baseEnv };
  if (!env.SITE_URL) {
    env.SITE_URL = resolveSiteUrl(context, request);
  }

  try {
    const result = await createSquareCheckout(env);
    return json({ ok: true, ...result });
  } catch (error) {
    if (error.code === 'unconfigured') {
      return json({ error: 'Checkout is not wired up yet.' }, 503);
    }
    return json({ error: 'Square did not open a checkout. Try again in a moment.' }, 502);
  }
}
