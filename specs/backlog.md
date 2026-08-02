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

### 6. Kubera.swift SDK ✅

All Kubera access lives in one documented file: `Kubera.REST` (HMAC signing,
portfolios, snapshot, history probing), `Kubera.MCP` (one generic
`call(tool:arguments:)` entry point), `Kubera.Parse` (every response decoder plus
the markdown reader), `Kubera.Error`. The old `KuberaAPI` / `KuberaMCP` names
remain as thin forwards, so the widget target and the existing parser tests kept
working without a mass rename.

Also finished what REST cannot serve: `get_profile` for the account name, and
`get_portfolio` for cash on hand, tax estimate, investable, and the asset list
with its sheet/section hierarchy.

### 7. Overview, phase 2 ✅

Greeting as the screen's heading (replacing the nav title, with a quiet marker
revealing what an unfamiliar hello means), drag-to-scrub that retargets the hero
figure and delta to the scrubbed day, Liquid Glass on the controls layer only
(range pills and scrub tooltip, gated to iOS 26 with a material fallback), and
the chart bleeding to the card's edges.

Widget light mode landed alongside: `WidgetTheme` resolves per trait collection,
with the darker green and red in light mode because the bright dark-mode green is
unreadable on white.

### 8. Widgets tab as a gallery ✅

Each family now scrolls horizontally at true point size with a peek of the next
card. The medium widget is no longer scaled down to fit — which had been
misrepresenting the one thing a preview is for, its text size. Lock Screen
accessories are previewed for the first time, on a dark stand-in wallpaper, with
the circular family clipped to a circle because the system clips it too. Still
the real views from `Shared/WidgetViews.swift`, never mockups.

Widget options stayed in Settings; the tab links to them instead. Privacy mode
and Compact numbers change the app as well as the widgets, so splitting them
across two screens would have been the wrong fix for a discoverability problem.

### 9. Settings around a profile header ✅

Opens on an identity — monogram from `KuberaProfile.name`, display name,
portfolio · currency — with the per-surface REST and history status lines moved
into that block, then Disconnect directly beneath it. Then grouped cards, then
the privacy text last.

Disconnect is a red row, not a filled red button: iOS puts Sign Out in a plain
row in its own account sheets, and a full-width red slab outshouted the identity
it sits under. Monogram over avatar, as the open question suspected — it never
fails to load and costs no fetch. The initials logic lives in
`Shared/Monogram.swift` with tests, because `App/` is untestable by construction.

### 11. Dynamic Type ✅

Text styles across every screen, `@ScaledMetric` for what must grow beside text,
and layouts that switch at accessibility sizes rather than only growing. The hero
figure auto-compacts at accessibility sizes with the full number in its VoiceOver
value. Verified at AX5 in the simulator, which caught two real bugs: the
assets/debts rows wrapping mid-number at *default* size, and the portfolio name
truncating to "Sample portfoli…" in the Settings header.

Sequenced before the two redesigns, per the research doc, so the new screens were
built scaling rather than retrofitted twice.

### 13. Minimizing tab bar ✅

`.tabBarMinimizeBehavior(.onScrollDown)`, gated to iOS 26, **confirmed firing on
device**. It is reported not to work in tabs built on `NavigationStack(path:)`;
the Overview's stack has no path binding, which is evidently why it works here.

Worth recording because it fails silently: if a future change gives any tab's
`NavigationStack` a `path:` binding, the tab bar will quietly stop minimizing
with no error and no test to catch it.

---

## Next

### 10. OAuth — blocked on Kubera

