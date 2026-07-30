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

---

## Next

### 10. OAuth — blocked on Kubera

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

### 13. Confirm the minimizing tab bar actually fires

`.tabBarMinimizeBehavior(.onScrollDown)` is enabled and gated to iOS 26. It is
reported not to work in tabs built on `NavigationStack(path:)`; the Overview's
stack has no path binding, so it should — but **it fails silently**, and the
simulator here could not be driven to scroll (no Accessibility permission for UI
automation, and `simctl` cannot send touches). So this is unverified.

Worth ten seconds on a device: open the Overview, scroll down, see whether the
tab bar shrinks. If it doesn't, the screens' bottom padding is still correct —
they use `.safeAreaPadding(.bottom)` now — so the only cost is a missing
flourish.

### 14. Widget preview footprints are hardcoded to one device

`WidgetPreviewSize` in `App/Views/WidgetsView.swift` holds iPhone 15/16 Pro point
sizes. Real footprints vary by a few points across devices, so on an SE or a Max
the "true size" preview is true-ish. `WidgetCenter` exposes no footprint API, so
the honest options are a small per-screen-width table or accepting the drift and
saying so. Low stakes, but the whole point of the gallery is fidelity.

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

### A. Scrub delta baseline: range-start or today? — **correctness, not taste**

When you scrub the chart, the delta shown next to the hero figure has to be
measured from *something*, and the app has to pick one and label it. Apple's
Stocks measures from the start of the selected range. The widgets and the CAGR
block need to agree with whatever the Overview does, and right now it is worth
confirming they do. Flagging it because a delta with an unstated baseline is a
number that looks precise and isn't.

### B. Is the palette monochrome-plus-two by policy?

You said early on "very monochrome for now" and I have held to it: greyscale plus
one green and one red. The allocation bar and the composition breakdown both
*want* a categorical palette — distinct colours per asset class — and they will
keep wanting one. Either we write the monochrome rule down as policy, or we own a
contrast-checked category palette, which is real work rather than a colour pick.

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

- Net worth sparkline widget (the history series can now feed it).
- Per-widget portfolio selection via AppIntents configuration.
- A real Sankey flow diagram — needs custom `Path` ribbon drawing; the grouped
  composition breakdown is the phone-sized stand-in.
- Moving the cached snapshot into the Keychain for maximal hardening.
