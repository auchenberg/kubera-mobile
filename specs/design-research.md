# Design research: state of the art on iOS, applied to Kubera Mobile

Written July 2026, against the iOS 26 SDK. Audience: a SwiftUI engineer about to
redesign `App/Views/SettingsView.swift` and `App/Views/WidgetsView.swift`, and to
retrofit Dynamic Type across the app (backlog items 8, 9 and 11).

All figures in code sketches are synthetic. This repo is public.

---

## TL;DR — the principles that matter for this app

1. **Glass is a layer, not a finish.** It belongs to floating controls that sit
   *above* content — pills, toolbars, the tab bar, transient tooltips — and must
   never become the background of a card holding a currency figure. The app
   already gets this right in `GlassBackground.swift`; the redesigns must not
   regress it. Apple gave the 2026 Interaction award partly for "best-in-class
   Liquid Glass integration", so doing this well is now a judged competency.
2. **Fixed `.system(size:)` is the single biggest design defect in the app.**
   Every screen ignores the user's text size. Apple's 2026 Inclusivity citation
   names exactly three APIs — Dynamic Type, Increase Contrast, Differentiate
   Without Color — and this app implements none of them. A design that cannot
   reflow is an unfinished design.
3. **One hero number, and it must animate its own changes.**
   `.contentTransition(.numericText(value:))` plus `.monospacedDigit()` is what
   separates a hero figure that feels alive from one that jump-cuts. Scrubbing
   the chart is a *value change*, so it should transition, not swap.
4. **Nested rounded corners must be concentric.** A 16pt card containing a 12pt
   button looks wrong at every size; iOS 26 ships `ConcentricRectangle` and
   `.rect(corners: .concentric)` so the inner radius derives from the outer one
   and the padding. The `Card` (r=16) / `FilledButtonStyle` (r=12) pairing in
   `Components.swift` is currently a hand-picked guess.
5. **Green/red alone is not a signal.** Direction must also be carried by a
   glyph or a sign character, and the greens must be the darker light-mode
   variants — which `WidgetTheme` already does for widgets and `Theme` should
   do for the app.
6. **Show the thing, don't label the thing.** The Widgets tab's job is to make
   someone want the widget on their Home Screen; a horizontally scrolling
   gallery of real widget views at true point size does that, a vertical list of
   captioned previews does not. Award-winning apps consistently replace
   descriptive chrome with a rendered instance of the real thing.
7. **Settings is an identity screen first.** The best account screens open with
   *who you are*, put the destructive action next to the identity it terminates,
   and push explanatory text to the bottom. Grouped-card lists in the middle.
8. **Motion earns its keep by being interruptible.** Scrub feedback, pill
   selection and glass morphing should all use spring animations that respond
   mid-flight; anything decorative must be gated behind Reduce Motion.
9. **Every glass surface must work in three configurations, not one.** Default,
   Reduce Transparency, and the **"Tinted" appearance mode Apple shipped in
   iOS 26.1** — which lives in appearance settings rather than Accessibility, so
   it is a mainstream preference many people run permanently. A tinted glass
   control over a chart gradient needs a deliberate opaque fallback or it becomes
   a grey smear.
10. **Empty and stale states are product surface, not error handling.** A
    finance app is judged on what it shows when the network is down and the
    cached number is four hours old.

---

## Apple Design Awards: what winning actually looks like

### 2026 winners and finalists (apps)

Twelve winners from thirty-six finalists across six categories: Delight and Fun,
Inclusivity, Innovation, Interaction, Social Impact, Visuals and Graphics.

| Category | App winner | Developer |
| --- | --- | --- |
| Interaction | **Moonlitt: Moon Phase Tracker** | Flipping Hues Srls, Italy |
| Visuals and Graphics | **Tide Guide: Charts & Tables** | Condor Digital, US |
| Delight and Fun | **grug** | Ocho, Netherlands |
| Inclusivity | **Guitar Wiz** | Bijoy Thangaraj, India |
| Innovation | **NBA: Live Games & Scores** (visionOS) | NBA, US |
| Social Impact | **Primary: News in Depth** (visionOS) | Wood Metal Rocks, US |

Finalists worth studying for this project: **Tide Guide** (Interaction finalist
*and* Visuals winner), **The Outsiders: Athlete Tracker** (Gentler Stories),
**Structured** (Inclusivity finalist), **Detail: AI Video Editor**,
**(Not Boring) Camera**.

**Two of Apple's own citations are, almost verbatim, the brief for this app.**

> **Moonlitt** — won *Interaction* for "an elegant interface for tracking
> celestial events," with **"easy onboarding and best-in-class Liquid Glass
> integration."**

Read that again: in 2026 Apple gave the Interaction award to an app partly *for
how well it adopted Liquid Glass*. Glass adoption is not a cosmetic tax this
year; it is a judged design competency. It also pairs glass with onboarding —
the same two things this app has already invested in (`GlassBackground.swift`,
`WelcomeView.swift`).

> **Guitar Wiz** — won *Inclusivity* as an "all-in-one toolkit that provides
> spoken instructions on everything from pitch to finger placement," leveraging
> **"Dynamic Type, Increased Contrast, and Differentiate Without Color."**

Those three named APIs are precisely the three this app does not implement.
Apple's Inclusivity award citation is a list of the gaps in backlog item 11.
This is the strongest available argument that Dynamic Type is not deferrable
polish.

### Per-app findings

**Tide Guide — the most relevant winner in the list.** A data-dense app whose
entire product is one continuous time series with a "now" position on it. It won
*Visuals and Graphics* and was an *Interaction* finalist for the same thing: the
tide curve is the interface. Apple's citation praises "hour-by-hour forecasts and
a crisp presentation of weather data," singling out **"full-screen charts filled
with custom animations"** and an **"aquatic theme, and sky-matching palette."**
Lessons that transfer directly to the Overview chart:

- **Full-screen charts.** The chart is the hero, not a 200pt illustration inside
  a card. Worth asking whether tapping the Overview chart should push a
  full-screen scrubable version — that is the move Apple rewarded.
- **Custom animations in the chart itself**, not just around it: the series
  animating in, the cursor, the transition between ranges. Apple called these
  out by name.
- **A palette derived from the data's own state** ("sky-matching"). The
  monochrome-plus-green/red palette here is a deliberate and defensible choice,
  but note that the award went to expressive, state-driven colour.
- Ships on six platforms including watchOS and visionOS, which forces layout
  discipline where nothing is positioned by absolute point offsets — and is
  impossible with fixed `.system(size:)` type.

