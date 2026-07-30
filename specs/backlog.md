# Backlog

## Done

### 1. Rename the app ✅

Shipped as **Kubera Mobile** (`CFBundleDisplayName` on both targets, plus the
in-app and widget-gallery strings). Bundle identifiers are `com.kubera.mobile` /
`.widgets` / `.tests`, and the App Group, shared Keychain group, and URL scheme
(`kubera://`) moved with them. Because iOS keys installs by bundle id, the first
install under the new id arrives as a fresh app: delete the old icon and expect
to re-enter credentials once.

Signing is on team `TP8BN7C8C6` — the Apple ID actually signed into Xcode on
this machine. The other team had no account, so no profile could be minted.

### 2. Face ID lock ✅

On by default, with a Settings toggle. Cold start and returns from background
after a 30-second grace period require Face ID / Touch ID / passcode; brief app
switching does not. Devices with no passcode configured unlock rather than
brick. Onboarding is never gated — locking requires credentials to exist.
`AppLockPolicy` holds the when-to-lock decision in `Shared/` and is unit-tested.

### 3. Restructure Settings and the Widgets tab ✅

Widget options moved into Settings alongside the Face ID toggle. The Widgets tab
is now purely live previews of the real widget views plus an **Add widgets**
button. iOS exposes no API to open the Home Screen widget gallery — `WidgetCenter`
has no hook and there is no URL scheme — so the button presents an illustrated
walkthrough instead of pretending otherwise.

Credential management was also simplified: there is no edit-in-place path, and
changing a key means disconnecting and reconnecting, which the confirmation
dialog says outright.

### 4. First-run experience ✅

Two steps: a **welcome screen that shows the product** — the real dashboard and
the real widget views rendered against deterministic sample data, badged SAMPLE
DATA — then the credential form. No third step: a successful connect swaps in the
tabs, so landing in the app is the confirmation.

### 5. Overview dashboard, phase 1 ✅

Replaced the Net Worth tab. One hero net worth number, a Swift Charts area chart
with 1W/1M/3M/YTD/1Y/ALL pills (YTD default), assets/debts with direction-aware
colouring, allocation as a segmented bar, ranked holdings. Chart maths lives in
`Shared/OverviewChart.swift` and is unit-tested, including gap segmentation so a
hole in Kubera's history breaks the line rather than inventing a slope.

---

## In flight

- **`Shared/Kubera.swift` SDK** — consolidating the REST client, the MCP client,
  and all response parsing into one documented file with a single generic
  `MCP.call(tool:arguments:)` entry point. Also finishes `get_profile` (the
  user's real name) and `get_portfolio` (cash on hand, tax estimate, investable,
  and the asset list with sheet/section).
- **Overview parity modules** — cash on hand, tax estimate, investable as a
  second hero figure, the CAGR • YTD block with market comps, and a composition
  breakdown grouped by sheet/section.
- **Widget light mode** — `WidgetTheme` was five hardcoded dark colours; making
  it adaptive, with proper light/dark colour set appearances.

---

## Next

### 6. Wire the greeting into the Overview header

`Shared/Greeting.swift` exists and is tested (18 languages mixed with English
time-of-day forms, each foreign hello carrying its own translation note). It is
not yet rendered. Needs: the header line above the hero, the real name from
`store.profile?.name` once the SDK lands, and a tap or long-press to reveal the
translation note the way Kubera's web dashboard uses a footnote marker.

### 7. Overview dashboard, phase 2 — scrubbing and Liquid Glass

From `specs/overview-dashboard.md`:

- **Drag-to-scrub** the chart: the hero number and delta retarget to the
  scrubbed date, with haptics. `OverviewChart.nearest(to:in:)` already exists and
  is tested for exactly this.
- **Liquid Glass on the controls layer only** — range pills, scrub tooltip, nav
  bar. Cards stay opaque, per Apple's guidance and because glass behind numbers
  wrecks legibility. Note the app already gets the native glass tab bar free on
  iOS 26; this is about the app's own controls.
- `contentTransition(.numericText)` on the changing figures.
- Portfolio switcher and the privacy toggle into the nav bar.
- Risk: the simulator misrepresents glass. Budget device time; don't sign off on
  screenshots.

### 8. OAuth — blocked on Kubera

Tested live: Kubera's OAuth is real and complete (PKCE S256, public clients,
refresh tokens) but **closed to unregistered clients**. Despite advertising
`client_id_metadata_document_supported: true`, client lookup is a registry read,
not a document fetch — four different `client_id` values, including one that
isn't a URL, all return the same `1003 Invalid input`. A registered client
(Claude's MCP integration) renders the real consent screen; ours errors.

The blocker is a database row at Kubera, not code. A draft email asking them to
register a client is written; the one detail to confirm is whether their
authorization server accepts a **custom-scheme** redirect (Claude registered an
HTTPS one because it completes the flow server-side). Full evidence in
`specs/settings-and-auth.md`.

### 9. Dynamic Type

Every screen uses fixed `.system(size:)` fonts, so text does not grow with the
system setting. Overflow is guarded with `lineLimit` + `minimumScaleFactor`, so
nothing breaks — but the app is not accessible to anyone who needs larger text.
This is an app-wide change, not a one-file fix.

### 10. Ship it properly

- **TestFlight** — `./release` exists and the App Store Connect app record is
  created, but uploading needs either a live Xcode session for the signing team
  or an App Store Connect API key. The API key is the durable fix.
- **Make the repo public** — audited and pushed; the visibility flip is a
  one-click decision that hasn't been made.
- **App icon** — currently Kubera's own "K" logo, which is fine for a personal
  build but is their trademark. Worth an original icon before any public
  distribution.

### Ideas, unranked

- Net worth sparkline widget (the history series can now feed it).
- Per-widget portfolio selection via AppIntents configuration.
- A real Sankey flow diagram — needs custom `Path` ribbon drawing; the grouped
  composition breakdown is the phone-sized stand-in.
- Moving the cached snapshot into the Keychain for maximal hardening.
