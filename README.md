# Meridian

Investment UI proof of concept with Flutter BLoC and a local copy of `adaptive_platform_ui` from `../adaptive2/packages/adaptive_platform_ui`.

- Native UIKit tabs: Liquid Glass on supported iOS versions, system-owned side placement on Duo.
- Requested custom red header stays visible while content scrolls.
- Accounts appear in a persistent side menu at widths of 620 points and above; compact screens use a drawer. The menu can be collapsed.
- Portfolio ranges, account filters, watchlist membership, and tab selection use `InvestmentBloc`.
- Detail, profile, statements, and preferences use full-screen push navigation with native back controls.
- All prices, holdings, activity, and statements are fictional. No network calls, real orders, or persistence; demo state resets when the app restarts.

Run with `flutter run`. iOS bundle ID: `com.peterleung.meridian`.

## Simulator review

Built and ran on iPhone 17 Pro (iOS 27.0) and iPhone Duo (iOS 27.1). Inspected initial and scrolled layouts, drawer/account selection, native tabs, asset details, watchlist changes, and native back navigation. The copied package now restores the window top safe area when native tabs host a custom header.

Duo review covered its active compact display with the native side tab rail. Expanded posture and live folding could not be verified: available simulator controls did not switch to the inner display or honor the orientation request. The persistent menu layout is implemented at 620+ points. No test suites were run.