**The Outsiders: Athlete Tracker (Gentler Stories).** Interaction finalist,
iOS + watchOS. Gentler Stories' house style — also visible in *Gentler
Streak*, a 2022 ADA winner — is the reference for "quantified numbers without
the anxiety": a single ring or arc per metric, prose-form summaries next to the
figures ("you are ahead of where you were last month" rather than "+3.1%"), and
deliberately soft language around bad numbers. For a net-worth app, the
transferable move is **pairing each figure with a plain-language reading of it**.

**Structured.** Inclusivity finalist on four platforms. Its notable trait is
that the same information architecture survives from watch complication to Mac
window, and that it is fully usable at accessibility text sizes — the timeline
reflows rather than truncating.

**grug (Delight and Fun winner).** An affirmation app: "a playful way to discover
and embrace daily wisdom," where "each prompt is thoughtfully delivered to offer
users a small but meaningful moment of reflection." The transferable point is
narrow but real — **delight came from the pacing and framing of a single piece of
text**, not from effects. The nearest analogue here is already in the app: the
Overview greeting, and the "quiet marker revealing what an unfamiliar hello
means". That instinct is correct and under-exploited. A one-line plain-language
reading of the portfolio's state, delivered with some care, is the cheapest
delight available to a net-worth app — and it is the same move Gentler Stories
makes (below).

**(Not Boring) Camera / Not Boring Software.** Andy Works' apps are the
canonical "delight through material and motion" reference: physics-driven
controls, custom easing, sound. The takeaway for a finance app is narrower than
it looks — the lesson is not "add whimsy", it is that **the single most-used
control in the app deserves a bespoke, tactile treatment** while everything
else stays standard. For Kubera Mobile that control is the range pill row and
the scrub gesture.

**Copilot Money.** Worth being precise, because it is often miscredited: Copilot
Money was a **2024 Apple Design Award *finalist* in Innovation**, not a winner
(Innovation went to *Lost in Play*). Its actual credentials are ADA finalist
2024, App Store **Editors' Choice** in Personal Finance, and a Webby — plus
sustained App Store editorial featuring. It is still the closest design
comparison this project has, and the praise is consistently about *native feel*:
typography, spacing and animation that read as built for iOS rather than ported.
What it does that a competent finance app does not:

- **A single, calm hero figure per screen** with the comparison stated as a
  short phrase, not a wall of secondary stats.
- **Category colour is a real, owned system** — a hand-tuned palette where every
  category has a light and dark variant that both clear contrast minimums, so
  charts are readable rather than merely colourful.
- **Editing is inline and immediate.** Recategorising a transaction happens
  where the transaction is, with an immediate optimistic update and a haptic.
- **Charts respond to touch everywhere they appear**, including small inline
  ones, so a chart is never a static picture.
- **Onboarding is the product**, not a slideshow: it connects an account and
  shows real numbers as fast as possible.

### Distilled: what an award-winning iOS app in 2026 does that a competent one does not

1. **It has one signature interaction that is clearly bespoke** and polished far
   past reasonable — and everything else is stock UIKit/SwiftUI. Competent apps
   distribute mediocre custom work evenly.
2. **It is native on every platform it ships to**, which is really a claim about
   layout discipline: no absolute positioning, no fixed font sizes, no assumed
   width.
3. **State is expressed through the whole surface.** Loading, empty, stale,
   error and success are designed compositions, not a spinner and an alert.
4. **Numbers and shapes animate between values**, never cut.
5. **It survives the accessibility inspector.** Dynamic Type to AX5, VoiceOver
   labels that read as sentences, Reduce Motion and Reduce Transparency paths
   that are designed rather than degraded.
6. **Typography is a hierarchy of three or four sizes, used consistently**, not
   eleven ad-hoc sizes. (Kubera Mobile currently uses at least 12/13/14/15/16/17/20/22.)
7. **Haptics are semantic** — a selection tick on scrub, a success thud on
   connect — and never decorative.
8. **It respects the floating-controls layer** iOS 26 introduced: content
   scrolls under glass, and the app does not build its own competing bottom bar.

---

## Liquid Glass: the rules

### Where glass goes

Apple's model is a strict layer split:

- **Content layer** — scrollable substance. Opaque or near-opaque. Cards,
  tables, charts, text. *No glass.*
- **Controls layer** — floats above content, always: navigation bars, tab bars,
  toolbars, sheets' grabbers, floating action clusters, transient popovers,
  sliders, the search field. *Glass lives here and only here.*

The practical test: if the element scrolls with the content, it is content. If
it stays put while content moves under it, it is a control and may be glass.

### Where glass must not go

- **Behind small text**, and especially behind monospaced numerals. Glass
  samples and blurs what is behind it; a 13pt masked API key or a currency
  figure over a sampling backdrop loses the crispness the eye uses to read
  digits. This is the reason `GlassBackground.swift` keeps `Theme.card` opaque
  and it is the single rule most likely to be broken during a redesign.
- **Glass on glass.** Two glass layers stacked sample each other and produce a
  muddy, low-contrast result. Apple's guidance is one glass layer at a time; if
  you need grouped glass elements, that is what `GlassEffectContainer` is for —
  it merges them into *one* glass surface rather than stacking two.
- **Dense data.** Tables, lists of rows, holdings, allocation bars.
- **Large fill areas.** Glass reads as a floating object; a full-screen glass
  panel just reads as a broken blur.
- **Anything that needs a guaranteed contrast ratio.** You cannot certify
  contrast against a backdrop you do not control.

### The APIs, precisely

```swift
// A single floating control. `in:` takes the shape — capsule for pills.
Text(rangeLabel)
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .glassEffect(.regular, in: .capsule)

// Interactive glass reacts to touch (scale + highlight). Use it on anything
// tappable; without `.interactive()` a glass button feels dead.
.glassEffect(.regular.interactive(), in: .capsule)

// Tint for legibility over busy content — not for decoration, and not at
// full strength.
.glassEffect(.regular.tint(Theme.card.opacity(0.4)), in: .rect(cornerRadius: 12))

// `.clear` is thinner and more transparent; only over media, never over text.
.glassEffect(.clear, in: .capsule)
```

`Glass` modifiers that matter: `.regular` (the default, adaptive), `.clear`
(more transparent, for media backdrops), `.tint(_:)`, `.interactive(_:)`, and
`.identity` (no effect — useful as a conditional).

**Grouping.** Multiple glass elements near each other must share a container, or
each samples the backdrop independently and their edges fight:

