# Migrating to 2.0

## Icons are `AdaptiveIcon`

Every `dynamic icon` is now an `AdaptiveIcon`. Give the SF Symbol for iOS and the Material icon for everywhere else.

```dart
// 1.x
AdaptiveNavigationDestination(icon: 'house', selectedIcon: 'house.fill', label: 'Home')

// 2.0
AdaptiveNavigationDestination(
  icon: AdaptiveIcon(sfSymbol: 'house', icon: Icons.home_outlined),
  selectedIcon: AdaptiveIcon(sfSymbol: 'house.fill', icon: Icons.home),
  label: 'Home',
)
```

`AdaptiveIcon(image: AssetImage('...'))` and `AdaptiveIcon(widget: ...)` replace passing an `ImageProvider` or a widget. The same type is used by `AdaptivePopupMenuButton.icon`, `AdaptivePopupMenuItem.icon`, `AdaptiveContextMenuAction.icon` and `AdaptiveAlertDialog.show(icon:)`. `AdaptiveSegmentedControl(sfSymbols:)` is now `icons:`, a `List<AdaptiveIcon>`.

App bar actions and drawer items follow the same rule:

```dart
// 1.x
AdaptiveAppBarAction(iosSymbol: 'magnifyingglass', icon: Icons.search, onPressed: search)

// 2.0
AdaptiveAppBarAction(
  icon: AdaptiveIcon(sfSymbol: 'magnifyingglass', icon: Icons.search),
  onPressed: search,
)
```

`iconWidget:` becomes `icon: AdaptiveIcon(widget: ...)`.

## Pages need no inset workarounds

Remove `SafeArea` around page bodies and `MediaQuery.paddingOf(context).bottom` padding added for bars. `AdaptiveScaffold` places the body itself:

- a body that is a `ListView`, `GridView` or `CustomScrollView` runs under the glass bars on iOS 26+ and starts below them;
- any other body sits between the bars.

To keep content running under the bars for a body the scaffold cannot see into (a router shell, a `BlocBuilder`), set `extendBody: true` or `extendBodyBehindAppBar: true`.

The scaffold owns the page's scroll link. Remove `AdaptiveAppBar(scrollController:)` and replace `AdaptiveListView` with a plain `ListView`, also on pages that use `AdaptiveNavigationSearchBar`. Where the page needs the controller, read `PrimaryScrollController.of(context)` inside the body.

Large titles no longer need a controller:

```dart
// 1.x
final controller = AdaptiveNavigationScrollController();
AdaptiveScaffold(
  appBar: AdaptiveAppBar(title: 'Inbox', largeTitle: true, scrollController: controller),
  body: AdaptiveListView(controller: controller, children: rows),
)

// 2.0
AdaptiveScaffold(
  appBar: AdaptiveAppBar(title: 'Inbox', largeTitle: true),
  body: ListView(children: rows),
)
```

## Colours and bar style are set once

```dart
// 1.x: repeated on every AdaptiveAppBar, plus Material and Cupertino themes
AdaptiveAppBar(
  title: 'Portfolio',
  navigationBarColor: red,
  navigationBarShadow: true,
  hidesNavigationButtonBackground: true,
  tintColor: Colors.white,
)

// 2.0
AdaptiveApp(
  theme: AdaptiveThemeData(
    primaryColor: red,
    background: paper,
    barStyle: AdaptiveBarStyle.solid(red, foreground: Colors.white, shadow: true, plainButtons: true),
  ),
  home: ...,
)
AdaptiveAppBar(title: 'Portfolio')
```

An app bar can still override any of these. `materialLightTheme` and `cupertinoLightTheme` still win over the derived themes when passed. A `builder` that only installed a Material `Theme` on iOS, and the Material and Cupertino localisation delegates, can be removed.

## Drawers

```dart
final scaffoldKey = GlobalKey<AdaptiveScaffoldState>();

AdaptiveScaffold(
  key: scaffoldKey,
  drawer: AdaptiveDrawer(
    title: 'Accounts',
    sections: [
      [AdaptiveDrawerItem(id: 'all', title: 'All accounts', sfSymbol: 'square.grid.2x2', icon: Icons.grid_view)],
    ],
    selectedId: 'all',
    onSelected: (id) => ...,
  ),
  ...
)

scaffoldKey.currentState?.openDrawer();
```

On iOS this opens the native panel; elsewhere a Material drawer. Any other widget passed as `drawer` is a Material drawer everywhere, as before.

## Removed

| 1.x | 2.0 |
|---|---|
| `IOS26Button`, `IOS26Switch`, `IOS26Slider`, `IOS26SegmentedControl`, `IOS26AlertDialog`, `IOS26ContextMenu`, `IOS26NativeTabBar`, `IOS26NativeSearchTabBar` | the matching `Adaptive*` widget |
| `IOS26ScaffoldLegacy` | `AdaptiveScaffold` |
| `AdaptiveScaffold.enableBlur`, `enableToolbarGradient` | remove; they had no effect |
| `AdaptiveButton.useNative` | remove; iOS buttons are always native |
| `AdaptiveTextField.cupertinoDecoration`, `AdaptiveTextFormField.cupertinoDecoration` | remove; UIKit draws the field |
| `AdaptiveNavigationScrollController.compactUnderlapTop`, `AdaptiveLargeTitleSpacer` | remove |
| `PlatformInfo.isIOS26OrHigher()` for layout decisions | `AdaptiveCapabilities.liquidGlass` |
| `AdaptiveAppBar(useNativeToolbar: false)` | pass your own `cupertinoNavigationBar`; without one iOS always shows the native bar |
| `AdaptiveBottomNavigationBar(useNativeBottomBar: false)` | pass your own `cupertinoTabBar` |
| `AdaptiveScaffold.minimizeBehavior`, `TabBarMinimizeBehavior` | remove; it never took effect |
| `AdaptiveListView` | `ListView` |
| `AdaptiveAppBar.scrollController`, `AdaptiveNavigationScrollController` | `PrimaryScrollController.of(context)` in the body |
| `IOS26NativeSearchTabBar` | `AdaptiveBottomNavigationBar(search:)` |
| `PlatformTarget.ios` | `PlatformTarget.ios26Plus` or `PlatformTarget.ios18OrLower` |

## Choosing the family of controls

`AdaptiveApp(style: AdaptiveStyle.material)` runs Material on iOS too. `AdaptiveStyleScope(style: AdaptiveStyle.material, child: ...)` does the same for one subtree, which also suits widget tests.
