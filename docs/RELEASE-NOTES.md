# Release notes — 1.0.0

> **Draft.** Nothing has been tagged or published. This is a working document for
> the first release; the version number, the date and the wording are all still
> open.

The first release of **Kubera Mobile**, an unofficial native iOS app and Home
Screen widget suite for [Kubera](https://www.kubera.com). It is not affiliated
with or endorsed by Kubera. It reads your portfolio directly from Kubera's API
using credentials you create in your own account, and every request it makes is
read-only.

## A native app, not a wrapper

The project started as an Expo/React Native app with a native widget extension.
It is now pure Swift — SwiftUI for the app, WidgetKit for the widgets, no web
view anywhere. Nothing about it should look ported.

The on-disk formats did not change in the rewrite, so a device upgrading from the
old build keeps its credentials and settings. The app did get a new bundle
identifier along the way, though: iOS keys installs by bundle id, so the first
install under the new one arrives as a fresh app. Delete the old icon and expect
to enter your credentials once more.

## The Overview

The old Net Worth tab is gone, replaced by a single scrollable dashboard built
around one idea: net worth is the headline, and everything else supports it.

- One hero figure with its change beside it, instead of four equally large
  numbers competing for attention.
- A chart that fills the width of its card and responds to touch. Drag across it
  and the hero figure and delta follow your finger to that day. Range pills for
  1W, 1M, 3M, YTD, 1Y and ALL, opening on YTD.
- Assets and debts, each with its own 1 day and 1 year change.
- Cash on hand and the estimated tax on unrealized gains.
- Year-to-date growth and compound annual growth rate, shown next to the S&P
  500, Dow Jones and Bitcoin over the same period.
- Allocation as one segmented bar rather than a column of percentages, a
  composition breakdown grouped by your Kubera sheets or sections, and your
  ranked top holdings.
- Pull to refresh, and a line saying when the figures were last updated.

Where a number cannot be known honestly, it is left out rather than filled in. A
gap in Kubera's history breaks the chart line instead of drawing a slope across
it; a portfolio with no data from last year gets no year-to-date figure rather
than a misleading one; and the compound growth rate stays hidden until there is a
full year of history to compute it from.

## Widgets

Three widgets, covering five widget families between them:

- **Net Worth** — small, medium, and all three Lock Screen accessories (inline,
  circular, rectangular). Shows net worth with its 1 day and year-to-date change.
- **CAGR • YTD** — small. Your year-to-date growth beside the three market
  benchmarks. Percentages only, no amounts, which also makes it the widget to use
  if you would rather not have a balance on your Home Screen.
- **Assets vs Debts** — medium. Both totals with a ratio bar.

Widgets now follow the Home Screen's light or dark appearance instead of always
rendering dark, with the greens and reds adjusted for light mode where the bright
dark-mode green was unreadable. They refresh themselves in the background, so
they stay current whether or not you open the app, and they fall back to the last
cached figures instead of going blank when the network fails. Tapping one opens
the app and scrolls to the module it was showing.

The Widgets tab in the app is a real gallery: each family scrolls horizontally at
its true point size, so a preview is an honest preview of the text size you will
get. Nothing there is a mockup — they are the same views the Home Screen draws.
The Lock Screen accessories are previewed for the first time, on a stand-in
wallpaper. Because iOS offers no way for an app to open the widget gallery, the
"Add widgets" button shows you the manual steps rather than pretending it can.

## First run, and connecting an account

First run is two steps: a welcome screen that shows the actual product — the real
dashboard and real widgets rendered against sample data, badged as such — and
then the credential form.

Connecting takes three values, all from one page in Kubera's web settings: an API
key, an API secret, and an MCP token. The key and secret are checked against the
live API before anything is stored, so a bad paste cannot overwrite a working
key. The MCP token is checked by actually asking Kubera for history, which is the
only check that means anything. If just the token fails, the other two are still
saved and the app tells you precisely what went wrong and what you lose.

The MCP token is required rather than optional, and this is worth being blunt
about: Kubera serves portfolio history only through its MCP endpoint, and that
endpoint rejects the REST API key. Without the token there is no real 1 day,
year-to-date or CAGR figure — growth falls back to a log the app keeps on the
device, one point per day, which starts empty on the day you install.

## Face ID, privacy, and where your data lives

- **Face ID lock**, on by default. The app locks on a cold start and on returning
  after 30 seconds in the background, so switching apps briefly does not cost you
  a prompt. Touch ID and the passcode work as fallbacks. A device with no passcode
  set unlocks rather than locking you out permanently, and first run is never
  gated — there is nothing to protect before an account is connected.
- **Privacy mode** masks every amount in the app and on the Home Screen.
  Percentages stay visible, since a ratio gives away no balance.
- **Compact numbers** switches between `$1.24M` and `$1,240,000`.
- Credentials are stored in the iOS Keychain, in an access group shared with
  nothing but this app's own widget extension. Portfolio data is cached on the
  device so widgets can render offline. The app talks to Kubera directly; there
  is no server of ours in between. Every request is read-only.
- Disconnecting removes all three credentials, the cached balances and the
  on-device history log.

## Try it with no Kubera account

A debug demo mode renders every screen against a synthetic portfolio — no
account, no subscription, no credentials. It is how the screenshots in the README
are taken, and it means anyone can clone this repository and see what the app does
before deciding whether to bother with an API key.

Demo mode is debug-only and gated behind a launch argument, so it cannot be
reached from a release build. It writes nothing anywhere, so a demo figure can
never resurface as if it were yours.

## Design and accessibility

- An original app icon. Kubera's "K" was used as a placeholder early on and is
  now gone from the repository entirely; `docs/icon.md` records the reasoning and
  the directions that did not work.
- Liquid Glass on iOS 26, applied to the controls layer only — range pills, the
  scrub tooltip, buttons — and never under a number you are trying to read. On
  earlier versions those fall back to materials.
- Dynamic Type across every screen, with layouts that restructure at accessibility
  sizes rather than merely growing. Testing at the largest size caught two real
  bugs, one of which was breaking numbers at the default size too. The hero figure
  compacts when the type
  is large but keeps the full number in what VoiceOver reads aloud, and the chart
  is exposed to VoiceOver as a readable series.
- A rotating greeting as the dashboard's heading — hellos in eighteen languages
  plus English time-of-day forms, with a tap for the translation when the greeting
  is one you may not know.

## Known limitations

Being honest about what does not work yet:

- **No TestFlight build.** There is a release script and an App Store Connect app
  record, but uploading needs either a live Xcode session for the signing team or
  an App Store Connect API key, and neither is set up. Until then, running the app
  means building it yourself.
- **Sign in with Kubera is blocked on Kubera.** Their OAuth implementation is real
  and complete, but closed to unregistered clients — every client identifier we
  tried is rejected at lookup, while a registered client renders the real consent
  screen. The blocker is a database row on their side, not code on ours, so for
  now the app asks for API credentials instead. Evidence is in
  `specs/settings-and-auth.md`.
- **The minimizing tab bar is unverified.** The iOS 26 behaviour that shrinks the
  tab bar as you scroll is enabled, but it has never been confirmed firing on a
  real device, and it fails silently if it does not. Nothing else depends on it —
  the screens' bottom spacing is correct either way — so the worst case is a
  missing flourish.
- **Widget previews are sized for one device.** The Widgets tab draws each family
  at hardcoded iPhone 15/16 Pro point sizes. Real widget footprints vary by a few
  points across devices, and iOS exposes no API to ask, so on an SE or a Max the
  "true size" preview is true-ish.
- **No indication of how old a figure is.** If a refresh failed or the phone was
  offline, yesterday's net worth looks exactly like today's. An "as of" line is
  planned; the threshold at which it should appear is still an open question.
- **One dashboard module is missing.** Kubera's "YOUR CLUB" peer percentile comes
  from a session-authenticated endpoint that neither an API key nor the MCP token
  can reach, so it is left out rather than faked. The Sankey flow diagram is
  replaced rather than omitted — the composition breakdown tells the same story at
  a size that fits a phone.
- **iPhone only, portrait only, English only.** No iPad layout, no landscape, and
  no localization beyond the greetings themselves.
