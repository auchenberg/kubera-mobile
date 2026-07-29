# Settings & authentication

Status: proposal. Scope: how Kubera Mobile stores, shows, edits, and validates
the credentials it needs, plus a verdict on whether OAuth can replace them.

## TL;DR

- Credentials are entered in two unrelated places today (sign-in for key/secret,
  Settings → Growth history for the MCP token). Collapse them into **one
  "Connect Kubera account" screen** used for both first-run and later edits, and
  give Settings a real **Kubera account** section that owns all three credentials
  with per-credential masked display, replace-in-place, and live status.
- Status is per-surface, not global: `REST: connected · History: connected`.
  Balances come from the HMAC REST API; growth history comes only from MCP. One
  can work while the other is broken, and today the UI can't say which.
- **OAuth exists and works, but is closed to us today.** Kubera publishes RFC 9728
  and RFC 8414 metadata with `authorization_code` + `refresh_token`, PKCE `S256`,
  and public clients (`"none"`). Tested live, though: despite advertising
  `client_id_metadata_document_supported: true`, the server never fetches a client
  metadata document — client lookup is a **registry read**, and only clients Kubera
  registered (e.g. Claude's MCP integration) resolve. Ours returns
  `1003 Invalid input`. OAuth therefore needs Kubera to add us; it is not
  something this app can adopt on its own. Full evidence in
  [OAuth: verdict](#oauth-verdict).
- Plan: phase 1 unified connect screen + Settings IA (done), phase 2
  per-credential validation and status (done), phase 3 OAuth **parked** pending a
  registration from Kubera. The MCP token stays the history credential — and it is
  required, not optional: Kubera serves history only over MCP.

## Research findings

### What credentials Kubera actually issues

From `https://help.kubera.com/article/167-kubera-mcp-config`:

- One creation flow, in Kubera on desktop: **Settings → API → Create New API
  Key / MCP Token**. The help page treats "API Key / MCP Token" as a single
  concept and calls the resulting value `AUTH_TOKEN`.
- MCP endpoints: `https://api.kubera.com/api/v1/mcp` and
  `https://api.kubera.com/api/v2/mcp`.
- Header format: `Authorization: Basic <AUTH_TOKEN>` — the token is pasted whole,
  it is *not* base64 of `user:pass` despite the `Basic` scheme name. The page
  notes one client (Perplexity) needs the bare value with no `Basic` prefix,
  which confirms the scheme word is decoration.
- The page says nothing about OAuth and nothing about token expiry.

So Kubera's own docs describe **two** things that the same Settings → API page
emits: an HMAC key pair (`apiKey` + `secret`, used by `Shared/KuberaAPI.swift`
with `x-api-token` / `x-timestamp` / `x-signature`) and an MCP token used as a
bearer-ish `Basic` credential. They are not interchangeable: the MCP endpoint
rejects the REST API key with `Kubera MCP: Invalid apiKey`, and the REST v3
history paths 404 while the web app's `chartAndCAGR` rejects HMAC auth with 401.
That asymmetry is the whole reason the app needs three fields.

### OAuth evidence

Live probing (already done; do not repeat destructively):

`POST https://api.kubera.com/api/v1/mcp` with no auth → **HTTP 401** with

```
www-authenticate: Bearer error="invalid_token",
  error_description="Missing Authorization header",
  scope="read_profile read_portfolio write_portfolio",
  resource_metadata="https://api.kubera.com/.well-known/oauth-protected-resource"
```

`POST https://api.kubera.com/api/v2/mcp` with no auth → **HTTP 400**
`{"error":"Kubera MCP: missing authorization header"}` — no OAuth hints at all.

`GET https://api.kubera.com/.well-known/oauth-protected-resource` (RFC 9728):

```json
{
  "resource": "https://api.kubera.com/api/v1/mcp",
  "authorization_servers": ["https://api.kubera.com"],
  "scopes_supported": ["read_profile", "read_portfolio", "write_portfolio"],
  "bearer_methods_supported": ["header"],
  "client_id_metadata_document_supported": true
}
```

`GET https://api.kubera.com/.well-known/oauth-authorization-server` (RFC 8414):

```json
{
  "issuer": "https://api.kubera.com",
  "authorization_endpoint": "https://app.kubera.com/oauth/authorize",
  "token_endpoint": "https://api.kubera.com/api/v1/public/oauth2/token",
  "revocation_endpoint": "https://api.kubera.com/api/v1/public/oauth2/revoke",
  "response_types_supported": ["code"],
  "grant_types_supported": ["authorization_code", "refresh_token"],
  "token_endpoint_auth_methods_supported": ["none", "client_secret_post"],
  "code_challenge_methods_supported": ["S256"],
  "scopes_supported": ["read_profile", "read_portfolio", "write_portfolio"],
  "client_id_metadata_document_supported": true
}
```

`GET https://api.kubera.com/.well-known/openid-configuration` → **HTTP 404**, so
this is plain OAuth 2.0, not OpenID Connect: there is no ID token and no userinfo
endpoint, and no second metadata document that might have hidden a
`registration_endpoint`. The absence of dynamic client registration is therefore
a real property of the deployment, not a gap in where we looked.

Read line by line, this is a complete public-client OAuth deployment:

| Requirement for a native app | Kubera's answer |
| --- | --- |
| Auth code flow | `response_types_supported: ["code"]` |
| PKCE (mandatory, no secret) | `code_challenge_methods_supported: ["S256"]` |
| Client with no secret | `token_endpoint_auth_methods_supported` includes `"none"` |
| Long-lived access without re-prompt | `refresh_token` grant |
| Client identity without a Kubera-side signup | no `registration_endpoint`, but `client_id_metadata_document_supported: true` |
| Revocation on disconnect | `revocation_endpoint` present |

`client_id_metadata_document_supported` is the OAuth Client ID Metadata Document
mechanism (the IETF successor to IndieAuth's client discovery, adopted by the
MCP ecosystem as the lighter alternative to RFC 7591): instead of registering,
the client uses an **HTTPS URL as its `client_id`**, and the authorization server
fetches that URL to read the client's metadata (`client_name`, `redirect_uris`,
`logo_uri`, …). For an open-source app this is nearly free — the document is a
static JSON file on GitHub Pages.

Three caveats, stated plainly because they are the difference between "spec it"
and "ship it":

1. **The redirect URI is constrained by where the metadata document is hosted.**
   `draft-ietf-oauth-client-id-metadata-document` requires an HTTPS `client_id`
   *with a path*, whose document repeats that URL verbatim in its own `client_id`.
   For native clients it further requires `redirect_uris` to be `http://localhost`
   or a **custom scheme matching the client_id hostname in reverse-domain order**,
   written `scheme:/path` (one colon, one slash).

   The scheme is **`com.kubera.mobile`**, matching the bundle id, giving
   `com.kubera.mobile:/oauth-callback`. Read strictly, the draft would want that
   scheme's document hosted at `mobile.kubera.com`; in practice most servers only
   check the redirect against the `redirect_uris` in the metadata document, which
   can live anywhere. That is the one thing the live test below has to settle.

   Remaining unknown for the live test: whether Kubera's authorize endpoint
   enforces the host reversal strictly, or merely checks that the redirect
   matches one listed in the metadata document. Worth noting either way: asking
   Kubera to bless the document would make this a sanctioned client rather than
   an unofficial one.
   Register exactly that scheme in `CFBundleURLTypes` and pass only the scheme
   to `ASWebAuthenticationSession`'s `callbackURLScheme`. It matches the app's
   bundle id, `com.kubera.mobile`.
2. **OAuth covers the MCP resource, not the HMAC REST API.** The
   protected-resource document names exactly one `resource`:
   `.../api/v1/mcp`. Nothing suggests these bearer tokens authenticate
   `x-api-token`-style REST calls. So OAuth definitely replaces the MCP token; it
   replaces the key/secret only if the app moves *all* reads onto MCP tools.
   That looks feasible — Kubera's public MCP surface advertises
   `list_portfolios`, `get_portfolio`, `get_portfolio_history`,
   `get_portfolio_cagr`, `get_top_movers`, and `get_profile`, which is a superset
   of what the widgets need — but it is a data-layer rewrite, not a login change,
   and it should be a separate decision from the auth work.
3. **The app currently talks to v2, and v2 is the non-OAuth endpoint.**
   `Shared/KuberaMCP.swift` posts to `/api/v2/mcp`, which answers unauthenticated
   requests with a bare 400 and advertises no OAuth metadata. OAuth lives on v1.
   Any OAuth migration therefore also means re-verifying `get_portfolio_history`
   against v1 — the two versions differ in more than a path segment.

### Competitor patterns worth copying

Finance apps converge on the same shape, and it is not "a form":

- **Monarch / Copilot Money**: one **Accounts / Connections** list in Settings.
  Each row is a connection with a status chip (`Connected`, `Needs attention`) and
  a relative last-synced time. A broken connection gets a **Fix** affordance on
  the row — never "remove and re-add". Re-auth is additive and never destroys
  cached data.
- **Revolut**: identity/session (Account) is separate from device behaviour
  (Security & privacy), and destructive actions sit at the bottom behind an extra
  tap, never adjacent to a toggle.
- For multi-field credential entry: one labelled field per row, a paste button in
  the field rather than relying on long-press, reveal toggles instead of
  permanent `SecureField` blindness, validation on blur *per field*, and an error
  attached to the field that failed. Never clear typed values on error.

The through-line: **a connection is an object with state**, not a form
submission. Today's Settings shows a masked key and a token box, so it reads as a
form. That's the gap to close.

## Proposed Settings IA

Order top to bottom (rationale: identity → what the widgets show → device
behaviour → boilerplate → destructive):

```
Settings
├─ Kubera account                     ← new, owns ALL credentials
│   ├─ status header: "Connected"
│   │     REST · connected · balances updated 4 min ago
│   │     History · not connected · "Kubera MCP: Invalid Token"
│   ├─ API key       kbra••••1234        [Replace]
│   ├─ API secret    ••••••••            [Replace]
│   ├─ MCP token     not set             [Add]        · unlocks growth history
│   └─ [Update credentials] → opens the ConnectView sheet
├─ Widget portfolio                   ← unchanged, hidden while list is empty
│   └─ rows, tap to pick, "On widgets" marker
├─ Preferences                        ← unchanged (Face ID / Privacy / Compact)
├─ Data & privacy                     ← unchanged explainer, moves below Prefs
└─ Disconnect Kubera                  ← destructive, stays last
```

Decisions and why:

- **Kubera account goes first and absorbs the Growth history section.** The MCP
  token is a credential, not a feature. What was the "Growth history" card
  becomes the History line of the account status header, keeping its most useful
  part: the real last-fetch outcome from `SharedStore.historyStatus()`.
- **Per-credential rows, each with its own action.** `Replace` for a stored
  credential, `Add` for a missing one. Both open the same connect sheet focused
  on that field — one code path, three entry points.
- **Two independent status lines**, derived from the last real call against each
  surface, not from "is a string present in the Keychain":
  - `REST · connected` / `REST · authentication failed` / `REST · rate limited`
  - `History · connected (182 points)` / `History · not connected — <reason>` /
    `History · using on-device log`
  The third history state matters: with no MCP token the app still shows growth
  from its local log, which is a legitimate degraded mode, not an error.
- **"Update credentials" replaces the disconnect/reconnect dance.** Editing must
  never clear the snapshot, trends, local history, or the selected portfolio.
  Today the only way to change a key is `Disconnect`, which wipes all of it
  (`AppStore.signOut()` clears five caches including `clearLocalHistory()` —
  months of on-device history gone to fix a typo).
- **Widget portfolio above Preferences.** It's the setting people actually come
  here to change; Preferences are set-once.
- **Disconnect keeps its confirmation dialog**, with copy that now names what is
  lost: credentials, cached balances, and the on-device history log.

## Connect flow

One view, `ConnectView`, used for first run (full screen, no navigation bar) and
for editing (sheet from Settings with a Cancel button). Same fields, same
validation, same error copy.

```
Connect your Kubera account
Read-only. Nothing is ever written to your Kubera account.

REQUIRED — balances
  API KEY      [ kbra_pk_EXAMPLE_KEY_0001        ] [Paste]  ✓ valid
  API SECRET   [ ••••••••••••••••••  ]  [👁] [Paste]        ✓ valid
  ↳ Unlocks: net worth, assets, debts, holdings, allocation.

OPTIONAL — growth history
  MCP TOKEN    [ ••••••••••••  ] [👁] [Paste]      ⚠ Invalid token
  ↳ Unlocks: 1 day, YTD and CAGR from Kubera's own history.
     Without it, growth is estimated from the on-device log.

  [ Connect ]

Where do I find these?
  Kubera on desktop → Settings → API → Create New API Key / MCP Token.
  Copy the key and secret into the first two fields. Create an MCP Token on
  the same page for the third.
```

Behaviour:

- **Requirement is explicit and enforced separately.** `Connect` enables on
  key+secret non-empty (as today). An invalid MCP token must never block
  connecting — it degrades one feature.
- **Validate each credential against its own endpoint.**
  - key+secret → `KuberaAPI.listPortfolios` (what sign-in already does).
  - MCP token → one `tools/call` for `get_portfolio_history`, or `tools/list` if
    no portfolio is known yet. This is the only honest check; a token can be
    well-formed and still rejected.
  - Validate on blur per field, and again on submit. Show a per-field marker
    (`✓ valid`, `⚠ <reason>`, spinner) — not one shared error under the button.
- **Paste-friendly fields**: `.textInputAutocapitalization(.never)`,
  `.autocorrectionDisabled()`, `.textContentType(.password)` on secrets so
  iOS offers Passwords rather than autocorrect, a visible Paste button per field,
  a reveal toggle on the two secret fields, and trimming of whitespace and a
  leading `Basic ` on the token (the sanitizer in `KuberaMCP.sanitized` already
  does this — reuse it at entry so the user sees the cleaned value).
- **Error copy mapped from real API responses:**

  | Real response | Field | Copy |
  | --- | --- | --- |
  | REST 401 | key+secret | "Kubera rejected this key and secret. Check both — the secret is only shown once when you create the key." |
  | REST 429 | banner | "Kubera's rate limit was hit. Try again in a minute." |
  | REST 2xx, empty list | banner | "This key works, but the account has no portfolios." |
  | MCP `Kubera MCP: Invalid apiKey` | mcp token | "That looks like your API key, not an MCP token. Create an MCP Token in Kubera → Settings → API." |
  | MCP `Kubera MCP: Invalid Token` | mcp token | "Kubera rejected this MCP token. Create a new one and paste it again." |
  | MCP 400 missing header | mcp token | "The token field came through empty." |
  | MCP 200, unreadable payload | mcp token | "Kubera answered but the history payload was unreadable. Growth will use the on-device log." |
  | transport failure | banner | "Could not reach Kubera. Check your connection." |

  The `Invalid apiKey` mapping matters: it is precisely the mistake the current
  three-field screen invites, and today it produces silence.
- **Editing semantics**: fields prefill with masked placeholders, not values. An
  untouched field keeps its stored credential; an emptied optional field clears
  it. Saving writes once via `SharedStore.saveCredentials` and leaves every cache
  intact.

## OAuth: verdict

**Blocked, not broken. OAuth works — but only for clients Kubera has registered
on its side, so we cannot ship it unilaterally. Keep the token flow.**

Tested live against Kubera on 2026-07-29. What we learned:

1. **The advertised CIMD support is not open registration.** The metadata says
   `client_id_metadata_document_supported: true`, but the consent UI resolves a
   client through `GET /api/v1/auth/user/oauth2/client/<url-encoded client_id>`,
   and that endpoint is a **registry read, not a fetch**. Four probes returned the
   byte-identical `{"errorCode":1003,"errorMessage":"Invalid input"}`:
   a URL that 404s, a URL serving valid JSON of the wrong shape, a URL serving
   arbitrary valid JSON, and a string that is not a URL at all. If the server
   fetched and parsed the document, those four could not fail identically.
2. **A registered client resolves and works.** Claude's MCP client is registered:

   ```json
   {"id":"https://claude.ai/oauth/mcp-oauth-client-metadata","name":"Claude",
    "description":"Anthropic Claude(CIMD) MCP integration",
    "scopes":"read_profile,read_portfolio,write_portfolio",
    "tsCreated":1774954354}
   ```

   Driving `app.kubera.com/oauth/authorize` with that `client_id` renders the real
   consent screen — "Claude wants access to your Kubera Account", the account
   identity, an itemised scope list ("Read your profile", "View your portfolio
   data"), and Allow / Deny. The same URL with our `client_id` renders
   "Sorry, something went wrong". So the flow is sound; only client identity is
   missing. (No grant was made during testing — Allow was never clicked.)
3. **The token endpoint does not gate on client_id.** `POST .../oauth2/token`
   with an arbitrary URL `client_id`, a custom-scheme `redirect_uri`, and a bogus
   code answers `invalid_grant` / "Invalid code", not `invalid_client`. Useful to
   know, but it does not help: without an authorization code from the consent
   screen there is nothing to exchange.
4. **This is a supported integration path, aimed squarely at us.** Kubera's own
   bundle describes the feature as connecting AI assistants "so they can access
   your portfolio in real time during a chat session", and lists
   `/auth/user/oauth2/list` + `/revoke` so users can audit and revoke connected
   apps. An MCP-consuming client is the intended shape — this app just is not on
   the list.

### What it would take

Email `hello@kubera.com` and ask them to register a client. What they need:

| Field | Value |
| --- | --- |
| `client_id` | the HTTPS URL where we host the metadata document |
| `client_name` | Kubera Mobile |
| `redirect_uris` | `com.kubera.mobile:/oauth-callback` |
| scopes | `read_profile read_portfolio` (read-only; never `write_portfolio`) |

Note that Claude registered an **HTTPS** redirect on its own host
(`https://claude.ai/api/mcp/auth_callback`) because it completes the flow
server-side. A native app needs a custom scheme instead, so that is the one
detail worth confirming with them rather than assuming — if they only accept
HTTPS redirects, OAuth needs a redirect-broker page and stops being attractive
for a device-only app.

### Recommendation

Do not build phase 3 on spec. The implementation cost is not the blocker —
the handshake is a day's work and the refresh-token race is a known problem with
known mitigations — but every line of it is dead code until a stranger at another
company adds a database row. Ship phases 1-2 (done), keep the MCP token as the
history credential, and revisit if Kubera answers. If they do register us, the
payoff is real: one "Sign in with Kubera" button replaces the token field, and
`revocation_endpoint` makes Disconnect actually end access server-side rather
than just forgetting a string.

## Implementation plan

### Phase 1 — unified connect screen + Settings IA (~1 day)

No protocol changes; pure UI plus one store method.

- `App/Views/ConnectView.swift` (new): the three-field screen above, with a
  `mode: .firstRun | .edit(focus: Credential?)`. `SignInView` becomes a thin
  wrapper or is deleted in favour of `ConnectView(mode: .firstRun)`.
- `App/Views/SettingsView.swift`: replace `accountCard` with an account section
  (status header + three credential rows + Update button); delete
  `mcpTokenCard`, `mcpToken`/`savingToken`/`tokenStatus` state; reorder sections
  to Account → Widget portfolio → Preferences → Data & privacy → Disconnect.
- `App/AppStore.swift`: add
  `func updateCredentials(apiKey: String?, secret: String?, mcpToken: String??) async throws`
  — nil means "leave as stored", `.some(nil)` means "clear". It validates, writes
  once through `SharedStore.saveCredentials`, refreshes, and **touches no
  caches**. `saveMCPToken` becomes a thin call into it (keep it until callers are
  gone).
- Strengthen the disconnect dialog copy to name the on-device history log.
- Tests: masking helper; `updateCredentials` merge semantics (partial update
  preserves the untouched field, clearing the token nils it, snapshot and local
  history survive); token sanitization at entry.

### Phase 2 — per-credential validation and status (~1 day)

- `Shared/KuberaCredentials`: unchanged on disk. Add a *non-persisted*
  `ConnectionHealth` model in the app layer:
  `{ rest: State, history: State }` where
  `State = .unknown | .checking | .ok(detail: String) | .failed(reason: String)`.
- `Shared/KuberaAPI.swift`: add `validate(creds:) async -> Result<Void, APIError>`
  wrapping `listPortfolios` (no behaviour change to existing callers).
- `Shared/KuberaMCP.swift`: extract `validateToken(_ token: String, portfolioId:
  String?) async -> Result<Int, MCPError>` returning point count, and introduce a
  typed `MCPError` so the mapping table above is code, not string sniffing. Keep
  `setHistoryStatus` writing its human string for the widget-side path, but drive
  Settings from the typed value.
- `AppStore` gains `private(set) var health: ConnectionHealth`, updated by every
  refresh and by explicit validation; Settings renders it.
- Tests: the error-mapping table (fixture bodies → copy), health transitions,
  and that a failed MCP validation leaves REST health untouched.

### Phase 3 — OAuth (~2–3 days after a green light, plus unknowns)

Gate on the live authorize test. Then:

- Publish the client metadata document (static file, GitHub Pages or
  auchenberg.dk) and register the matching reverse-domain scheme in
  `CFBundleURLTypes` in `App/Info.plist` — note `project.yml` generates the
  project, so the entry belongs in the source Info.plist, not the built one.
- `Shared/KuberaOAuth.swift` (new): PKCE generation, authorize URL construction,
  code exchange, refresh with single-flight and one `invalid_grant` retry,
  revocation.
- Credential storage: keep the Keychain item's `service`/`account` coordinates
  exactly as they are (`kubera-widgets:no-auth` / `kubera.credentials`, account
  written as raw UTF-8 bytes for expo-secure-store compatibility) and evolve only
  the JSON payload. Add optional fields:
  `oauth: { accessToken, refreshToken, expiresAt, scope }?`. `KuberaCredentials`
  already decodes older blobs by making new fields optional — do the same here,
  and make `apiKey`/`secret` optional *in the decoder only* so an OAuth-only
  install is representable while existing installs keep decoding unchanged.
  Never write a shape an older build can't read while both may be installed.
- `KuberaMCP`: switch to `/api/v1/mcp` and choose the header by credential kind
  (`Bearer` for OAuth, `Basic` for a token). Re-verify `get_portfolio_history`
  and the SSE/JSON envelope handling on v1 before removing the v2 path.
- Widget extension: read-only with respect to tokens under mitigation (a); if
  refresh must happen there, implement the Keychain lease.
- `ConnectView` gains a primary "Sign in with Kubera" button with the manual
  three-field path kept below as "Use an API key instead" — needed for anyone
  whose account predates OAuth, and as the fallback if the browser flow fails.
- Tests: PKCE challenge derivation against known vectors, refresh single-flight
  under concurrent callers, `invalid_grant` retry, expiry handling that renders
  cached data rather than an empty widget.

### Migration notes

- The Keychain item format is live on devices. Additive optional fields only;
  never rename `SharedKeys.keychainService`/`keychainAccount`, and keep the
  raw-UTF-8 account quirk.
- `SharedStore.migrateLegacyCredentialsIfNeeded()` still has to work: pre-Keychain
  installs keep a plaintext copy in App Group defaults until first launch of a
  new build. Any credential-shape change must survive decoding that older blob.
- An install that has an MCP token and later completes OAuth should keep both
  until OAuth has succeeded at least once, then drop the token and tell the user
  it's no longer needed.
- Widget and app ship in the same build, so they agree on the format — but a
  widget can render from a *stale* cache written by the previous build. Don't
  make decoding of the snapshot/trends caches depend on the credential shape.

All example keys, secrets, and tokens in this document are synthetic.
