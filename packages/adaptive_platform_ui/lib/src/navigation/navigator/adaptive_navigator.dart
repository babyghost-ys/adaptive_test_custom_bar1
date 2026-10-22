import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/platform_info.dart';
import '../chrome/toolbar_registry.dart';
import '../search/adaptive_navigation_search_bar.dart';

/// Pushes full-screen pages using the platform's navigation implementation.
///
/// On iOS, use this with `AdaptiveToolbarHost` and `AdaptiveScaffold`. UIKit's
/// navigation controller owns the push, Back button and interactive back swipe;
/// Flutter keeps the page's widget state and completes its navigation result.
/// Other platforms use [MaterialPageRoute].
abstract final class AdaptiveNavigator {
  /// Pushes [builder] and returns the value supplied to [Navigator.pop].
  ///
  /// A cancelled UIKit back swipe leaves the Flutter route and its state intact.
  /// Standard [Navigator.pop], `maybePop` and `popUntil` remain supported for
  /// pages pushed through this method. Use this method for every pushed page in
  /// a native iOS stack; mixing arbitrary Flutter page routes into that stack
  /// cannot provide a UIKit-owned transition for those routes.
  static Future<T?> push<T extends Object?>(
    BuildContext context,
    WidgetBuilder builder, {
    RouteSettings? settings,
  }) async {
    final navigator = Navigator.of(context);
    if (!PlatformInfo.isIOS) {
      return navigator.push<T>(
        MaterialPageRoute<T>(builder: builder, settings: settings),
      );
    }
    return _NativeNavigation.instance.push<T>(
      navigator,
      ModalRoute.of(context),
      ToolbarRegistry.maybeOf(context),
      builder,
      settings,
    );
  }
}

/// A full-screen page for declarative routing, such as a go_router
/// `GoRoute.pageBuilder` or `Navigator.pages`.
///
/// On iOS it is the declarative form of [AdaptiveNavigator.push]: UIKit's
/// navigation controller owns the push, Back button and interactive back
/// swipe, and popping the route (`context.pop()`, `Navigator.pop`) pops the
/// native page. Other platforms use a [MaterialPageRoute]-style transition.
///
/// ```dart
/// GoRoute(
///   path: '/details',
///   pageBuilder: (context, state) =>
///       AdaptivePage(key: state.pageKey, child: const DetailsPage()),
/// )
/// ```
class AdaptivePage<T> extends Page<T> {
  const AdaptivePage({
    required this.child,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  /// The page's content, usually an `AdaptiveScaffold`.
  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) {
    if (!PlatformInfo.isIOS) return _MaterialPageBasedRoute<T>(page: this);
    return _NativePageRoute<T>.page(
      page: this,
      navigation: _NativeNavigation.instance,
      toolbarRegistry: ToolbarRegistry.maybeOf(context),
    );
  }
}

final class _MaterialPageBasedRoute<T> extends PageRoute<T>
    with MaterialRouteTransitionMixin<T> {
  _MaterialPageBasedRoute({required AdaptivePage<T> page})
    : super(settings: page);

  AdaptivePage<T> get _page => settings as AdaptivePage<T>;

  @override
  Widget buildContent(BuildContext context) => _page.child;

  @override
  bool get maintainState => true;

  @override
  String get debugLabel => '${super.debugLabel}(${_page.name})';
}

// Internal toolbar coordination. The package entry point exports only
// AdaptiveNavigator from this file, so this does not add a public component API.
bool ownsNativePageTransition(Route<dynamic>? route) =>
    route is _NativePageRoute<dynamic>;

/// Whether a native page has been pushed above [route]. The pushed page has
/// no Flutter transition, so [route] cannot tell it from a popup by its
/// secondary animation.
bool hasNativePageAbove(Route<dynamic>? route) {
  if (route == null) return false;
  final stack = route is _NativePageRoute<dynamic>
      ? route.stack
      : _NativeNavigation.instance._rootStacks[route];
  if (stack == null || stack.routes.isEmpty) return false;
  return !identical(stack.routes.last, route);
}

final class _NativeStack {
  _NativeStack(
    this.navigator,
    this.rootId,
    this.rootRoute,
    this.toolbarRegistry,
  );

  final NavigatorState navigator;
  final String rootId;
  ModalRoute<dynamic>? rootRoute;
  final ToolbarRegistry? toolbarRegistry;
  final routes = <_NativePageRoute<dynamic>>[];
  int revision = 0;
  bool preparing = false;
  Future<void>? nativePush;

