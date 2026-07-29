# Backlog

## 1. Rename the app ✅ done

Shipped as **Kubera Mobile** (`CFBundleDisplayName` on both targets, plus the
in-app and widget-gallery strings). The name signals an unofficial client instead
of implying endorsement, which is the cheapest way to reduce the trademark
exposure this project carries — see the README disclaimer.

Bundle identifiers are `com.kubera.mobile` / `.widgets` / `.tests`. Because iOS
keys installs by bundle id, the first install under the new id arrives as a fresh
app: delete the old icon, and expect to re-enter credentials once. Growth history
re-downloads from Kubera's MCP endpoint, so only the credentials are a real
re-entry cost.

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