```swift
@Namespace private var glassNamespace

GlassEffectContainer(spacing: 12) {
    HStack(spacing: 12) {
        ForEach(ranges) { range in
            Button(range.label) { select(range) }
                .buttonStyle(.glass)
                .glassEffectID(range.id, in: glassNamespace)
        }
    }
}
```

- `GlassEffectContainer(spacing:)` merges overlapping/nearby glass shapes into
  one surface, applies consistent blur and lighting, enables morphing between
  them, and is faster to render than N independent glass views.
- `.glassEffectID(_:in:)` identifies a glass shape across state changes so it
  *morphs* rather than cross-fading — this is the effect Apple's own toolbars
  use when a button expands into a group.
- `.glassEffectUnion(id:namespace:)` forces several elements to read as one
  glass body even when separated by a larger gap than `spacing` would merge.
- `.glassEffectTransition(_:)` controls how a glass shape enters/leaves.

**Button styles.** `.buttonStyle(.glass)` for a neutral glass button;
`.buttonStyle(.glassProminent)` for the one primary action on the surface —
it takes the tint and reads as filled glass. `.glassProminent` is the correct
replacement for the app's hand-rolled `FilledButtonStyle` on iOS 26, with
`FilledButtonStyle` remaining as the pre-26 fallback.

**`backgroundExtensionEffect()`** mirrors and blurs a view's own edges outward
so a bounded image appears to continue under an adjacent glass control (a nav
bar, a sidebar). It is for edge-to-edge imagery — a hero photo behind a nav bar
— and is *not* a general background: applying it to a chart card would smear
the chart's own gradient into the margins.

**Scroll edge effects.** Where content passes under a glass bar, iOS 26 blurs and
dims it at the boundary so text does not collide with the bar's edge. **This is
automatic** for `ScrollView`, `List` and `Form` on iOS 26+ — you do not add it,
you only tune it, via `.scrollEdgeEffectStyle(_:for:)`:

- `.automatic` — the default.
- `.soft` — a gradual, diffused fade.
- `.hard` — a sharp cutoff with a visible dividing line, for discrete UI
  boundaries.

`.scrollEdgeEffectHidden(_:for:)` opts out entirely. **Do not fake any of this**
with a manual `LinearGradient` overlay; the system version adapts to the bar's
state, and a hand-rolled one will fight it now that it is applied by default.

**Forward-compatibility trap:** iOS 27 changes the default to `.hard`. An app
that relies on iOS 26's softer look without saying so will change appearance on
OS upgrade. If the soft fade is the intent for the Overview's scroll under the
nav bar, **write `.soft` explicitly** rather than leaving it `.automatic`.

### Content meeting a floating tab bar

The tab bar in iOS 26 floats over content and can shrink out of the way:

```swift
TabView {
    Tab("Overview", systemImage: "chart.line.uptrend.xyaxis") { OverviewView() }
    Tab("Widgets", systemImage: "square.grid.2x2") { WidgetsView() }
    Tab("Settings", systemImage: "gearshape") { SettingsView() }
}
.tabBarMinimizeBehavior(.onScrollDown)
.tabViewBottomAccessory {
    // Persistent mini-control above the tab bar. Apple Music's now-playing
    // bar is the archetype.
    NetWorthMiniBar()
}
```

- `.tabBarMinimizeBehavior(_:)` takes `.automatic` (system decides), `.never`
  (always full), or `.onScrollDown` (collapses to a compact pill on downward
  scroll, restores on scroll up). It is the cheapest way to look like an iOS 26
  app — but see NN/g's predictability objection below before applying it
  everywhere.
- `.tabViewBottomAccessory { }` places a persistent accessory in the same glass
  group as the tab bar; Apple Music's now-playing bar is the archetype. It
  *reflows* automatically when the tab bar minimizes. Read
  `@Environment(\.tabViewBottomAccessoryPlacement)` — `.expanded` means it floats
  above the full tab bar, `.inline` means the bar has minimized and the accessory
  has merged into it, and it can be `nil` (undefined). Render a compact variant
  for `.inline`. A single-line net-worth readout fits; anything two lines does not.

**Two shipped bugs to plan around, both of which this app is exposed to** —
every tab here wraps a `NavigationStack`:

- `.tabBarMinimizeBehavior(.onScrollDown)` has been reported **not to trigger in
  tabs that use `NavigationStack(path:)`**. Verify on device before designing
  around the minimize behaviour; if it does not fire, the design must still work
  with a permanently full-height tab bar.
- Conditionally rendering `.tabViewBottomAccessory` (i.e. returning it or not
  based on state) **has been reported to crash with `TabView(selection:)`**.
  If the net-worth accessory should only appear once credentials exist, prefer
  always attaching the accessory and varying its *content* — including to an
  `EmptyView` — over conditionally attaching the modifier.
- **Do not add bottom padding by hand** to clear the tab bar. Use
  `.safeAreaInset(edge: .bottom)` or let the system's safe area do it — hard-coded
  `Spacer(minLength: 40)` at the end of a `ScrollView` (which both
  `SettingsView` and `WidgetsView` currently do) is exactly the pattern that
  breaks when the bar minimizes.

### The concentricity rule

When one rounded rectangle nests inside another, their corner arcs must share a
centre. The relationship is `innerRadius = outerRadius - padding`. Get it wrong
and the gap between the two curves visibly varies around the corner — the classic
"squeezed corner" that makes a layout feel slightly off without anyone naming it.

iOS 26 makes this automatic, via two APIs that only work as a pair:

```swift
// 1. The container declares the shape children resolve against.
//    Must conform to `RoundedRectangularShape` — RoundedRectangle,
//    Capsule and Circle all do.
.containerShape(.rect(cornerRadius: 16))

// 2. The child asks for a concentric shape. Radius is derived from the
//    container's radii minus the distance to them — i.e. the padding.
ConcentricRectangle()
ConcentricRectangle(corners: .concentric(minimum: 8), isUniform: true)

// Or on any shape-taking modifier (note: `corners:`, plural):
.clipShape(.rect(corners: .concentric))
.glassEffect(.regular, in: .rect(corners: .concentric(minimum: 8), isUniform: true))
```

**The gotcha that will bite:** when a corner is too far from the container's
corresponding edge, its resolved radius falls back to **0** — a square corner —
unless you pass `isUniform: true` (which makes every corner adopt the largest
resolved radius) or a `minimum:`. A button inset well inside a tall card is
exactly that case, so **always pass a `minimum:`** in this app rather than
relying on the bare form.

Concretely for Kubera Mobile: `Card` in `Components.swift` should add
`.containerShape(.rect(cornerRadius: 16))` alongside its existing `clipShape`,
and `FilledButtonStyle` plus the range pills should switch from their hardcoded
radius 12 to `.rect(corners: .concentric(minimum: 8), isUniform: true)` under
`#available(iOS 26, *)`, keeping 12 as the fallback.

