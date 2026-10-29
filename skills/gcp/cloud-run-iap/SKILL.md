---
name: cloud-run-iap
description: Conventions for deploying Cloud Run services protected by Identity-Aware Proxy (IAP) — the GA-as-of-March-2026 "IAP-direct" pattern that enables IAP via a single `--iap` flag, NO external load balancer, no extra cost. Covers gcloud commands, IAM bindings (IAP service agent → roles/run.invoker, end users → roles/iap.httpsResourceAccessor), per-service vs shared service-account choice, when an LB is still required (custom domain, Cloud Armor, single domain for multiple services), and the SPA + BFF deployment shape. Trigger when deploying a Cloud Run service that needs browser-side auth, choosing between IAP-direct and IAP-with-LB, planning SPA + API on Cloud Run, or designing per-service IAM. For CI/CD wiring of these deploys, see `cloud-run-cicd-gha`.
---

# Cloud Run + IAP (no load balancer)

Since March 2026 GA, IAP can be enabled **directly on a Cloud Run service**
with `--iap`. No external HTTPS Load Balancer required, no extra cost. This
is the default pattern for any browser-facing Cloud Run service that needs
Google sign-in at the edge.

## When to use IAP-direct vs IAP+LB

| Need | IAP-direct | IAP + external LB |
|---|---|---|
| Browser sign-in via Google identity | ✓ | ✓ |
| `run.app` URL is fine | ✓ | — |
| Custom domain | run.app domain mapping (region-limited) | full L7 LB → custom domain |
| Single domain for many services (path routing) | one service per URL | ✓ (URL maps) |
| Cloud Armor / WAF | — | ✓ |
| Cloud CDN | — | ✓ |
| Cost | $0 extra | ~$18+/month (forwarding rule + egress) |

**Default to IAP-direct.** Step up to LB only when one of the right-column
needs becomes real.

## Reference deploy

```bash
PROJECT=my-runtime-project
REGION=europe-west1
SERVICE=my-app
IMAGE=europe-west1-docker.pkg.dev/my-platform/docker/my-app:abc123
SA=my-app-runtime@${PROJECT}.iam.gserviceaccount.com

# 1. Deploy the service with IAP enabled at the edge.
gcloud run deploy "${SERVICE}" \
  --region="${REGION}" \
  --project="${PROJECT}" \
  --image="${IMAGE}" \
  --port=8080 \
  --service-account="${SA}" \
  --no-allow-unauthenticated \
  --iap

# 2. Grant the IAP service agent the right to invoke Cloud Run on behalf of
#    authenticated users. One-time per service.
PROJECT_NUMBER=$(gcloud projects describe "${PROJECT}" --format='value(projectNumber)')
gcloud run services add-iam-policy-binding "${SERVICE}" \
  --region="${REGION}" --project="${PROJECT}" \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-iap.iam.gserviceaccount.com" \
  --role=roles/run.invoker

# 3. Grant end users the IAP web access role.
gcloud iap web add-iam-policy-binding \
  --region="${REGION}" --project="${PROJECT}" \
  --resource-type=cloud-run --service="${SERVICE}" \
  --member=user:alice@example.com \
  --role=roles/iap.httpsResourceAccessor

# Or grant a Google Group (preferred for teams):
gcloud iap web add-iam-policy-binding \
  --region="${REGION}" --project="${PROJECT}" \
  --resource-type=cloud-run --service="${SERVICE}" \
  --member=group:engineering@example.com \
  --role=roles/iap.httpsResourceAccessor

# 4. Verify.
gcloud run services describe "${SERVICE}" --region="${REGION}" --project="${PROJECT}" \
  | grep -i iap   # → "Iap Enabled: true"
```

## What IAP forwards to your app

Once IAP is enabled, every request reaching the Cloud Run service carries
three headers (set by IAP, stripped from incoming requests so clients can't
spoof them):

| Header | Use |
|---|---|
| `X-Goog-Authenticated-User-Email` | Informational, e.g. `accounts.google.com:alice@example.com`. |
| `X-Goog-Authenticated-User-Id` | Informational, stable Google account ID. |
| `X-Goog-IAP-JWT-Assertion` | **The source of truth.** Signed JWT — verify it before trusting any identity claim. |

Verify the JWT against IAP's public keys
(`https://www.gstatic.com/iap/verify/public_key-jwk`). Expected `aud`:
`/projects/PROJECT_NUMBER/global/backendServices/...` for LB-backed IAP,
or the Cloud Run service identifier for IAP-direct (check the
service-issued docs; the value is shown by
`gcloud run services describe`).

The informational headers are useful for logging but **must not** be the
basis of auth decisions — they can be set by anyone if IAP is bypassed
(misconfig, network mishap, future regression). Always validate the JWT.

## Service account: one per service, not shared

**Default: one runtime SA per Cloud Run service.** Even when two services
sit next to each other (SPA + BFF, or web + worker).