  /// Declarative pages prepare UIKit one at a time, in stack order.
  Future<void>? pagePreparation;

  String parentIdOf(_NativePageRoute<dynamic> route) {
    final index = routes.indexOf(route);
    return index <= 0 ? rootId : routes[index - 1].id;
  }

  List<String> get routeIds => [rootId, for (final route in routes) route.id];
  String get topId => routes.isEmpty ? rootId : routes.last.id;
  String? get parentId => routes.isEmpty
      ? null
      : routes.length == 1
      ? rootId
      : routes[routes.length - 2].id;
}

/// Synchronizes Flutter's widget stack with the native content-controller stack.
/// No recognizer or animation here imitates a UIKit transition.
final class _NativeNavigation {
  _NativeNavigation() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static final instance = _NativeNavigation();
  static const _channel = MethodChannel('adaptive_platform_ui/navigation');
  final _stacks = Expando<_NativeStack>();
  final _rootStacks = Expando<_NativeStack>();
  final _routes = <String, _NativePageRoute<dynamic>>{};
  final _nativePops = <String>{};
  int _nextId = 0;

  Future<T?> push<T extends Object?>(
    NavigatorState navigator,
    ModalRoute<dynamic>? parentRoute,
    ToolbarRegistry? toolbarRegistry,
    WidgetBuilder builder,
    RouteSettings? settings,
  ) async {
    final stack = _stacks[navigator] ??= _NativeStack(
      navigator,
      'native_root_${++_nextId}',
      parentRoute,
      toolbarRegistry,
    );
    if (parentRoute != null && stack.rootRoute == parentRoute) {
      _rootStacks[parentRoute] = stack;
    }
    // Ignore a repeated tap while UIKit is preparing its source page. A push
    // cannot be queued behind the first route's result: that completes on pop.
    if (stack.preparing) return null;
    stack.preparing = true;
    final id = 'native_route_${++_nextId}';
    final parentId = stack.topId;
    late final _NativePageRoute<T> route;
    try {
      final prepared = await _channel.invokeMethod<bool>('preparePush', {
        'routeId': id,
        'parentRouteId': parentId,
      });
      if (prepared != true) return null;
      if (!navigator.mounted) {
        await _channel.invokeMethod<void>('syncStack', {
          'routeIds': stack.routeIds,
        });
        return null;
      }
      route = _NativePageRoute<T>(
        builder: builder,
        settings: settings,
        id: id,
        stack: stack,
        navigation: this,
      );
      stack.routes.add(route);
      _routes[id] = route;
    } finally {
      stack.preparing = false;
    }
    // The result stays pending for this page's lifetime; release preparation
    // before awaiting it, so a detail can push its own next page.
    return navigator.push<T>(route);
  }

  /// Registers a declarative page with its navigator's native stack. The
  /// Navigator has already added the route, so unlike [push] it cannot wait
  /// for UIKit before Flutter builds it: the route stays empty and
  /// translucent (the previous page keeps showing) until UIKit has prepared.
  void installPage(_NativePageRoute<dynamic> route, NavigatorState navigator) {
    final stack = _stacks[navigator] ??= _NativeStack(
      navigator,
      'native_root_${++_nextId}',
      null,
      route.toolbarRegistry,
    );
    route.stack = stack;
    route.id = 'native_route_${++_nextId}';
    stack.routes.add(route);
    _routes[route.id] = route;
  }