Also relevant: **device-corner concentricity**. Full-bleed content anchored to
the display's corners should follow the screen radius rather than a guessed
number, which is what a `ConcentricRectangle` resolves to when its container is
the safe-area-ignoring root.

### What broke, and what Apple changed

The first iOS 26 betas over-applied glass and were criticised hard. This is not
gossip — it changed the shipping design, and the criticisms are a usable
checklist.

**What Apple changed.** Across betas 2–4, Apple increased the material's opacity
and frostiness and added internal blur, so the shipping look is noticeably less
see-through than the WWDC reveal. Then, in **iOS 26.1, Apple shipped a "Tinted"
appearance control** that suppresses the bloom and mutes internal highlight
contrast, producing a flatter panel much closer to pre-Liquid iOS. The important
detail for us: **it lives in the appearance settings, not in Accessibility.**
Apple positioned toning glass down as a mainstream preference rather than a
disability accommodation, which means a meaningful share of users will run it
permanently. Glass surfaces must look deliberate in *three* configurations:
default, Tinted, and Reduce Transparency.

**What critics named** (Nielsen Norman Group's critique is the most substantive,
and each point is a real risk for this app):

1. **Transparency creates illegibility.** "Anything placed on top of something
   else becomes harder to see." NN/g's examples are text over background images
   and email subject lines over other content — which is precisely the failure
   mode of a currency figure over a chart gradient.
2. **Touch targets shrank and crowded.** The floating tab bar squeezes items
   below the ~44pt / 1cm minimum. Directly relevant: the range pill row is a
   horizontal cluster of small glass controls, and it must not get tighter in
   the name of looking like the system.
3. **Predictability loss.** Controls that appear and disappear contextually —
   collapsing tab bars, conditional buttons — force users to rescan rather than
   build habits. This is a genuine argument *against* enthusiastic adoption of
   `.tabBarMinimizeBehavior`; adopt it because content benefits, not because it
   is new, and never hide a control the user needs mid-task.
4. **Motion for its own sake.** "Motion for motion's sake is not usability. It's
   distraction with a side of nausea." Glass morphing should mark a real state
   change (range selected, control group expanded), never idle.
5. **Discoverability decline** from stripped labels — unlabelled back buttons,
   tabs behind overflow. Keep the tab bar's text labels.

Two further practical complaints worth designing against: glass **washes out in
direct sunlight** at high brightness, and it causes **visual fatigue during
prolonged reading**. Both argue for the same thing this app already does — keep
the reading surfaces opaque.

**Design for the frosted, shipping look, not the beta screenshots.** And check
every glass surface with Reduce Transparency on, because that is a real
configuration many users run permanently.

The engineering lesson for a mixed-deployment app like this one: the
`#available(iOS 26, *)` + material fallback structure in
`GlassBackground.swift` is the right shape, and the fallback must be designed,
not merely present. `.ultraThinMaterial` over a white card is nearly invisible,
which is why that file adds a hairline — keep that.

---

## Data-dense screens: per-pattern guidance

### The hero figure that changes

**Pattern.** One figure, large, monospaced digits, animating between values.

```swift
Text(netWorth, format: .currency(code: currency))
    .font(.system(.largeTitle, design: .default, weight: .semibold))
    .monospacedDigit()
    .contentTransition(.numericText(value: netWorth))
    .animation(.snappy(duration: 0.25), value: netWorth)
```

- `.monospacedDigit()` is non-negotiable for a figure that updates — without it
  the number's width jitters as digits change and the whole layout twitches.
- `.contentTransition(.numericText(value:))` rolls digits like Apple's own
  timers and Stocks; passing `value:` lets it choose an up/down roll direction.
- Wallet and Stocks both keep the hero figure **fixed in place** while the
  comparison line beneath it changes. Do not move the hero.
- **Fey** (the investing app most often cited for design) demonstrates the
  inverse discipline: the hero figure is the only large type on the screen, and
  everything else is one or two steps smaller. Restraint reads as confidence.

### Chart scrubbing feedback

Scrubbing is the single interaction a portfolio app lives or dies on. What the
best ones do:

- **Robinhood** set the canon: drag anywhere on the chart, the hero figure and
  the delta retarget to the touched point, a vertical rule and a dot follow the
  finger, and releasing snaps back to "now". Kubera Mobile already does this.
- **Delta** and **Revolut** add a *time label* at the cursor, so you know which
  day you are reading. If the tooltip shows only a value, half the information
  is missing.
- **Selection haptics.** A `.selection` feedback tick as the cursor crosses each
  data point is what makes scrubbing feel physical.
  `.sensoryFeedback(.selection, trigger: scrubbedIndex)` — trigger on the
  *index*, not the value, or a flat stretch fires nothing and a volatile one
  fires continuously.
- **Use the first-party selection API rather than a hand-rolled `DragGesture`.**
  `.chartXSelection(value:)` is iOS 17+, so it is available at this app's
  deployment target, and it gives you the platform's own hit-testing and
  snapping for free. iOS 26 adds `.chartGesture` for fully custom gestures, but
  reach for it only if selection genuinely cannot express the interaction.

  ```swift
  @State private var scrubbedDate: Date?

  Chart(points) { point in
      AreaMark(x: .value("Date", point.date), y: .value("Net worth", point.value))
      if let scrubbedDate, let hit = nearest(to: scrubbedDate) {
          RuleMark(x: .value("Date", hit.date))
          PointMark(x: .value("Date", hit.date), y: .value("Net worth", hit.value))
      }
  }
  .chartXSelection(value: $scrubbedDate)
  .sensoryFeedback(.selection, trigger: nearest(to: scrubbedDate)?.id)
  ```

  Note `chartYSelection` and the `ClosedRange` bindings exist too, if a range
  selection ever becomes interesting.
- **Never let the y-axis rescale during a scrub.** Rescaling makes the line move
  under the finger, which feels broken. Fix the domain per range, not per frame.
- On release, animate back — `withAnimation(.snappy)` on clearing the selection.
- Stocks shows the delta *for the scrubbed point relative to the range start*,
  not relative to today. Pick one and label it; ambiguity here is a correctness
  bug wearing a design costume.

### Sparklines vs full charts

- **Sparkline** when the chart is a *supporting attribute of a row*: a holding
  in a list, a widget, an account in a picker. No axes, no labels, no
  interaction, 20–40 points maximum, sized to the row's cap height times ~2.
  Direction colour only.