| Why per-service | Notes |
|---|---|
| Least privilege | Each SA only gets what *that* service needs (Secret Manager keys, GCS bucket, Cloud SQL client, etc.). |
| Blast radius | Compromise of one service can't escalate via permissions the other has. |
| Audit | Cloud Audit Logs show *which* service made each call. |
| Rotation / revocation | Disable one SA without touching the other. |
| Cost | SAs are free, no quota concerns. |

Naming convention: `<service>-runtime@<project>.iam.gserviceaccount.com`.
Examples: `orders-bff-runtime@…`, `orders-ui-runtime@…`.

**A shared SA is only justified** when:
- The "services" are really one logical app split for scale (e.g.
  three identical workers behind a queue).
- You're a team of one prototyping and the IAM cleanup cost dominates.
  Even then, plan to split on the way to production.

## SPA + BFF deployment shape (IAP-direct)

```
[Browser] ─── IAP gate ───► UI (Cloud Run, --iap, nginx static)
   │
   └──── IAP gate ───► BFF (Cloud Run, --iap, FastAPI)
            (browser calls BFF cross-origin with CORS)
```

Both services public-routed but `--no-allow-unauthenticated --iap` so only
IAP can reach Cloud Run. Each gets its own runtime SA and its own IAP
binding for the user/group that's allowed in.

CORS is still required on the BFF (the browser is calling a different
origin than the UI). Set the BFF's `CORS_ORIGIN` env var to the UI's
`run.app` URL.

`VITE_API_BASE_URL` (baked into the UI bundle at build time) must point at
the BFF's `run.app` URL. Three ways to resolve the chicken-and-egg
(BFF URL needed at UI build time):

1. **Map both services to custom domains you control** (e.g.
   `api.example.com`, `app.example.com`). Bundle uses the known custom
   domain, deploy order is independent.
2. **Two-pass deploy**: deploy BFF first → grab its URL → rebuild UI with
   `VITE_API_BASE_URL=<bff-url>` → deploy UI. Easy in CI.
3. **Single domain via external LB** (the option that justifies paying
   for the LB) — drops CORS entirely.

## Gotcha: same-origin proxy → private BFF — strip `X-Serverless-Authorization`

An alternative (often better) SPA + BFF shape: front **only the UI** with IAP,
keep the **BFF private** (`--no-allow-unauthenticated`, no `--iap`, invoker IAM
only), and have the UI's server reverse-proxy `/api` → BFF **server-to-server**.
Same-origin → no CORS, and the IAP session cookie just works. The UI runtime SA
holds `roles/run.invoker` on the BFF; the UI server mints an OIDC ID token
(`audience = BFF URL`) from the metadata server and sends it as
`Authorization: Bearer …` on each proxied call.

**The trap:** when IAP fronts the UI, it injects an **`X-Serverless-Authorization`**
header (IAP's *own* invoker token for the UI hop, `aud = UI service`) into the
request reaching the UI. A naive reverse-proxy forwards *all* inbound headers to
the BFF — including that one. And **Cloud Run's invoker check prefers
`X-Serverless-Authorization` over `Authorization`.** So the BFF validates IAP's
UI-audience token against *itself* → audience mismatch → **`401 "The access
token could not be verified"`** — even though your `Authorization` header carries
a perfectly valid BFF-audience token (it's simply ignored).

Maddening to debug: `gcloud`/`curl` to the BFF with a correct token returns 200
(no `X-Serverless-Authorization` present), but the proxied request 401s. The 401
is logged by Cloud Run *before* your app runs (no app access-log line for it).

**Fix:** strip `x-serverless-authorization` (with the hop-by-hop headers) before
forwarding. Keep forwarding `x-goog-iap-jwt-assertion` so the BFF still derives
the user identity.

```js
const STRIP = new Set([
  "host", "content-length", "connection", "keep-alive", "transfer-encoding",
  "x-serverless-authorization", // ← IAP's UI-hop invoker token; Cloud Run would
                                //    prefer it over our Authorization → BFF 401
]);
const headers = {};
for (const [k, v] of Object.entries(req.headers))
  if (!STRIP.has(k.toLowerCase())) headers[k] = v;
headers.authorization = `Bearer ${await mintOidcToken(BFF_URL)}`; // aud = BFF
// x-goog-iap-jwt-assertion is preserved → BFF reads the verified user identity
```

Related IAM detail for the 401-vs-403 tell: `roles/run.admin` does **not**
include `run.invoker`; the UI SA needs an explicit `roles/run.invoker` on the
BFF. A valid token *without* invoker yields **403**; the
`X-Serverless-Authorization` mismatch yields **401**. Use that distinction to
separate "wrong/extra token" (401) from "missing IAM" (403).

## When IAP-direct is NOT enough

Switch to the IAP+LB pattern when:
- Multiple Cloud Run services must share a single browser-facing domain
  (path routing).
- You need Cloud Armor (WAF), Cloud CDN, or other LB-only features.
- You need an external static IP.
- IAP regional limitations bite (check the GA region list in the docs).

The IAP+LB pattern uses a **serverless NEG** as the LB backend and enables
IAP on the LB's backend service. Cloud Run is set to
`ingress=internal-and-cloud-load-balancing` so the run.app URL is
unreachable. Same IAP IAM model (`roles/iap.httpsResourceAccessor`).
