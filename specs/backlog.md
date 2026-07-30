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

---

## Next

### 8. Redesign the Widgets tab as a gallery

The tab works but reads as a list of labelled previews stacked vertically. The
welcome screen's original treatment was better: widgets presented as a
**horizontally scrolling gallery** of cards at true widget size, which shows the
Home Screen result rather than describing it.

- Group by family — small, medium, Lock Screen — and scroll horizontally within
  each group, so a medium widget is not squeezed into a phone's width beside a
  section title.
- Show every family each widget supports, including the Lock Screen accessories,
  which the current tab does not preview at all.
- Keep rendering the real widget content views (`Shared/WidgetViews.swift`) with
  live data. They must never drift back into mockups — that was the whole point
  of moving them into the shared layer.
- Keep "Add widgets" and "Update widget data now", but let the gallery carry the
  page rather than the section titles.
- Worth evaluating: page indicators or a peek at the next card so the horizontal
  affordance is discoverable; and whether the widget options belong back here
  contextually now that Settings owns them.

### 9. Redesign Settings around a profile header

Model it on iOS's own account sheets (Photos' profile sheet is the reference):
an identity block at the top, then grouped preference cards, then the legal or
explanatory text last.

```
Settings
├─ Profile header                  ← centred, not a list row
│    avatar or monogram
│    Kenneth Auchenberg            ← from KuberaProfile.name
│    portfolio name · currency
│    connection status: REST · History
│    [Disconnect]                  ← lives WITH the identity it ends
├─ Widget portfolio                ← grouped card, rows with a checkmark
├─ Preferences                     ← Face ID / Privacy mode / Compact numbers
├─ Growth history                  ← the MCP token row and its status
└─ Data & privacy                  ← explanatory text, last
```

Why this over what exists:

- **Disconnect belongs with the identity, not stranded mid-scroll.** It ends the
  connection the header describes, so it reads as that block's action. Right now
  it floats between Preferences and Data & privacy.
- **The header answers "whose account is this?" in one glance** — the current
  Account card shows a masked key and nothing else. `KuberaProfile.name` and
  `.email` are already fetched.
- **An avatar or monogram** gives the screen a focal point. Kubera's web app has
  a profile picture; MCP's `get_profile` may expose one — check before assuming,
  and fall back to initials rather than a placeholder silhouette.
- Keep the per-surface status lines (REST vs History fail independently) — just
  move them into the header where they describe the connection they belong to.
- Keep the confirmation dialog on Disconnect, including the copy naming what is
  lost, since disconnecting is still the only way to change credentials.

Open question: whether an avatar is worth a network fetch and a cache for a
screen most people open twice. Initials may be the better answer.

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

### 11. Dynamic Type

Every screen uses fixed `.system(size:)` fonts, so text does not grow with the
system setting. Overflow is guarded with `lineLimit` + `minimumScaleFactor`, so
nothing breaks — but the app is not accessible to anyone who needs larger text.
This is an app-wide change, not a one-file fix.

### 12. Ship it properly

- **TestFlight** — `./release` exists and the App Store Connect app record is
  created, but uploading needs either a live Xcode session for the signing team
  or an App Store Connect API key. The API key is the durable fix.
- **Make the repo public** — audited and pushed; the visibility flip is a
  one-click decision that hasn't been made.
- **App icon** — currently Kubera's own "K" logo, which is fine for a personal
  build but is their trademark. Worth an original icon before any public
  distribution.

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