- **Full chart** when the chart is the *subject*: axes, a selectable range, and
  scrubbing. If you draw axes, they must be legible; a full chart at 90pt tall
  is worse than a sparkline.
- Apple's **Stocks** is the reference for the split: sparkline in the list row,
  full interactive chart on the detail screen, same data.
- **Do not put a sparkline and a full chart of the same series on one screen.**
- Sparklines in a dense list should share a **common y-domain** if the reader is
  meant to compare them, and be independently scaled if they are not — and the
  choice must be stated somewhere, because readers assume comparability.

### Positive/negative colour that survives accessibility review

- Green/red fails for ~8% of men (deuteranopia/protanopia). The fix is
  **redundant encoding**: an arrow or triangle glyph, an explicit `+`/`−`, and
  position. Apple's Stocks uses filled green/red *chips* with a sign inside —
  the sign is doing the work, the colour is reinforcement.
- **The bright dark-mode green is unreadable on white.** This app's
  `WidgetTheme` already resolves a darker green and red in light mode; `Theme`
  must do the same. Target ≥4.5:1 for figures at body size, ≥3:1 for large
  figures and for the chart's stroke.
- Do not rely on the chart's **gradient fill** for contrast — fills sit at low
  opacity and cannot carry meaning. The stroke does.
- Consider a **neutral state**: exactly-zero change should be neither green nor
  red. A 0.00% day shown in green is a small lie.
- Respect **`@Environment(\.accessibilityDifferentiateWithoutColor)`** — when set,
  force direction glyphs on even in compact layouts where they would normally be
  dropped, and add a pattern or border to allocation segments. This is one of the
  three APIs Apple named in the 2026 Inclusivity citation.
- Respect **`@Environment(\.colorSchemeContrast)`** — `.increased` means the user
  has Increase Contrast on. Darken/lighten `Theme.dim` toward `Theme.text`, raise
  the hairline border's opacity, and use the higher-contrast green/red variants.
  Also named in that citation.
- `@Environment(\.legibilityWeight)` reports Bold Text. `Theme`'s semibold
  labels are fine, but hairlines at `1/displayScale` and 13pt dim captions are
  what Bold Text users are trying to fix — check them.
- Red is also the destructive-action colour. If `Theme.negative` is both "you
  lost money" and "Disconnect", they should not be the *same* red at the same
  weight; the app currently shares `Theme.negative` between `ActionButton`'s
  destructive kind and loss figures.

### Number transitions

- Currency: `.currency(code:)` via `Text(value, format:)`, never manual string
  building — it gets grouping separators, negative-number conventions and RTL
  right per locale.
- Compact ("$1.24M") is a *display preference*, which this app already models in
  `WidgetSettings.compactNumbers`. Compact figures must still be exact in
  VoiceOver: set an `accessibilityValue` with the full number.
- Percentages: `.percent` format with an explicit fraction-length so a value
  does not oscillate between `3.1%` and `3.14%` between refreshes.
- Privacy mode masking should **preserve digit count and width** (`•••••••`
  sized with monospaced digits) so toggling it does not reflow the screen.

### Empty, loading and stale states

- **Loading**: `.redacted(reason: .placeholder)` over the real layout, so the
  screen's shape is right before the data lands. Never a centred spinner on a
  data screen — it discards the layout information the user already has.
- **Stale**: show the number *and* its age ("as of 09:41"). A finance app that
  shows a confident figure from four hours ago without saying so is lying.
  This matters doubly here because widget data has its own refresh cadence.
- **Empty**: `ContentUnavailableView` is the platform answer, with a real action
  in it. For a portfolio with no history, the empty state should explain *why*
  (no growth-history token) and link to the fix, which in this app is the MCP
  token row in Settings.
- **Error**: one sentence, in the place the data would have been, with a retry.
  Not an alert — alerts interrupt and lose the context of which section failed.
  `SettingsView`'s per-surface status lines (REST vs History failing
  independently) are a genuinely good instance of this and should survive the
  redesign.

---

## Settings / account screens: what the best ones do

The reference the backlog already names — **Photos' profile sheet** — is the
right one. The pattern, generalised across Photos, Apple Music, App Store,
Wallet, Revolut and Monarch:

1. **Identity block at the top, centred, not a list row.** Avatar or monogram,
   display name, then one line of secondary context. It answers "whose account
   is this?" before any scrolling.
2. **The account's destructive action sits with the identity**, not stranded in
   the middle of the scroll. Sign Out is directly under the identity block in
   Apple's own sheets. Kubera Mobile's "Disconnect Kubera" currently floats
   between Preferences and Data & privacy, which is the worst place for it.
3. **Grouped cards in the middle**, each with a short uppercase header, rows
   that are one line of label plus one line of description, and a right-hand
   control (toggle, checkmark, disclosure). Never mix a toggle row and a
   navigation row visually in the same group if their tap behaviours differ.
4. **Status is stated, not implied.** Apple Music's account sheet shows
   subscription state as text. Kubera Mobile's per-surface REST/History lines
   are the right idea; they belong *in the header*, describing the connection
   the header identifies.
5. **Secrets are shown as evidence of existence, not as values.** A masked key
   confirms "something is set" — which is all the user needs. Prefer a
   checkmark/status glyph plus a short mask over a long monospaced string; the
   long string invites squinting at data the user cannot act on.
6. **Explanatory and legal text last**, in secondary colour, at footnote size.
   Never above an interactive control.
7. **Monogram over avatar.** The backlog's open question answers itself: a
   two-letter monogram in a tinted circle, derived from `KuberaProfile.name`,
   costs nothing, never fails to load, and is what Apple does when there is no
   photo. Do not spend a network fetch and a cache on a screen opened twice.

What to avoid: a stock `Form`/`List` with `.insetGrouped` style will look
generic next to this app's custom `Card`, and mixing the two on one screen looks
like two apps. Pick the `Card` system and stay in it.

---

## Widget galleries and previews

How apps present the widgets they offer:

- **The winning move is a horizontally scrolling row of widgets rendered at
  their true point size**, grouped by family. It shows the Home Screen result
  instead of describing it. Vertically stacked captioned previews read as
  documentation.
- **Render the real widget views**, never mockups. This app already does the
  right thing by keeping them in `Shared/WidgetViews.swift` and rendering them
  with live data — that must not regress into a screenshot.
- **Show every family the widget supports**, including Lock Screen accessories,
  which `WidgetsView` currently does not preview at all despite the labels
  claiming "small, medium & Lock Screen".
