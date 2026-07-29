# Backlog

## 1. Rename the app to "Kubera Mobile"

Change the display name (`CFBundleDisplayName` in `project.yml`) and the
widget-gallery strings. Bundle identifiers can stay — renaming them would orphan
the Keychain access group and App Group on existing installs.

Note: leaning further into the "Kubera" name increases the trademark exposure
this unofficial project already carries (see the README disclaimer).

## 2. Face ID lock

Lock the app behind Face ID / Touch ID (`LocalAuthentication`, `LAContext`),
**enabled by default**, with a toggle in Settings to turn it off.

- Gate on app launch and on returning from background (with a short grace
  period so tab-switching apps isn't punishing).
- Fall back to device passcode when biometrics are unavailable.
- Store the toggle in `WidgetSettings`-style shared settings; widgets are
  unaffected (they already have privacy mode for masking amounts).
- Requires the `NSFaceIDUsageDescription` Info.plist key.

## 3. Restructure Settings and the Widgets tab

- Move the widget options (privacy mode, compact numbers) from the Widgets tab
  into Settings.
- The Widgets tab becomes purely a gallery of live previews.
- Add an "Add widgets" button in the Widgets tab.
  - Constraint: iOS has no public API to open the Home Screen widget gallery
    or the "edit widgets" UI from an app. Options to evaluate:
    `WidgetCenter` has no such hook; a How-To sheet with visuals is the
    reliable fallback; check whether newer SDKs added an invocation API
    (e.g. `WidgetCenter.shared` additions) before settling.
