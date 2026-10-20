# Meridian

Investment UI proof of concept with Flutter BLoC and a local copy of `adaptive_platform_ui` from `../adaptive2/packages/adaptive_platform_ui`.

- Native UIKit tabs: Liquid Glass on supported iOS versions, system-owned side placement on Duo.
- Requested custom red header stays visible while content scrolls.
- Accounts open in a left overlay drawer on every screen size, capped at 320 points. The remaining content dims, and native tabs hide until the drawer closes.
- Portfolio ranges, account filters, watchlist membership, and tab selection use `InvestmentBloc`.
- Detail, profile, statements, and preferences use full-screen push navigation with native back controls.
- All prices, holdings, activity, and statements are fictional. No network calls, real orders, or persistence; demo state resets when the app restarts.

Run with `flutter run`. iOS bundle ID: `com.peterleung.meridian`.

## Simulator review

Built and ran on iPhone 17 Pro (iOS 27.0) and iPhone Duo (iOS 27.1). Inspected initial and scrolled layouts, drawer/account selection, native tabs, asset details, watchlist changes, and native back navigation. The copied package now restores the window top safe area when native tabs host a custom header.

Expanded Duo landscape was also inspected with the drawer open and Activity at initial and bottom scroll positions. The simulator input tool targets the inactive cover display in this posture, so Flutter debugger callbacks controlled the active inner display for this review. Activity and menu rows now have the required Material ancestor. No test suites were run.

## Folded Duo correction

The native tab host can already narrow Flutter's surface beside the Duo rail. Safe-area reporting now measures only the remaining inset inside that surface, avoiding a second right-hand reservation. Portfolio range controls divide available width instead of overflowing with fixed padding.

Rechecked all four tabs, drawer, scrolled holdings, and native detail/back navigation on folded Duo, plus the regular iPhone initial and scrolled portfolio. Installed the signed update on the physical iPhone. Expanded posture was not rechecked after this correction: the current MCP and supported simctl commands expose no fold-state switch. Earlier expanded screenshots predate this change.

## Continuous custom header

The requested red custom header now extends its background across the native Duo side lane. Native status and tab controls keep their system placement and interaction. The extension dims with the drawer and is removed on pushed routes. Range pills have a 64-point visual cap while retaining equal available touch areas.

Reviewed the expanded landscape Duo initial portfolio, bottom scroll position, drawer, Preferences push and return after this change. MCP still addresses the inactive cover in expanded mode, so debugger callbacks drove those interactions and simctl captured display 3. Also reviewed regular iPhone rendering. The final header change has not been rechecked in folded posture.

The regular iPhone header also fills the top safe area, with light status icons. Drawer status styling switches to dark over its light background. Reviewed initial and scrolled regular iPhone states plus the open drawer, and installed the update on the physical phone.