Tested live: Kubera's OAuth is real and complete (PKCE S256, public clients,
refresh tokens) but **closed to unregistered clients**. Despite advertising
`client_id_metadata_document_supported: true`, client lookup is a registry read,
not a document fetch — four different `client_id` values, including one that
isn't a URL, all return the same `1003 Invalid input`. A registered client
(Claude's MCP integration) renders the real consent screen; ours errors.

The blocker is a database row at Kubera, not code. **The founder has been
emailed** — waiting on a reply, so there is nothing to build here until one
arrives.

The detail to settle in that thread: whether their authorization server accepts
a **custom-scheme** redirect. Claude's integration registered an HTTPS one
because it completes the flow server-side; a device-only client has no server,
so `kubera://` needs to be acceptable — or the app needs a redirect host, which
would put a server back in a design that deliberately has none.

Full evidence in `specs/settings-and-auth.md`.

### 12. Ship it properly

- ~~**Make the repo public**~~ ✅ — live at
  [auchenberg/kubera-mobile](https://github.com/auchenberg/kubera-mobile), MIT,
  with a rewritten README and twelve screenshots. Verified before the flip: no
  leaks across the full history, only `main` on the remote, and the pre-scrub
  `private-history` branch has since been deleted and its objects garbage
  collected.
- ~~**App icon**~~ ✅ — but read the caveat. It is now a **derivative of
  Kubera's own mark**, chosen deliberately over the original "Ascent" staircase.
  `docs/icon.md` records the tradeoff: it works against the README's
  unaffiliated disclaimer, and App Store review is the likely friction point.
  The original mark is recoverable from commit `b36a48a`.
- **TestFlight** — still the open one. `./release` exists and the App Store
  Connect app record is created, but uploading needs either a live Xcode session
  for the signing team or an App Store Connect API key. The API key is the
  durable fix. Note the icon caveat above lands here too: this is the step where
  a trademark-derived icon actually gets reviewed by someone.
- **Tag a release.** `docs/RELEASE-NOTES.md` is written and marked as a draft;
  the version number, date and wording are all still open. Nothing is tagged.

### 14. Widget preview footprints ✅

`WidgetPreviewSize` now carries the ten iPhone screen classes Apple publishes
widget dimensions for, and resolves this device against them.

Keyed on the **screen**, not a `GeometryReader`: the table's key *is* the screen
size, and a view's size never is — it is the window minus safe areas and the tab
bar, which cannot tell 375×812 from 375×667, two classes whose footprints differ
by 7pt. Going through the screen also handles Display Zoom for free, since a
zoomed phone reports the smaller size and the guidelines list it as its own row.

An unpublished screen falls to the nearest class by width, and **says so** — the
previews claim to be actual size, so on a screen Apple publishes nothing for they
admit to being a few points out rather than quietly lying.

---

## Decisions that need you

`specs/design-research.md` ends with a list of open questions. I settled the ones
that were mine to settle and implemented them; these are the ones that are
genuinely yours, either because they change what the app asserts about your money
or because they commit us to real work.

For the record, the ones I settled and did not ask about: widget options **stay in
Settings** (Privacy mode and Compact numbers affect the app too, so Settings is
their honest home — the Widgets tab links to them instead); the hero figure
**auto-compacts at accessibility text sizes** with the full unabbreviated number
in its VoiceOver value, because that is the only option that neither lies nor
breaks the layout; Settings gets a **monogram, not an avatar**, since an avatar
costs a network fetch and a cache for a screen you open twice; and `Card`
**never becomes glass** — glass belongs on the controls layer, not under figures
you are trying to read.

### A. Scrub delta baseline — decided: range-start ✅

The delta beside the hero figure is measured from the **start of the selected
range**, never from today. Scrub to Jul 10 on a YTD chart and it reads "up
$60,000" meaning since Jan 1 — the same convention Apple's Stocks uses.

The code already did this (`OverviewChart.scrubChange` subtracts `first.value`);
what was missing was anyone having decided it, so nothing stopped it drifting.
`testScrubBaselineIsTheRangeStartAndNotToday` now pins it. The two conventions
agree at the right-hand edge, so that test discriminates them the only way
possible: it moves the *last* point and asserts a mid-series delta does not
follow.

Consistency across the app, checked rather than assumed:

- **Hero delta** — range-start, labelled with the range's own wording ("year to
  date") at rest and "by <date>" while scrubbing.
- **Widgets and the CAGR block** — not range-based at all. They show fixed
  windows (1 DAY, YTD) that carry their own labels, so there is nothing to
  disagree with.

The rule this leaves behind: **every delta states its window.** A signed figure
with no stated baseline is the failure mode, not a particular choice of baseline.

### B. Monochrome-plus-two — decided: it stays ✅

Greyscale plus one green and one red. The maintainer's verdict: *"accident but
it works."* So it is policy now rather than an accident, and it is written down
here because the accident could otherwise be undone by someone tidying up.

What this rules out: a categorical palette. The allocation bar, the composition
breakdown and any future Sankey all *want* a colour per category, and each will
press for one. The answer is a **luminance ramp** ordered by value —
`OverviewView`'s `rampColor(_:)` — not a rainbow.

Green and red keep their existing jobs and no others: direction of change, never
category identity. Anything that needs to distinguish categories does it by
order, size and label.

### C. Stale-data disclosure

The app currently shows a confident net worth figure with no indication of its
age. If the last refresh failed, or the phone was offline, that figure is
yesterday's and looks like today's. The fix is an "as of HH:mm" line under the
hero and on the widget previews once the snapshot passes some threshold — but the
threshold is a judgement call about your data, so you pick it: an hour? a day?

### D. A net-worth readout on the tab bar

iOS 26's `.tabViewBottomAccessory` puts a persistent line above the tab bar,
visible from every tab. One line — current figure and today's delta — is the
flourish that best fits this app's content. It is also a permanent
always-on-screen display of your net worth, including any time you hand someone
your phone, which is why it is your call and not mine. Privacy mode would need to
cover it.

---

### Ideas, unranked

- **Move the Widgets screen under Settings** (maintainer request, 2026-08-01).
  Settings → Widgets, where the previews live and the Add-widgets walkthrough
  is reached from — instead of Widgets holding a tab of its own. The tab bar
  earned this question the day it grew to five: Overview, Assets and Debts are
  places you check your money, Settings is where you configure the app, and the
  gallery is closer to configuration than to checking. History to respect when
  building it: item 3 already moved the widget *options* into Settings and made
  the tab purely a gallery, and the tab's reset/scroll wiring (`AppTab.widgets`)
  would need retiring, along with `kubera://widgets` and `-KuberaInitialTab
  widgets` growing a redirect rather than a dead end.
- Net worth sparkline widget (the history series can now feed it).
- Per-widget portfolio selection via AppIntents configuration.
- A real Sankey flow diagram — needs custom `Path` ribbon drawing; the grouped
  composition breakdown is the phone-sized stand-in.
- Moving the cached snapshot into the Keychain for maximal hardening.

---

## Potential items from the API gap analysis (2026-08-01)

A two-sided audit — what Kubera's payloads serve versus what this app consumes,
and what the documented API/MCP surface offers versus what it calls. Sources:
help.kubera.com articles 171 (REST v3), 133 (limits), 166 (MCP tools), plus a
file-by-file inventory of `Kubera.Parse` against the fixtures. The full surface
is recorded in the session memory note "kubera-api-surface"; two findings from
the audit already shipped (the truncated-table preference fix and Kubera's own
CAGR on the growth card). The rest, unranked and uncommitted:

**From data the app already fetches but never shows**

- **Cost basis and unrealized gain** — parsed from both transports, cached on
  the snapshot, rendered nowhere. A gain view costs no new fetch.
- **REST `debt[]` for API-key-only accounts** — the Debts tab fills only via
  MCP today. Article 171 documents a parallel debt array in the REST portfolio
  response; wiring it means one property on `PortfolioData` and a preference
  rule when both transports answer. Needs one live response verified first.
- **Documents and insurance inventory** — the REST response carries
  `document[]` (`{id, name, fileType, size}` — metadata only, no download
  endpoint) and `insurance[]`, both currently discarded at decode.
- Per-asset `assetClass` and `ticker` are parsed and unused; the MCP payload's
  own allocation and concentration tables, the per-debt `Since` dates (the only
  date any row carries), and the per-holding percent columns are all dropped.

**Read-only features needing calls the app has never made**

- **Cost and IRR columns on the asset tables** — the desktop-parity feature.
  REST serves `irr` and `cost` per item; the current decoder keeps only
  name/value/sheetName. This is the reason those columns were dropped from the
  drill-down screens, and the reason no longer holds.
- **Tax view** — per-item `taxability` / `taxRate` / `taxOnUnrealizedGain`
  would let the Tax Estimate card explain itself.
- **`get_top_movers`** (MCP) — top 10 changes over 1 day / 1 month; a natural
  Overview module or widget.
- **Liquidity cut** — per-item `investable` classifies easy-convert vs cash vs
  non-investable, a truer "what could I actually spend" than the current
  investable total.
- **Account drill-down** — `parent` / `holdingsCount` give the account→holding
  hierarchy the flat sheet/section view collapses.
- **Per-account freshness** — `connection.lastUpdatedTimestamp` answers the
  stale-data question (item C above) at the row level, not just the snapshot
  level.
- **Cash-flow history** for private investments — `GET /data/item/{id}/cashFlow`.

**A category jump: writes**

REST documents create/update/archive for manual items and cash-flow entries;
MCP has `update_portfolio_item`. Updating a car's value from the phone is
documented and possible. The app is read-only by design today, and the write
path carries a real trap — item `value` means *quantity* when a ticker is set
and money otherwise — so this is a deliberate decision, not a feature to slip
in.

**Known constraints and open verifications**

- No webhooks, no push, no refresh trigger anywhere in the API — polling is the
  only freshness mechanism. Rate limits: 30 req/min, daily caps by plan, MCP
  counted separately at 3×.
- `get_default_portfolio` documents a pagination `cursor` this client never
  sends; a large portfolio is silently page one. Following it needs a live
  capture of a paged reply — the response shape is unpublished and a guessed
  field name would truncate more subtly than not paging does.
- `get_portfolio_cagr`'s response shape and argument spelling are still
  inferred, not observed; the client logs every probe outcome so one real
  refresh settles them.