  /// Called from didPush/didAdd. The first preparation is sent synchronously,
  /// before the previous page rebuilds and gives up the native bar.
  void preparePage(_NativePageRoute<dynamic> route) {
    final stack = route.stack;
    final operation = _preparePage(route, stack.pagePreparation);
    stack.pagePreparation = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(stack.pagePreparation, operation)) {
          stack.pagePreparation = null;
        }
      }),
    );
  }

  Future<void> _preparePage(
    _NativePageRoute<dynamic> route,
    Future<void>? previous,
  ) async {
    final stack = route.stack;
    if (previous != null || stack.nativePush != null) {
      await previous;
      await stack.nativePush;
    }
    // UIKit refuses while another push or pop is still settling.
    for (var attempt = 0; attempt < 30; attempt++) {
      if (!route.isActive || !stack.navigator.mounted) return;
      final prepared = await _channel.invokeMethod<bool>('preparePush', {
        'routeId': route.id,
        'parentRouteId': stack.parentIdOf(route),
      });
      if (prepared == true) break;
      await SchedulerBinding.instance.endOfFrame;
    }
    if (!route.isActive) return;
    route.reveal();
    shown(route);
    await stack.nativePush;
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'didPop') return;
    final arguments = call.arguments;
    final id = arguments is Map ? arguments['routeId'] : null;
    final route = _routes[id];
    if (route == null || !route.isCurrent || !route.stack.navigator.mounted) {
      return;
    }
    // UIKit sends this only after an interactive transition commits. In
    // particular it sends nothing when the user reverses/cancels their swipe.
    final stack = route.stack;
    final targetId = arguments is Map ? arguments['targetRouteId'] : null;
    final target = _routes[targetId];
    final targetIndex = targetId == stack.rootId
        ? -1
        : target != null && target.stack == stack
        ? stack.routes.indexOf(target)
        : null;
    if (targetIndex == null) {
      _nativePops.add(route.id);
      stack.navigator.pop();
      _nativePops.remove(route.id);
      return;
    }
    // UIKit's Back history menu can pop several pages at once. Match its
    // selected controller rather than assuming that every native pop is one
    // level deep.
    final poppedIds = [
      for (final popped in stack.routes.skip(targetIndex + 1)) popped.id,
    ];
    _nativePops.addAll(poppedIds);
    try {
      stack.navigator.popUntil(
        (candidate) => targetIndex == -1
            ? stack.rootRoute == null
                  ? candidate.isFirst
                  : identical(candidate, stack.rootRoute)
            : identical(candidate, target),
      );
    } finally {
      _nativePops.removeAll(poppedIds);
    }
  }

  void shown(_NativePageRoute<dynamic> route) {
    final operation = _showAfterFrame(route);
    route.stack.nativePush = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(route.stack.nativePush, operation)) {
          route.stack.nativePush = null;
        }
      }),
    );
  }

  Future<void> _showAfterFrame(_NativePageRoute<dynamic> route) async {
    await _renderedPage();
    if (!route.isActive || !route.isCurrent) return;
    await _channel.invokeMethod<void>('routeShown', {
      'routeId': route.id,
      'parentRouteId': route.stack.parentIdOf(route),
      'expectsNativePage': _expectsNativePage(route),
    });
    popPermissionChanged(route);
  }

  void popPermissionChanged(_NativePageRoute<dynamic> route) {
    if (!route.isActive) return;
    final enabled = route.nativePopAllowed;
    if (route.nativePopEnabled == enabled) return;
    route.nativePopEnabled = enabled;
    unawaited(
      _channel.invokeMethod<void>('setPopEnabled', {
        'routeId': route.id,
        'enabled': enabled,
      }),
    );
  }

  void willPop(_NativePageRoute<dynamic> route) {
    if (_nativePops.contains(route.id)) return;
    // Queue the outgoing native content snapshot before Navigator schedules
    // the previous Flutter page's frame. Native UIKit animation starts after
    // that target page has rendered, via syncStack below.
    unawaited(_channel.invokeMethod<void>('preparePop', {'routeId': route.id}));
  }

  void popped(_NativePageRoute<dynamic> route) {
    _routes.remove(route.id);
    route.stack.routes.remove(route);
    _synchronizeAfterFrame(route.stack);
  }

  void disposed(_NativePageRoute<dynamic> route) {
    // Covers an explicit Navigator.removeRoute as well as ordinary pops.
    if (_routes.remove(route.id) == null) return;
    route.stack.routes.remove(route);
    _synchronizeAfterFrame(route.stack);
  }

  void _synchronizeAfterFrame(_NativeStack stack) {
    final revision = ++stack.revision;
    unawaited(_synchronize(stack, revision));
  }

  Future<void> _synchronize(_NativeStack stack, int revision) async {
    await _renderedPage();
    if (!stack.navigator.mounted || stack.revision != revision) return;
    // Flutter may pop a page while UIKit is still pushing its controller.
    // routeShown completes at native didShow, so serialize the final pop
    // behind that transition rather than asking UIKit to mutate a busy stack.
    // A page popped before routeShown skips its native push and resolves this
    // operation immediately, allowing syncStack to cancel its preparation.
    await stack.nativePush;
    if (!stack.navigator.mounted || stack.revision != revision) return;
    final topId = stack.topId;
    // popUntil may remove several Flutter routes in one call. Publish only
    // the final stack, and let UINavigationController pop to that controller.
    // Native completes this method after its transition finishes.
    await _channel.invokeMethod<void>('syncStack', {
      'routeIds': stack.routeIds,
    });
    // Native pop completion reattaches Flutter to the target controller. Its
    // final safe areas and bar metrics can change at that point; render them
    // before removing UIKit's retained target-content cover.
    await _renderedPage();
    if (!stack.navigator.mounted || stack.revision != revision) return;
    await _channel.invokeMethod<void>('routeShown', {
      'routeId': topId,
      'parentRouteId': stack.parentId,
      'expectsNativePage':
          stack.routes.isNotEmpty && _expectsNativePage(stack.routes.last),
    });
  }

  bool _expectsNativePage(_NativePageRoute<dynamic> route) {
    final registry = route.stack.toolbarRegistry;
    if (registry == null) return false;
    for (final entry in registry.entries.reversed) {
      if (!identical(entry.route, route) || !entry.shownInPlace) continue;
      final appBar = entry.appBar;
      return appBar != null &&
          (appBar.useNativeToolbar ||
              appBar.cupertinoNavigationBar is AdaptiveNavigationSearchBar);
    }
    return false;
  }

  Future<void> _renderedPage() async {
    // Scaffold registration publishes native bar content after the first
    // frame. Wait for the next frame too so content and native items agree.
    final scheduler = SchedulerBinding.instance;
    await scheduler.endOfFrame;
    await scheduler.endOfFrame;
  }
}