- **Lock Screen accessories need their own backdrop.** An
  `.accessoryRectangular` widget renders as vibrant white-on-transparent; on a
  white card it disappears. Preview it on a dark, slightly blurred plate that
  stands in for a wallpaper.
- **A peek at the next card** (partial card visible at the trailing edge) is the
  cheapest discoverability affordance for a horizontal scroller, and
  `.scrollTargetBehavior(.viewAligned)` with `.scrollTargetLayout()` gives
  snapping. Page dots are usually unnecessary if a peek is present.
- **Widget size fidelity matters more than fitting.** A medium widget is 338pt
  wide and does not fit a 393pt phone screen with 20pt margins plus a card's
  16pt padding — which is why `WidgetsView` currently *scales it down*, and a
  scaled-down widget misrepresents its text size. Horizontal scrolling solves
  this properly: let the medium widget be full width and scroll.
- Since iOS 17, `#Preview(as: .systemSmall)` with `WidgetPreviewContext` renders
  widgets in Xcode; the same timeline-provider sample data should feed both the
  Xcode previews and the in-app gallery, so there is one source of sample truth.
- **Do not promise to open the widget gallery.** There is no API. The
  walkthrough sheet in `WidgetsView` is the honest answer and should stay;
  consider making it a `.sheet` with `.presentationDetents([.medium])` only, and
  illustrating each step with a small rendered graphic rather than an SF Symbol
  in a 32pt frame.

---

## Accessibility as a design constraint

### Dynamic Type

This is backlog item 11 and it is the app's biggest gap. Concretely:

- **`.system(size: 16)` does not scale. Ever.** It ignores the user's setting
  entirely. `.font(.body)` scales. `.font(.system(.body, design: .monospaced))`
  scales *and* keeps the monospaced design — that is the replacement for
  `.system(size: 13, design: .monospaced)` in `SettingsView`'s credential rows.
- Map the app's ad-hoc sizes onto text styles rather than inventing a parallel
  scale:

  | Current | Use |
  | --- | --- |
  | `.system(size: 12, weight: .semibold)` + kerning (`SectionTitle`) | `.font(.caption)` with `.textCase(.uppercase)` |
  | `.system(size: 13)` (secondary/detail) | `.font(.footnote)` |
  | `.system(size: 14)` (privacy body) | `.font(.subheadline)` |
  | `.system(size: 15)` | `.font(.subheadline)` |
  | `.system(size: 16)` (row label, button) | `.font(.body)` |
  | `.system(size: 17, weight: .semibold)` (status headline) | `.font(.headline)` |
  | `.system(size: 22, weight: .bold)` (sheet title) | `.font(.title2)` |
  | hero net worth | `.font(.largeTitle)` or `.system(.largeTitle, weight:)` |

- **`@ScaledMetric` for everything that is not text but must grow with it**:
  icon frames, row min-heights, the widget-preview plate, card padding, the
  monogram circle's diameter.

  ```swift
  @ScaledMetric(relativeTo: .body) private var symbolWidth: CGFloat = 32
  @ScaledMetric(relativeTo: .body) private var rowMinHeight: CGFloat = 44
  ```

  Note `relativeTo:` — scaling an icon against `.body` when its label uses
  `.footnote` makes them drift apart at large sizes.
- **Switch layout at accessibility sizes, don't just grow.** A row that is
  label-left / value-right must become stacked:

  ```swift
  @Environment(\.dynamicTypeSize) private var typeSize

  // ...
  if typeSize.isAccessibilitySize {
      VStack(alignment: .leading) { label; value }
  } else {
      HStack { label; Spacer(); value }
  }
  ```

  Or use `ViewThatFits { HStack { … }; VStack { … } }` and let it choose.
- **Toggles at AX sizes.** A `Toggle` with a two-line label (which all three
  rows in `preferencesCard` have) crushes badly at AX3+. The standard fix is
  `LabeledContent`/`Toggle` with the description moved to a footer, or a
  vertical layout at accessibility sizes.
- **Where clamping is legitimate**: content that is genuinely fixed-canvas —
  the widget previews. A widget's own text does not grow with the phone's
  setting beyond the widget's own scaling, so
  `.dynamicTypeSize(...DynamicTypeSize.xxxLarge)` on the preview plate is
  correct there and wrong everywhere else. Do not use it to paper over a layout
  that will not reflow.
- `lineLimit` + `minimumScaleFactor` — which the app currently relies on — keeps
  things from breaking but *shrinks text the user asked to enlarge*. It is a
  guard for the hero figure, not a Dynamic Type strategy.
- Test at **AX5** in the Accessibility Inspector and in Xcode previews
  (`.environment(\.dynamicTypeSize, .accessibility5)`).

**Testing the other settings in previews.** `colorSchemeContrast` and
`accessibilityDifferentiateWithoutColor` are read-only in production, but the
underscored keys are settable in previews:

```swift
#if DEBUG
#Preview("AX5 + increased contrast") {
    SettingsView()
        .environment(\.dynamicTypeSize, .accessibility5)
        .environment(\._colorSchemeContrast, .increased)
        .environment(\._accessibilityDifferentiateWithoutColor, true)
}
#endif
```

Keep these inside `#if DEBUG` — they are private symbols and must not reach an
App Store binary. Given how many states this app now has (light/dark ×
default/Tinted/Reduce Transparency × AX sizes), a `Shared/` preview helper that
enumerates them is worth the twenty lines.

### Reduce Transparency and Reduce Motion

Both are directly load-bearing for a glass-heavy design.

```swift
@Environment(\.accessibilityReduceTransparency) private var reduceTransparency
@Environment(\.accessibilityReduceMotion) private var reduceMotion
```

- `glassEffect` degrades automatically under Reduce Transparency, but **a tinted
  glass control needs checking** — the scrub tooltip passes `Theme.card` at 0.4
  opacity, and once the glass goes opaque that tint may land as a grey wash over
  a grey card. Test it; if it reads badly, branch to a solid `Theme.card` fill
  with the hairline border.
- Under Reduce Transparency the pre-26 `.ultraThinMaterial` fallback also flattens,
  so the hairline in `ControlGlassModifier` becomes the only thing defining the
  control. Keep it, and consider raising its contrast in that mode.
- Under Reduce Motion: drop the glass **morph** (`glassEffectID` transitions),
  drop any scale/spring on selection, and replace with a cross-fade. Keep
  `.contentTransition(.numericText(value:))` — a rolling number is not vestibular
  motion, and removing it makes updates harder to notice, not easier. If in
  doubt, `.animation(reduceMotion ? .none : .snappy, value:)`.
