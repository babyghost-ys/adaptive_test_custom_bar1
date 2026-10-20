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

## Native return transition

Before the first managed push, the native host now records whether the root navigation bar is hidden. UIKit applies that policy during the interactive return instead of briefly showing a native title over the custom header and waiting for Flutter's route update. Reviewed a recording of the native Back-button return on regular iPhone: the detail title exits before the red header is fully revealed. Simulator-injected swipes did not initiate a native pop, so interactive completion/cancellation remains unverified.

Follow-up from the user's Duo swipe recording: native bar configuration is now frozen between `willShow` and `didShow`, so Flutter page updates cannot re-show the departing bar during a pop. Returning to the custom-header root hides the native bar without a separate trailing animation; a cancelled interaction restores the source controller's bar policy. Inspected Duo Back-button video frames: no AAPL title overlaps the returning red header. Regular iPhone push/Back and returned safe-area layout were also inspected. Both simulator builds succeeded and the signed update was installed on the physical iPhone. Injected swipe input still did not initiate interactive navigation, so gesture completion/cancellation remains visually unverified.


The preceding transition changes did not address the app's actual route path: `openPage` was still pushing `CupertinoPageRoute`, so Flutter animated the content independently of UIKit's title and Back button. All app detail pushes now call `AdaptiveNavigator.push`, giving UIKit ownership of the content transition as well as its navigation bar. Previous Back-button checks did not establish interactive gesture correctness. Rebuilt and checked native push/Back on regular iPhone and folded Duo; simulator gesture injection still produces no interactive pop.

## Interactive handoff cleanup

The shared Flutter surface now transfers after the navigation transition coordinator completes and UIKit has had its cleanup turn, rather than directly inside `didShow`. No fixed-duration timer or private view manipulation is used. The plugin's bundled `axe` CLI with 2-pixel touch spacing successfully drives native gestures (earlier MCP gesture attempts did not). Inspected a recorded full-content swipe from VOO back to scrolled holdings on regular iPhone: rounded transition corners settle during the finishing animation, with no multi-second persistence observed. Also exercised short cancelled and completed swipes on folded Duo. Physical-device reproduction of the original duration remains unverified.

## White corner exposure

The earlier cleanup timing change did not solve the physical-phone report. LLDB inspection during a slow native swipe located the rounding on UIKit's transition cards, not the Flutter view or retained snapshot. Runtime logs then showed the custom-header root incorrectly had `hidesNativeNavigationBar == false`. Root policy now derives from its explicit custom-header configuration, and the public transition coordinator's container receives matching header/page backing colors. Native detail anchors also update their controller's bar policy for cancelled swipes. Reviewed the regular iPhone swipe recording: the returning header no longer exposes a white top-right wedge after the outgoing detail leaves. Rebuilt Duo and checked return/cancellation. No private UIKit views are modified.

Cancelled-swipe restoration is applied after the coordinator's completion, rather than at interaction-end (UIKit can still reverse visibility afterward). Final Duo cancellation screenshot confirms both AAPL title and native Back button restored.

The native scroll view's top edge effect is disabled when the page declares a solid custom header. This removes the pale wash and contrasting red strip seen during swipe-back. Reviewed NVIDIA-to-Markets swipe video on regular iPhone, plus Duo return. Native detail edge effects and tab materials remain system-controlled.
