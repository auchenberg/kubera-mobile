# Overview Dashboard — Product & Design Spec

Status: draft for review · Target: iOS 26 (Liquid Glass era), SwiftUI · Owner: @auchenberg

> All figures in this document are **synthetic**. The sample portfolio is a fictional
> $1.24M net worth. Do not replace them with real numbers — this repo is public.

---

## TL;DR

Replace the current **Net Worth** tab with a single scrollable **Overview** screen that is
good enough to delete Kubera's mobile web app from the home screen.

1. **One hero, not four.** Net worth is the headline. Assets, debts, and investable stop
   being competing hero numbers and become supporting stats. The web app's fatal flaw is
   four equally-weighted giant numbers stacked vertically — no hierarchy, so nothing reads.
2. **The chart is the product.** A full-width interactive area chart directly under the
   hero, with drag-to-scrub (value + date follow your finger) and `1W 1M 3M YTD 1Y ALL`
   range pills. Every good finance app does this; the web app's orphaned axis-less purple
   blob at the bottom of the page is the single biggest thing to fix.
3. **Scrubbing rewrites the hero.** Dragging the chart retargets the hero number and the
   delta to the scrubbed date. This is the Robinhood/Stocks interaction, and it is why the
   hero and chart must be one visual unit, not two cards.
4. **Stats in a 2-up grid, ordered by how often you look at them.** Assets/Debts, then
   Investable/Cash, then CAGR vs market comps, then Tax Estimate (collapsed).
5. **Allocation becomes a segmented bar + legend**, not a list of percentage rows. Top
   holdings become a ranked list with a share bar, not bare name/value pairs.
6. **Liquid Glass goes on the controls layer only** — nav bar, floating range pills, scrub
   tooltip, tab bar. Cards stay opaque. This is Apple's explicit rule and it also happens
   to be the tasteful answer: glass on a data card destroys number legibility.
7. **Phase 1 is shippable on its own**: hero + chart + stat grid, no glass, no scrubbing.