final class _NativePageRoute<T> extends PageRoute<T> {
  _NativePageRoute({
    required WidgetBuilder this.builder,
    required this.id,
    required this.stack,
    required this.navigation,
    super.settings,
  }) : toolbarRegistry = stack.toolbarRegistry,
       _awaitingNative = false,
       super(allowSnapshotting: false);

  /// A page-based route; [AdaptivePage.child] supplies its content.
  _NativePageRoute.page({
    required AdaptivePage<T> page,
    required this.navigation,
    required this.toolbarRegistry,
  }) : builder = null,
       _awaitingNative = true,
       super(settings: page, allowSnapshotting: false);

  final WidgetBuilder? builder;
  late String id;
  late _NativeStack stack;
  final _NativeNavigation navigation;
  final ToolbarRegistry? toolbarRegistry;
  bool? nativePopEnabled;

  /// A page-based route waits for UIKit to prepare before showing content.
  bool _awaitingNative;

  bool get _pageBased => builder == null;

  void reveal() {
    if (!_awaitingNative) return;
    // TransitionRoute keeps the route's opacity on its first overlay entry.
    overlayEntries.first.opaque = true;
    _awaitingNative = false;
    // The modal scope caches the built page; this rebuilds it.
    changedExternalState();
  }

  @override
  bool get opaque => !_awaitingNative;

  @override
  void install() {
    if (_pageBased) navigation.installPage(this, navigator!);
    super.install();
  }

  @override
  void didChangePrevious(Route<dynamic>? previousRoute) {
    super.didChangePrevious(previousRoute);
    // The first declarative page learns its native root here: the route the
    // native stack returns to when this navigator pops all its pages.
    if (_pageBased &&
        stack.rootRoute == null &&
        previousRoute is ModalRoute<dynamic> &&
        previousRoute is! _NativePageRoute<dynamic>) {
      stack.rootRoute = previousRoute;
      navigation._rootStacks[previousRoute] = stack;
    }
  }

  @override
  void didAdd() {
    super.didAdd();
    if (_pageBased) navigation.preparePage(this);
  }

  bool get nativePopAllowed =>
      !willHandlePopInternally &&
      // Keep compatibility with applications still using WillPopScope.
      // ignore: deprecated_member_use
      !hasScopedWillPopCallback &&
      popDisposition != RoutePopDisposition.doNotPop;

  @override
  Duration get transitionDuration => Duration.zero;
  @override
  Duration get reverseTransitionDuration => Duration.zero;
  @override
  bool get popGestureEnabled => false;
  @override
  bool get maintainState => true;
  @override
  Color? get barrierColor => null;
  @override
  String? get barrierLabel => null;

  @override
  TickerFuture didPush() {
    final result = super.didPush();
    if (_pageBased) {
      navigation.preparePage(this);
    } else {
      navigation.shown(this);
    }
    return result;
  }

  @override
  void changedInternalState() {
    super.changedInternalState();
    navigation.popPermissionChanged(this);
  }

  @override
  bool didPop(T? result) {
    if (willHandlePopInternally) return super.didPop(result);
    navigation.willPop(this);
    final popped = super.didPop(result);
    if (popped) navigation.popped(this);
    return popped;
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => _awaitingNative
      ? const SizedBox.shrink()
      : builder?.call(context) ?? (settings as AdaptivePage<T>).child;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;

  @override
  void dispose() {
    navigation.disposed(this);
    super.dispose();
  }
}
