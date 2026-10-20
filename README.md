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