Not in scope: **"YOUR CLUB" peer comparison.** That number comes from a session-authenticated
Kubera endpoint an API key cannot reach. See [Unavailable data](#unavailable-data).

---

## Research: what the best apps do

### Copilot Money (Apple Design Award finalist 2024, Interaction category)
- Home leads with **one** number in context, not a wall of them. Everything else is a
  card you scroll to.
- Native-feeling typography, spacing, and animation rather than a ported web design — the
  most-cited reason reviewers call it best-in-class. Nothing about it looks cross-platform.
- Signature move is **motion as feedback**: numbers animate between states, charts draw in,
  category rings fill. Note the nomination was in *Interaction*, not Visuals — the polish is
  in how it responds, not how it looks in a screenshot.
- Telling detail: Copilot shipped a web app in Dec 2025 and it is explicitly *not* a
  replacement for the mobile experience. The best-designed app in this category treats
  mobile as the primary surface — the inverse of Kubera today, and our opening.
- Takeaway: the gap between "competent" and "award" is transitions and responsiveness, which
  is cheap in SwiftUI and is exactly what the web app has zero of.

### Monarch Money
- Net-worth-first dashboard with a chart immediately under the headline, then an accounts
  breakdown — the closest structural analogue to what we want.
- **Drag-and-drop reorderable dashboard widgets** (net worth, investment performance,
  upcoming bills). Reviewers consistently split it as **mobile for quick daily check-ins, web
  for deep configuration** — and Monarch leans into that rather than fighting it.
- Takeaway: design Overview for the 15-second check-in, not for configuration. Module order
  matters more than module count, so hardcode a good order for v1 and leave reordering to
  phase 3 rather than shipping a settings maze.

### Delta Investment Tracker (Delta by eToro)
- Portfolio total + period delta as a tight unit, then a **prominent scrubbing chart** with
  range tabs, then holdings ranked by value with per-row sparklines and % change. Allocation
  is a **donut with a tappable legend** that cross-references holdings.
- Their Portfolio 3.0 notes are unusually explicit about the polish: **subtle animations on
  the total-worth number when refreshing or filtering**, and the header **cross-fading from
  "Portfolios" to the current portfolio's name as you scroll**. Portfolio switching is a
  **horizontal swipe**, not a picker.
- Their own framing: the portfolio screen "has to display a lot of data while staying easy
  to understand and digestible at a glance" — solved by consistency and layout discipline.
- Takeaway: the animated hero number is validated by the app most praised for this exact
  screen — it's the thing people notice, not a gimmick. Holdings and allocation should
  cross-reference; a percentage that can't be tapped is a dead end. We reject
  swipe-between-portfolios: it collides with horizontal chart scrub.

### Robinhood
- The canonical **scrub interaction**: touch-and-drag the line, the hero number above it
  becomes the value at that instant, the delta recomputes against the range's start, and a
  timestamp floats at the touch point. Haptic tick on entry.
- Range switching (`1D 1W 1M 3M YTD 1Y ALL`) as one row of text pills under the chart, with
  green/red tint applied to the entire chart *and* the pill row — an all-or-nothing theme, so
  when you're down the whole hero cluster turns red. Bold, and legible at a glance.
- Takeaway: adopt the scrub, adopt the pill row, **don't** adopt full-screen color theming —
  a net-worth tracker isn't a day-trading app and daily red would be visually exhausting.

### Apple Stocks
- Chart + range row + a **stat grid below** (open/high/low/vol) — the exact "hero, chart,
  then a grid of secondary stats" skeleton we're proposing.
- Scrub shows a vertical rule and a value bubble; the number above the chart changes in
  place; nothing else on screen moves.
- Takeaway: the stat grid pattern is a system idiom users already read fluently, and it's
  the safest structure we can borrow. Two columns, label above value, monospaced digits.

### Also surveyed
- **Revolut** — big balance, then horizontally scrolling accounts, then a vertical feed;
  rounded **opaque** cards on a neutral background, color reserved for state. Confirms our
  existing `Card`-on-`Theme.background` container model is right; horizontal scroll is for
  peer items only.
- **Apple Wallet** — balances are typographic, not decorative; zero chrome around numbers.
  Glass only ever appears on floating controls above card content. Takeaway: restraint —
  amount + label + nothing is often the correct card.
- **Origin** — leads with one net-worth hero and a plain-language delta ("up $12,400 this
  month") instead of a bare percentage. We adopt the sentence-style delta for the hero and
  keep raw percents in the dense stat grid.
- **Vantage and net-worth trackers generally** — near-universal pattern of net worth line
  chart, assets-vs-debts as an opposed pair, allocation donut. Assets and debts read best as
  **one opposed pair**, not two independent cards.

### Fey
- The design-forward stock terminal: near-monochrome palette, one accent color, enormous
  whitespace, charts with almost no chrome (no gridlines, no axis boxes, just the curve and
  a soft gradient fill).
- Deliberately **dark-mode-first** — reviewers credit the rich dark palette with improving
  data legibility and lowering cognitive load over long sessions. Not a preference toggle;
  the design target.
- Described as using "motion, light, and color" to turn raw numbers into something
  cinematic, while "letting the numbers speak without noise."
- Signature: everything is gesture-driven and instant; no spinners, skeleton states instead.
- Takeaway: this is the aesthetic our dark palette is already reaching for, and it's the
  strongest external validation for staying dark-first. Kill axis furniture, keep the
  gradient fill, use skeletons not spinners.

### Apple Liquid Glass (iOS 26)
Sources: Apple HIG, `glassEffect` docs, community references (Donny Wals, LiquidGlassReference).

- **Glass is the navigation layer.** "Liquid Glass elements should always be designed as
  sitting on top of something. They don't stack, they're not part of your main UI."
  Approved surfaces: nav bars, toolbars, tab bars, floating action controls, sheets,
  popovers, menus. Explicitly warned against: list rows, content cards, scrollable content,
  full-screen backgrounds.
- **Never glass-on-glass.** Glass cannot sample another glass surface; overlapping glass
  reads as mud. Use one `GlassEffectContainer` per cluster.
- **Automatic adoption.** Recompiling against the iOS 26 SDK applies glass to NavigationBar,
  TabBar, Toolbar, sheets, popovers, menus, alerts, and search bars with **no code**. Most of
  our glass budget is free; the only hand-rolled glass is the range pills and scrub tooltip.
- **API surface.** `.glassEffect(_ glass: Glass = .regular, in shape: S = Capsule, isEnabled:)`
  with variants `.regular`, `.prominent`, `.clear` (needs a dimming layer + bold foreground),
  `.identity` (no-op, for conditional toggling); `.tint(_:)` ("conveys meaning, not
  decoration") and `.interactive()` (scale, bounce, shimmer). `GlassEffectContainer(spacing:)`
  shares one sampling region, where `spacing` is the **morph threshold** — elements closer
  than it merge visually. Plus `glassEffectID(_:in:)`, `glassEffectUnion`,
  `buttonStyle(.glass)`/`.glassProminent`, `ToolbarSpacer(.fixed/.flexible)`,
  `.sharedBackgroundVisibility(.hidden)`, `.tabBarMinimizeBehavior(_:)`,
  `.tabViewBottomAccessory { }`. UIKit: `UIGlassEffect`, `UIGlassContainerEffect`.
- **Accessibility is automatic.** Reduce Transparency swaps in solid backgrounds, Reduce
  Motion disables lensing, Increase Contrast adds stark borders, and Settings → Brightness
  exposes a user-level Clear/Tinted choice. **Never override any of it.**
- **Bare glass renders poorly**; a slight tint at low opacity is usually needed for
  legibility, especially over a busy chart. Apple's own advice is to test legibility over
  busy backgrounds before shipping. Specular highlights and motion response **do not render
  correctly in the Simulator** — glass work must be reviewed on device.
- **Known iOS 26.0–26.1 bugs that constrain our design:** (1) `.regular.interactive()` has a
  hit-shape mismatch on buttons — use `.buttonStyle(.glass)` instead, which **decides how the
  range pills are built**; (2) `.glassProminent` + `.circle` has rendering artifacts, avoid;
  (3) a `Menu` inside a `GlassEffectContainer` breaks morphing, which **keeps the portfolio
  switcher in the system toolbar** rather than any custom container.

### Distilled principles

1. **One hero.** Exactly one number gets display type. Everything else steps down at least
   two type sizes. Four heroes is zero heroes.
2. **The chart is interactive or it's decoration.** No axes, no scrub, no ranges = delete it.
3. **Scrubbing retargets the hero.** The hero and chart are one unit; the number is the
   chart's readout.
4. **Glass floats, content doesn't.** Controls layer gets glass; data cards stay opaque.
   This is Apple's rule and it protects number legibility.
5. **Color is state, not decoration.** Green/red only ever encode direction of change.
   Allocation gets a neutral ramp, never the semantic pair.
6. **Motion is the polish budget.** Number transitions, chart draw-in, and haptics are what
   separate award-grade from competent — and they're the cheapest thing on this list.
7. **Density earns its place.** A stat only appears if you'd look at it weekly. Everything
   else collapses or moves to a detail screen.

---

## What we're replacing

Kubera's mobile web app, diagnosed against the principles above:

| Symptom | Principle violated | Fix |
|---|---|---|
| Four equal hero numbers (Assets, Debts, Net Worth, Investable) stacked on plain black | 1 — one hero | Net worth is the only hero; the rest step down two type sizes into a stat grid |
| Purple area chart orphaned at the page bottom: no axes, no scrubbing, no ranges | 2, 3 — chart is decoration | Chart moves directly under the hero, gains ranges + scrub, becomes the hero's readout |
| No cards, no grouping — one flat vertical list | 7 — density earns its place | Opaque cards group related stats; unrelated stats are separated or collapsed |
| Enormous dead space, zero interactivity | 6 — motion is the polish budget | 2-up grids reclaim height; scrub, haptics, and number transitions add response |
| Comps row (S&P/Dow/BTC) detached from the CAGR block it explains | 7 | Comps move inside the Growth card, below a hairline |

Its one genuine strength is typography, which is legible and well-proportioned. Everything
else is absent rather than wrong, which is why a rebuild beats a restyle.

---

## Design

Single scrollable screen, `NavigationStack` + `ScrollView`. Order top to bottom:

```
[ nav bar: portfolio switcher (title menu) · privacy toggle ]   ← glass
┌─────────────────────────────────────────┐
│ HERO + CHART (one visual unit)          │
│   NET WORTH                             │
│   $1,240,860                            │
│   ▲ $18,420  +1.5%   past month         │
│   ╭───────── area chart ─────────╮      │
│   │                        ╱‾‾   │      │
│   │        ╱‾╲___╱‾‾‾‾‾‾‾‾╱      │      │
│   ╰──────────────────────────────╯      │
│      ( 1W  1M  3M  YTD  1Y  ALL )       │   ← glass pill row
└─────────────────────────────────────────┘
[ Assets        ] [ Debts         ]   2-up
[ Investable    ] [ Cash on hand  ]   2-up
[ GROWTH — CAGR/YTD + market comps ]  full width
[ ALLOCATION — segmented bar + legend ]
[ TOP HOLDINGS — ranked, share bars ]
[ Tax estimate (collapsed row) ]
[ Updated 2 minutes ago ]
```

### Module 1 — Hero + chart (one card, full bleed edges)

| | |
|---|---|
| Primary | `netWorth` — 44pt bold, `-1` kerning, `.numericText` transition |
| Secondary | Change for the selected range: `▲ $18,420  +1.5%  past month` |
| Chart | Swift Charts `AreaMark` + `LineMark`, gradient fill to transparent, no gridlines, no axis boxes |
| Control | Range pills `1W 1M 3M YTD 1Y ALL` |

**Rationale.** Every app in the research leads with hero-then-chart, and the two are always
coupled by scrubbing (Robinhood, Stocks, Delta). Making them one card rather than two makes
the coupling legible before the user ever touches it. The label `NET WORTH` sits above the
number in 12pt caps/kerned — our existing `SectionTitle` treatment — so the number owns the
visual weight.

**Chart details.**
- Data: the daily history series (`KuberaAPI.HistoryPoint`, `date` + `value`), filtered to
  the selected range. `ALL` uses everything; ranges shorter than available data window down.
- Line: 2pt, `Theme.text` at full opacity in dark, `Theme.accent` in light. **Not** green/red
  — the line is neutral; direction is communicated by the delta text. (Robinhood tints the
  whole chart; we don't, because a net worth chart is up-and-to-the-right over years and
  daily red would misrepresent the trend.)
- Fill: `LinearGradient` from line color at 0.18 alpha to 0 at the baseline.
- Y domain: `[min * 0.98, max * 1.02]` over the visible range, never zero-based — a
  zero-based net worth chart is a flat line.
- No axis marks by default. Endpoint labels only: first and last date in 11pt dim, under
  the chart's left and right edges.
- Empty/short history: if fewer than 2 points, hide the chart entirely and show
  "Growth history needs a Kubera MCP token" (we already have that plumbing via
  `SharedStore.historyStatus()`), rather than rendering a one-point line.

**Scrub.** See [Interactions](#interactions).

### Module 2 — Assets / Debts (2-up)

Two `Card`s side by side, matching the current dashboard's pair, but with the **1-day and
period delta added as a third line** — the web app has that data and it's genuinely useful.

```
ASSETS                    DEBTS
$1,318,400                $77,540
▲ $19,100 (+1.5%)         ▼ $1,180 (-1.5%)
```

**Rationale.** Assets and debts are the one pair users read as a unit (research: net-worth
trackers universally show them opposed), and they're the arithmetic behind the hero, so they
belong immediately below it. Debts trending *down* is good news, so **sign the color by
whether the change is favorable, not by the sign of the number** — a shrinking debt renders
green. This is a real trap: the naive implementation paints debt reduction red.

### Module 3 — Investable / Cash on hand (2-up)

```
INVESTABLE                CASH ON HAND
$964,200                  $48,900
▲ 8.4% YTD                4.0% of net worth
```

Cash on hand is a **new fetch** (Kubera exposes it; we don't pull it yet). Showing it as a
percentage of net worth is the interesting framing — an absolute cash number tells you
nothing without the denominator.

**Rationale for order.** Investable is the number an investor checks second (after net
worth) because it's the part that's actually working; cash is its complement. Pairing them
in one row makes the liquid/illiquid split readable. If cash on hand is unavailable, this
row degrades to a single full-width Investable card.

### Module 4 — Growth (full width)

The web app's "CAGR • YTD" block, redesigned. Two rows inside one card:

```
GROWTH
Net worth        +11.2% YTD      CAGR 9.4%
Investable       +14.6% YTD      CAGR 12.1%
────────────────────────────────
S&P 500  +8.2%    Dow  +5.1%    BTC  +21.4%
```

**Rationale.** The comparison is the point, so the comps must sit inside the same card as
your own numbers, separated by a hairline — not in a detached row like the web app. Comps
get dim labels and slightly smaller type so your numbers stay dominant. Comps carry
green/red; your YTD carries green/red; CAGR stays neutral (it's a rate, not a change).

Peer comparison ("YOUR CLUB") would live in this card if it were reachable. It isn't —
see [Unavailable data](#unavailable-data). Do not ship a placeholder for it.

### Module 5 — Allocation (full width)

**Chosen form: horizontal segmented bar + tappable legend.** Rejected alternatives:

| Form | Verdict |
|---|---|
| Donut (Delta) | Beautiful but wastes vertical space on a phone and needs a legend anyway; center hole begs for a number we don't have a good candidate for. |
| Per-row horizontal bars (current) | Readable but consumes 8+ rows of height and reads as a table, not a composition. |
| **Segmented bar + legend** | One 12pt-tall bar shows the whole composition at a glance; legend below gives names and exact percentages. Half the height of the current design. |

```
ALLOCATION
▉▉▉▉▉▉▉▉▉▉▉▉▉▉▓▓▓▓▓▓▓▒▒▒▒▒░░░
● Public equity  42.1%    ● Real estate  24.8%
● Cash           18.3%    ● Crypto        9.4%
● Other           5.4%
```

- Palette: a **neutral-to-accent ramp**, 5–6 steps, derived from `Theme.text` at descending
  opacity in dark mode. Never green/red — those mean change, not category (principle 5).
- Segments under ~3% merge into a trailing "Other" segment so the bar doesn't turn into
  hairlines.
- Tapping a legend entry highlights its segment (others drop to 0.35 opacity) and, in a
  later phase, filters Top Holdings — the Delta cross-reference idea.
- Legend is a two-column `LazyVGrid`, so 6 classes cost 3 rows.

### Module 6 — Top holdings (full width)

Ranked list, max 5 rows, "Show all" pushes a detail screen (phase 3).

```
TOP HOLDINGS
1  Brokerage — VTI        $312,400   ▉▉▉▉▉▉▉▉ 25.2%
2  Primary residence      $290,000   ▉▉▉▉▉▉▉  23.4%
3  401(k)                 $184,600   ▉▉▉▉▉    14.9%
```

The bar is share-of-net-worth, scaled so the largest holding fills the track — a bar scaled
to 100% leaves every row nearly empty. Sheet name (`Holding.sheet`) becomes a dim prefix or
suffix on the name line, not its own column; phones don't have the width.

### Module 7 — Tax estimate (collapsed)

A single full-width row with a chevron, collapsed by default:

```
Estimated tax on unrealized gains        $61,300  ›
```

**Rationale.** It's a once-a-quarter number and a modelled estimate, not a fact. Giving it a
hero card (as the web app effectively does) overstates it. Collapsed row = present, not
shouting. Expanding reveals cost basis, unrealized gain, and the assumed rate — data we
already have in `PortfolioSnapshot` (`costBasis`, `unrealizedGain`) plus one new fetch.

### Footer

`Updated 2 minutes ago` in 12pt dim, centered, plus the history-source note when relevant.
Nothing else. No branding, no version.

### Unavailable data

- **"YOUR CLUB" peer percentile** — Kubera's web app gets this from a session-authenticated
  endpoint. An API key + secret (our auth model) cannot reach it, and there is no documented
  API-key equivalent. **Explicitly out of scope.** Don't add a locked/empty state for it
  either; an empty slot is worse than no slot.

---

## Liquid Glass plan

Apple's rule is the whole plan: **glass is the controls layer floating above content; the
content layer stays opaque.** Concretely:

| Surface | Treatment | Why |
|---|---|---|
| Nav bar (title + portfolio menu + privacy toggle) | **Glass**, automatic via iOS 26 SDK toolbar | System-owned navigation layer. Free by recompiling; add `ToolbarSpacer(.flexible)` between the switcher and the privacy toggle. |
| Range pill row | **Glass**, one `GlassEffectContainer(spacing: 8)` wrapping six `.buttonStyle(.glass)` buttons | It's a floating control over chart content — the textbook case. Uses `buttonStyle(.glass)` rather than `.glassEffect(.regular.interactive())` because of the 26.0–26.1 hit-shape bug. Container spacing of 8 lets adjacent pills merge into one glass slab, which is the effect we want. |
| Scrub tooltip / value bubble | **Glass**, `.regular` + faint `.tint(Theme.card)` for legibility over the chart | Transient overlay directly above content. Bare glass over a gradient fill is unreadable; tint at low opacity. Standalone — **not** in the pills' container. |
| Tab bar | **Glass**, system, `.tabBarMinimizeBehavior(.onScrollDown)` | Long scrolling screen; minimizing the tab bar reclaims real estate and is the iOS 26 idiom. |
| Portfolio switcher menu | **Glass**, system `Menu` in the toolbar — **never inside a `GlassEffectContainer`** | Menus get glass automatically; nesting one in a container breaks morphing (known 26.x bug). |
| Hero card, stat cards, allocation, holdings | **Opaque** `Theme.card` | Content layer. Glass here would (a) violate Apple's guidance and (b) wreck legibility of monospaced digits over a moving backdrop. |
| Page background | **Opaque** `Theme.background` | Full-screen glass is explicitly called out as wrong. |

Rules we hold ourselves to: one `GlassEffectContainer` per cluster, never nested. **No glass
on glass** — the tooltip is reserved to the top half of the chart so it can never overlap the
pill row below. **Tint conveys meaning only**, so the active range pill is *not* glass-tinted;
it's a solid `Theme.text` capsule with an inverted label, and the selected state reads without
relying on translucency. Zero accessibility conditionals — Reduce Transparency, Increase
Contrast, and Tinted Mode are system-handled. Glass sign-off happens on hardware, not the
Simulator.

**Light + dark.** Both are already supported by `Theme`'s adaptive colors. Dark is the
design target (`#0A0C12` bg, `#151823` cards). In light mode the chart gradient needs a
lower alpha ceiling (0.12 vs 0.18) or it muddies against the white card, and the glass pill
row picks up more visible frost — acceptable, no code fork needed.

**Privacy mode.** Amounts already render as `••••••` via `Format.money(masked:)`. Under the
new design:
- Hero, all stat values, holdings values → masked.
- **Percentages and the chart shape stay visible.** Masking a percentage tells a
  shoulder-surfer nothing, and a hidden chart makes the screen useless. This is a deliberate
  call: privacy mode hides *magnitude*, not *trend*.
- The chart's Y axis has no labels anyway, so it leaks nothing.
- Scrub tooltip shows a masked value with a real date.
- Allocation and holdings share bars stay visible (they're relative, not absolute).

---

## Interactions

- **Drag-to-scrub.** `DragGesture(minimumDistance: 0)` on a chart overlay; map `x` to the
  nearest history point via `ChartProxy.value(atX:)`. While scrubbing:
  - Hero number becomes the value at that date, with the date replacing the range label.
  - Delta recomputes from the range's first point to the scrubbed point.
  - A 1pt vertical rule at the touch x, plus a 5pt dot on the curve.
  - Glass value bubble above the point, horizontally clamped inside the chart bounds.
  - On release, spring back to the range's latest value over ~0.25s.
- **Haptics.** `UIImpactFeedbackGenerator(style: .light)` once on scrub start; a
  `UISelectionFeedbackGenerator` tick each time the nearest data point changes, rate-limited
  to ~30/s so a fast drag doesn't buzz. Range pill taps get `.selectionChanged()`.
- **Number transitions.** `.contentTransition(.numericText(value:))` on the hero and every
  stat value, wrapped in `withAnimation(.snappy(duration: 0.25))` on refresh and on range
  change. This is the single highest-impact polish item (principle 6).
- **Range change.** Chart animates the domain change; the curve morphs rather than redrawing
  (`.animation(.easeInOut(duration: 0.3), value: selectedRange)`).
- **Pull to refresh.** Keep `.refreshable { await store.refresh() }`. Add a success haptic
  and animate the numbers in.
- **Portfolio switcher.** Moves from the current horizontal chip row into the **nav bar title
  as a `Menu`** (title + chevron), shown only when `portfolios.count > 1` as today. Chips cost
  a full row of vertical space at the top of the most valuable screen for a control most users
  touch once a month, and a menu scales past 3–4 portfolios where chips don't. Rejected:
  Delta's swipe-between-portfolios (collides with scrub). Deferred to phase 3: Delta's header
  cross-fade to the portfolio name on scroll, via `.onScrollGeometryChange`.
- **Privacy toggle.** Nav bar trailing, `eye` / `eye.slash` icon button. Currently buried in
  Settings; it belongs one tap from the numbers it hides.
- **Tap targets.** Allocation legend rows and holding rows are buttons (highlight /
  future drill-in). Stat cards are inert in phase 1.
- **Loading.** Skeleton shapes (dim rounded rects at the real dimensions), never a
  centered spinner — the Fey lesson. Cached snapshot renders immediately; refresh happens
  behind it.

---

## Implementation plan

### Files

New, all under `App/Views/Overview/`:

```
OverviewView.swift          screen scaffold, ScrollView, nav bar, refresh
HeroChartCard.swift         hero number + Swift Charts area chart + scrub
RangePills.swift            glass range selector (GlassEffectContainer)
StatPairRow.swift           generic 2-up stat card row
GrowthCard.swift            CAGR/YTD + market comps
AllocationCard.swift        segmented bar + legend
HoldingsCard.swift          ranked holdings with share bars
TaxEstimateRow.swift        collapsed disclosure row
OverviewModel.swift         @Observable view state (range, scrub, derived series)
```

Reused as-is: `Card`, `SectionTitle`, `RowDivider` (`App/Views/Components.swift`), `Theme`,
`Format`. `DashboardView.swift` is deleted at the end of phase 1; `MainTabView` in
`App/KuberaWidgetsApp.swift` swaps its first tab to `OverviewView` and should migrate from
`.tabItem` to the iOS 26 `Tab(_:systemImage:)` initializers at the same time.

### State split

**Goes in `AppStore`** (shared, cached, widget-visible):
- `history: [KuberaAPI.HistoryPoint]` — currently fetched inside `TrendsCalculator.refresh`
  and thrown away after computing trends. Promote it to observable state and cache it via
  `SharedStore` so the chart renders instantly from cache on launch.
- `cashOnHand: Double?` and `taxEstimate: TaxEstimate?` — new fetches, added to
  `PortfolioSnapshot` (both optional so existing cached snapshots still decode).

**Goes in `OverviewModel`** (per-screen, ephemeral, not cached):
- `selectedRange: Range` (`.week/.month/.quarter/.ytd/.year/.all`)
- `scrubbedPoint: HistoryPoint?`
- derived: `visibleSeries`, `yDomain`, `rangeChange`, `displayedValue`

Rationale: anything a widget could want, or that survives app launch, belongs in `AppStore`
+ `SharedStore` (that's the existing contract — every mutation writes through). Chart UI
state is neither.

### New fetches

1. **Cash on hand** — Kubera exposes it; add to `KuberaAPI.fetchSnapshot`'s parse, optional
   field on `PortfolioSnapshot`. Unit test the parse against a fixture with and without the
   field.
2. **Tax estimate** — same shape. Needs a small `TaxEstimate` struct (amount + rate +
   basis) so the expanded row has something to show.
3. **History promotion** — no new endpoint, just stop discarding
   `KuberaMCP.fetchHistory`'s result. Merge with `SharedStore.localHistory()` exactly as
   `TrendsCalculator` already does, so the chart and the trends agree.

Every one of these degrades to "module hidden" when absent. No new required credentials.

### Chart

Swift Charts, `iOS 16+` API, no third-party dependency:

```swift
Chart(model.visibleSeries, id: \.date) { point in
    AreaMark(x: .value("Date", point.day), y: .value("Net worth", point.netWorth))
        .foregroundStyle(fillGradient)
        .interpolationMethod(.monotone)
    LineMark(x: .value("Date", point.day), y: .value("Net worth", point.netWorth))
        .foregroundStyle(Theme.text)
        .lineStyle(.init(lineWidth: 2, lineCap: .round))
        .interpolationMethod(.monotone)
}
.chartYScale(domain: model.yDomain)
.chartXAxis(.hidden)
.chartYAxis(.hidden)
.chartOverlay { proxy in scrubLayer(proxy) }
```

`.monotone` interpolation, not `.catmullRom` — Catmull-Rom overshoots and can draw a net
worth curve that dips below a local minimum it never actually hit. That's a correctness
issue in a finance chart, not a style preference.

### Phases

**Phase 1 — structure (≈1 day).** `OverviewView` scaffold, hero + static Swift Charts area
chart, working range pills (plain capsules, no glass), Assets/Debts and Investable stat
rows, allocation segmented bar, holdings list, footer. Delete `DashboardView`, retarget the
tab. Tests: range-filtering and Y-domain math in `OverviewModel`, favorable-direction color
logic for debts.

**Phase 2 — glass + scrubbing (≈1 day).** Drag-to-scrub with tooltip and haptics, glass on
the pill row / tooltip / nav bar, `contentTransition(.numericText)` everywhere, tab bar
minimize behavior, portfolio switcher into the nav bar, privacy toggle into the nav bar.
Device review for glass. Tests: nearest-point lookup, scrub delta computation, masked
tooltip formatting.

**Phase 3 — extras (≈half day each, pick as wanted).** Cash on hand + tax estimate fetches
and modules; allocation legend → holdings filtering; "Show all holdings" detail screen;
skeleton loading states; optional module reordering.

Each phase lands as its own commit with its own tests, per the repo's working agreement.

### Risks

- **Simulator lies about glass.** Budget device time in phase 2; don't sign off on
  screenshots.
- **History gaps.** Kubera's daily series can have holes; the chart must not interpolate
  across a multi-week gap as a straight line without it being obviously a gap. Decide in
  phase 1 whether to break the line (preferred) or accept the straight segment.
- **Scrub vs. scroll gesture conflict.** A vertical `ScrollView` containing a horizontal
  drag gesture needs `minimumDistance: 0` on the chart plus care that vertical drags still
  scroll. Test on device with a thumb, not a trackpad.
- **`PortfolioSnapshot` decode compatibility.** New fields must be optional or every cached
  snapshot (and every installed widget) breaks on update.

---

## Sources

- [Apple Design Awards](https://developer.apple.com/design/awards/) — Copilot Money, 2024 Interaction finalist
- [Copilot Money](https://www.copilot.money/) · [Copilot Money review, FinCompareLab](https://www.fincomparelab.com/reviews/copilot-money-review/)
- [Customizing Your Dashboard — Monarch Money help](https://help.monarch.com/hc/en-us/articles/360058127551-Customizing-Your-Dashboard) · [Monarch tracking features](https://www.monarch.com/features/tracking)
- [Your Portfolio, Your Way — Delta Portfolio 3.0](https://delta.app/academy/post/your-portfolio-your-way) · [Delta features](https://delta.app/en/features)
- [Fey features](https://fey.com/features) · [Top FinTech interface designs, Goodface](https://goodface.agency/insight/top-10-fintech-product-interface-designs/)
- [Designing custom UI with Liquid Glass on iOS 26 — Donny Wals](https://www.donnywals.com/designing-custom-ui-with-liquid-glass-on-ios-26/)
- [LiquidGlassReference — conorluddy](https://github.com/conorluddy/LiquidGlassReference)
- [SwiftUI Liquid Glass: The Complete iOS 26 Guide — Atelier Socle](https://www.atelier-socle.com/en/articles/swiftui-liquid-glass-guide)
- [Understanding GlassEffectContainer in iOS 26](https://dev.to/arshtechpro/understanding-glasseffectcontainer-in-ios-26-2n8p)