- Chart animation on range change should be suppressed under Reduce Motion —
  a whole line re-drawing across the screen is exactly the kind of large-area
  movement the setting exists for.

### Contrast on financial figures

- ≥4.5:1 for body-size figures, ≥3:1 for large text (≥18pt regular / ≥14pt bold)
  and for graphical objects like a chart stroke or an allocation segment.
- Check **both** appearances. Bright green (`#30D158`-family) is roughly 2:1 on
  white — a failure — which is why light mode needs the darker variant.
- Check the **secondary/dim** colour too. `Theme.dim` carries most of the
  explanatory copy in `SettingsView`; if it is below 4.5:1 the whole privacy
  paragraph fails.
- Allocation segments and composition bars need a **stroke or gap between
  adjacent segments**, because two adjacent fills that each pass against the
  background can still be indistinguishable from each other.

### VoiceOver for charts

A Swift Chart with no accessibility work is an unlabelled image — the single
most common accessibility failure in finance apps.

```swift
Chart(points) { … }
    .accessibilityLabel("Net worth over the selected range")
    .accessibilityChartDescriptor(NetWorthChartDescriptor(points: points))
```

- Implement `AXChartDescriptorRepresentable`, returning an `AXChartDescriptor`
  with an `AXNumericDataAxisDescriptor` for each axis and an
  `AXDataSeriesDescriptor` for the series. This gives VoiceOver users the Audio
  Graph experience — they can hear the shape of the curve and step through
  points.
- Per-point marks should also carry `.accessibilityLabel` (the date) and
  `.accessibilityValue` (the formatted currency) so swipe-through works.
- The **range pills** need `.accessibilityAddTraits(.isSelected)` on the active
  one, or VoiceOver cannot report which range is showing.
- The **hero figure and its delta should be one accessibility element**, not
  three: "Net worth, $1,240,000, up 3.1 percent year to date". Use
  `.accessibilityElement(children: .combine)` and override the label. As three
  separate elements it reads as noise.
- **Sparklines in rows should be `.accessibilityHidden(true)`** and their
  meaning folded into the row's own label — otherwise every holding row makes
  VoiceOver users swipe past an unlabelled chart.
- Widget previews: the whole preview card should be one element labelled as
  "Preview of the Net Worth widget, small size", not a traversal of the
  widget's internal text.

---

## Applied to Kubera Mobile: prioritised changes

### Quick wins

1. **Concentric corners in `Components.swift`.** `Card` adds
   `.containerShape(.rect(cornerRadius: 16))`; `FilledButtonStyle` and the range
   pills switch to `.rect(corners: .concentric(minimum: 8), isUniform: true)`
   under `#available(iOS 26, *)`, keeping radius 12 as the fallback. Pass the
   `minimum:` — without it an inset corner can resolve to square. Fixes a
   visible-but-unnamed wrongness on every screen.
   *Files:* `App/Views/Components.swift`, `App/Views/GlassBackground.swift`.
2. **`.monospacedDigit()` + `.contentTransition(.numericText(value:))` on the
   hero figure and the delta** in `OverviewView.swift`. Makes scrubbing feel
   built rather than assembled.
3. **`.tabBarMinimizeBehavior(.onScrollDown)`** on the root `TabView`, gated to
   iOS 26 — but **verify it fires on device**, since it is reported not to work
   in tabs using `NavigationStack(path:)`, which is this app's structure.
4. **Remove the hand-rolled bottom padding.** `Spacer(minLength: 40)` at the end
   of the `ScrollView` in `SettingsView.swift:32` and `WidgetsView.swift:67`
   should be `.safeAreaPadding(.bottom)` or nothing at all, or it will double up
   against a minimizing tab bar.
5. **`.buttonStyle(.glassProminent)`** for `ActionButton(kind: .primary)` on
   iOS 26, `FilledButtonStyle` below. Also gives free interactive feedback.
6. **A neutral colour for exactly-zero change**, and a `+`/`−` sign character
   next to every coloured figure that lacks one.
7. **Reduce Motion guards** on the chart's range-change animation and any glass
   morph — a one-line `.animation(reduceMotion ? nil : .snappy, value:)`.
8. **`.accessibilityAddTraits(.isSelected)`** on the active range pill, and
   `.accessibilityElement(children: .combine)` on the hero/delta pair.
9. **Write `.scrollEdgeEffectStyle(.soft, for: .top)` explicitly** wherever the
   soft fade is the intent, rather than leaving it `.automatic` — iOS 27 flips
   the default to `.hard`, so `.automatic` will silently change the app's
   appearance on OS upgrade.
10. **Switch to `@Environment(\.colorSchemeContrast)`-aware green/red and border
    colours.** Cheap, and one of the three APIs Apple's Inclusivity citation
    names.

### Real work

11. **Dynamic Type across the app (backlog 11).** Do it as one mechanical pass
    using the mapping table above, then a second pass fixing the layouts that
    break: `SettingsView`'s credential rows, all three `preferencesCard` toggles,
    `WelcomeView`, and the assets/debts and holdings rows in `OverviewView`.
    Introduce `@ScaledMetric` for icon frames and row heights. This is app-wide
    and touches every view file; sequence it *before* the Settings and Widgets
    redesigns so the new screens are built scaling from the start rather than
    retrofitted twice.
12. **Redesign Settings around a monogram identity header (backlog 9).**
    Centred monogram from `KuberaProfile.name` initials in a tinted circle,
    display name, `portfolio · currency` line, the two per-surface status lines
    moved into the header, and **Disconnect directly beneath them**. Then
    grouped `Card`s: Widget portfolio, Preferences, Growth history (the MCP
    token row and its status, currently buried in the account card), and Data &
    privacy text last. Shorten the masked-credential rows to a status glyph plus
    a short mask.
    *File:* `App/Views/SettingsView.swift`.
13. **Redesign the Widgets tab as a horizontal gallery (backlog 8).** One
    horizontally scrolling `ScrollView` per family with
    `.scrollTargetBehavior(.viewAligned)`, `.scrollTargetLayout()`, and a
    trailing peek so the affordance is visible. Widgets render at true point
    size with no `scaleEffect` — drop the `min(1, geo.size.width / size.width)`
    scaling in `WidgetsView.swift:159`, which currently misrepresents the
    medium widget's text size. Add the Lock Screen accessory families on a dark
    wallpaper-substitute plate. Keep "Add widgets" and "Update widget data now".
    *File:* `App/Views/WidgetsView.swift`.
14. **Chart accessibility.** An `AXChartDescriptorRepresentable` for the
    Overview chart, plus per-mark labels. This is the difference between the
    chart being usable and being invisible to VoiceOver.
15. **A light-mode green/red in `Theme`**, mirroring what `WidgetTheme` already
    does, with measured contrast ratios recorded in a comment so the next
    person does not "improve" them back.
16. **Stale-data disclosure.** An "as of HH:mm" line under the hero when the
    snapshot is older than some threshold, and the same on the widget previews.
    Currently the app shows a confident figure with no age.
17. **A `.tabViewBottomAccessory` net-worth readout** — a single line, current
    figure and today's delta, visible from the Widgets and Settings tabs. This
    is the iOS 26 flourish that best fits this app's content. Needs a compact
    variant for `.inline` placement.

### Needs a decision

18. **Do the widget options move back to the Widgets tab?** The backlog raises
    it. Recommendation: **no** — Privacy mode and Compact numbers affect the app
    too, not just widgets, so Settings is their honest home. But the Widgets tab
    should *link* to them ("These previews use your Settings" → deep link),
    which is cheap and resolves the discoverability complaint.
19. **How much type scale does the hero figure get?** A `.largeTitle` net worth
    at AX5 is enormous and will not fit "$1,240,000" on one line. Options:
    clamp the hero alone to `.xxxLarge`, switch to compact notation
    automatically at accessibility sizes, or allow two lines. Recommendation:
    auto-compact at accessibility sizes with the full number in
    `accessibilityValue` — it is the only option that neither lies nor breaks.
20. **Scrub delta baseline: range-start or today?** Stocks uses range-start.
    The app must pick one, label it, and be consistent between the hero delta,
    the widgets and the CAGR block. This is a correctness decision, not a
    visual one.
21. **Does `Card` become glass anywhere?** Recommendation: no, ever, for cards
    holding figures — but the `AddWidgetsSheet` and any future transient
    overlay are legitimately controls-layer and could be glass.
22. **Is the app's palette monochrome-plus-two by policy?** If so, write it
    down, because the allocation bar and composition breakdown will keep
    pressing for a categorical palette. Copilot Money's answer — an owned,
    contrast-checked category palette — is the alternative, and it is real work.

---

## Sources

- [Apple Design Awards — 2026 winners and finalists](https://developer.apple.com/design/awards/)
- [Apple Newsroom: 2026 Apple Design Award winners](https://www.apple.com/newsroom/2026/06/apple-reveals-winners-of-the-2026-apple-design-awards/)
- [Human Interface Guidelines: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Human Interface Guidelines: Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- [Human Interface Guidelines: Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [Human Interface Guidelines: Charting data](https://developer.apple.com/design/human-interface-guidelines/charting-data)
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [Landmarks: Building an app with Liquid Glass (sample code)](https://developer.apple.com/documentation/swiftui/landmarks-building-an-app-with-liquid-glass)
- [`GlassEffectContainer`](https://developer.apple.com/documentation/swiftui/glasseffectcontainer)
- [`ConcentricRectangle`](https://developer.apple.com/documentation/swiftui/concentricrectangle)
- [`tabViewBottomAccessory(content:)`](https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(content:))
- [`tabBarMinimizeBehavior(_:)`](https://developer.apple.com/documentation/swiftui/view/tabbarminimizebehavior(_:))
- [`backgroundExtensionEffect()`](https://developer.apple.com/documentation/swiftui/view/backgroundextensioneffect())
- [`scrollEdgeEffectStyle(_:for:)`](https://developer.apple.com/documentation/swiftui/view/scrolledgeeffectstyle(_:for:))
- [`contentTransition(_:)` / `.numericText`](https://developer.apple.com/documentation/swiftui/contenttransition/numerictext(value:))
- [`accessibilityChartDescriptor(_:)`](https://developer.apple.com/documentation/swiftui/view/accessibilitychartdescriptor(_:))
- [`AXChartDescriptor`](https://developer.apple.com/documentation/accessibility/axchartdescriptor)
- [`ScaledMetric`](https://developer.apple.com/documentation/swiftui/scaledmetric)
- [Apple Design Awards — 2024 winners and finalists](https://developer.apple.com/design/awards/2024/) (Copilot Money = Innovation finalist)
- [Liquid Glass Is Cracked, and Usability Suffers in iOS 26 — Nielsen Norman Group](https://www.nngroup.com/articles/liquid-glass/)
- ["Tinted" control in iOS 26.1 tones down Liquid Glass after backlash](https://gulfnews.com/technology/companies/apple-yields-tinted-control-in-ios-261-beta-4-tones-down-liquid-glass-after-backlash-1.500315176)
- [Apple's iOS 26 Liquid Glass: sleek, shiny, and questionably accessible — Infinum](https://infinum.com/blog/apples-ios-26-liquid-glass-sleek-shiny-and-questionably-accessible/)
- [Corner concentricity in SwiftUI on iOS 26 — Nil Coalescing](https://nilcoalescing.com/blog/ConcentricRectangleInSwiftUI/)
- [Exploring concentricity in SwiftUI — Create with Swift](https://www.createwithswift.com/exploring-concentricity-in-swiftui/)
- [Exploring tab bars on iOS 26 with Liquid Glass — Donny Wals](https://www.donnywals.com/exploring-tab-bars-on-ios-26-with-liquid-glass/)
- [Grouping Liquid Glass components using `glassEffectUnion` — Donny Wals](https://www.donnywals.com/grouping-liquid-glass-components-using-glasseffectunion-on-ios-26/)
- [`tabBarMinimizeBehavior` not triggering with `NavigationStack(path:)` — Apple Forums](https://developer.apple.com/forums/thread/799604)
- [Crash conditionally rendering `.tabViewBottomAccessory` with `TabView(selection:)` — Apple Forums](https://developer.apple.com/forums/thread/790913)
- [Supporting Increase Contrast in your app — Create with Swift](https://www.createwithswift.com/supporting-increase-contrast-in-your-app-to-enhance-accessibility/)
- [SwiftUI previews for accessibility testing — SwiftUISnippets](https://swiftuisnippets.wordpress.com/2026/04/18/swiftui-previews-your-accessibility-testing-powerhouse/)
- [iOS SwiftUI accessibility techniques: Increase Contrast — CVS Health](https://github.com/cvs-health/ios-swiftui-accessibility-techniques/blob/main/iOSswiftUIa11yTechniques/Documentation/IncreaseContrast.md)
- [Adopting Liquid Glass: experiences and pitfalls — JuniperPhoton](https://juniperphoton.substack.com/p/adopting-liquid-glass-experiences)
- [LiquidGlassReference (community API reference)](https://github.com/conorluddy/LiquidGlassReference)
