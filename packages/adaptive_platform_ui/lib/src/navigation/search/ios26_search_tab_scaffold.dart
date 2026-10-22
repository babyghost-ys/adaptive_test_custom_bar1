import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../tab_bar/adaptive_bottom_navigation_bar.dart';
import '../chrome/toolbar_registry.dart';

/// UIKit owns native tabs and search above Flutter. This widget publishes
/// state and consumes measured insets through a noninteractive channel anchor.
class IOS26SearchTabScaffold extends StatefulWidget {
  const IOS26SearchTabScaffold({
    super.key,
    required this.bar,
    required this.builder,
    required this.hidden,
    this.releasesBottomInset,
    this.headerBackgroundColor,
    this.backgroundColor,
    this.headerHeight = 0,
  });

  final AdaptiveBottomNavigationBar bar;
  final WidgetBuilder builder;
  final bool hidden;

  /// Whether the page gives up the tab bar's bottom inset; defaults to
  /// [hidden]. A page covered by a pushed route keeps it: the page is off
  /// screen, and dropping the inset would shorten its scroll extent and clamp
  /// its position, so it jumps when Back reveals it.
  final bool? releasesBottomInset;
  final Color? headerBackgroundColor;
  final Color? backgroundColor;
  final double headerHeight;

  @override
  State<IOS26SearchTabScaffold> createState() => _SearchTabsState();
}

class _SearchTabsState extends State<IOS26SearchTabScaffold> {
  MethodChannel? _channel;
  double _bottomInset = 0;
  double _safeTop = 0;
  double? _safeLeft;
  double? _safeRight;
  double? _searchTopInset;
  double _scrollOffset = 0;

  bool _ready = false;

  Map<String, Object?> _configuration() => {
    'items': widget.bar.items!
        .map(
          (item) => {
            'title': item.label,
            'symbol': item.icon is String ? item.icon : null,
            'selectedSymbol': item.selectedIcon is String
                ? item.selectedIcon
                : null,
            'isSearch': item.isSearch,
            'badge':
                item.badgeText ??
                (item.badgeCount != null && item.badgeCount! > 0
                    ? '${item.badgeCount}'
                    : null),
          },
        )
        .toList(),
    'selectedIndex': widget.bar.selectedIndex,
    'placeholder': widget.bar.search?.placeholder ?? 'Search',
    'isDark': CupertinoTheme.brightnessOf(context) == Brightness.dark,
    'tint':
        (widget.bar.selectedItemColor ??
                CupertinoTheme.of(context).primaryColor)
            .toARGB32(),
    'hidden': widget.hidden,
    'pageColor': widget.backgroundColor?.toARGB32(),
    'transitionHeaderHeight': widget.headerHeight,
    'headerColor': widget.headerBackgroundColor?.toARGB32(),
    'headerHeight': (ModalRoute.of(context)?.isCurrent ?? true)
        ? widget.headerHeight
        : 0,
  };

  @override
  void didUpdateWidget(IOS26SearchTabScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    _channel?.invokeMethod<void>('configure', _configuration());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _channel?.invokeMethod<void>('configure', _configuration());
  }

  @override
  void dispose() {
    _channel?.invokeMethod<void>('dispose');
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _onNativeCall(MethodCall call) async {
    if (!mounted) return;
    switch (call.method) {
      case 'selected':
        final index = call.arguments as int;
        if (widget.bar.items![index].isSearch) {
          ToolbarRegistry.maybeOf(context)?.beginNativeSearchHandoff();
        }
        widget.bar.onTap?.call(index);
      case 'changed':
        widget.bar.search?.onChanged(call.arguments as String);
      case 'submitted':
        widget.bar.search?.onSubmitted?.call(call.arguments as String);
      case 'layout':
        final data = call.arguments as Map;
        final reported = (data['bottom'] as num).toDouble();
        // A covered page keeps the inset it had: UIKit reports the pushed
        // page's smaller one while the tab bar is hidden for it.
        final bottom = _ready && _covered ? _bottomInset : reported;
        final safeTop = (data['safeTop'] as num?)?.toDouble() ?? 0;
        final safeLeft = (data['safeLeft'] as num?)?.toDouble();
        final safeRight = (data['safeRight'] as num?)?.toDouble();
        // Reports for other tabs omit the search inset. Retain its last
        // measurement so the next search frame does not start at a different
        // origin while UIKit is still presenting the field and keyboard.
        final top = (data['top'] as num?)?.toDouble() ?? _searchTopInset;
        if (!bottom.isFinite || bottom < 0 || (top != null && !top.isFinite))
          return;
        if (_ready &&
            bottom == _bottomInset &&
            top == _searchTopInset &&
            safeTop == _safeTop &&
            safeLeft == _safeLeft &&
            safeRight == _safeRight)
          return;
        setState(() {
          _ready = true;
          _bottomInset = bottom;
          _safeTop = safeTop;
          _safeLeft = safeLeft;
          _safeRight = safeRight;
          _searchTopInset = top;
        });
    }
  }

  /// Behind a pushed page rather than with its tab bar hidden.
  bool get _covered =>
      widget.hidden && !(widget.releasesBottomInset ?? widget.hidden);

  bool get _searchSelected =>
      widget.bar.items![widget.bar.selectedIndex!].isSearch;

  /// The search page's scroll view: the outermost vertical one seen scrolling
  /// while the search tab is shown.
  BuildContext? _searchScrollable;

  /// UIKit collapses the search page's large title from this position. Other
  /// tabs, kept alive offstage, are ignored. The search page's own list keeps
  /// reporting while offstage: switching tabs changes the top inset, which
  /// can clamp its offset, and UIKit must already have that offset when it
  /// shows the page again or it keeps the collapsed title over a list at rest.
  bool _syncScroll(ScrollMetrics metrics, int depth, BuildContext? context) {
    if (depth != 0 || metrics.axis != Axis.vertical || context == null) {
      return false;
    }
    if (!identical(context, _searchScrollable)) {
      if (!_searchSelected ||
          !Visibility.of(context) ||
          !TickerMode.of(context)) {
        return false;
      }
      _searchScrollable = context;
    }
    final offset = metrics.pixels - metrics.minScrollExtent;
    if (!offset.isFinite || offset == _scrollOffset) return false;
    _scrollOffset = offset;
    _channel?.invokeMethod<void>('setScrollOffset', offset);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final metrics = MediaQuery.of(context);
    final isSearch = _searchSelected;
    final padding = metrics.padding.copyWith(
      left: _safeLeft ?? metrics.padding.left,
      right: _safeRight ?? metrics.padding.right,
      top: isSearch
          ? (_searchTopInset ?? metrics.padding.top)
          : math.max(metrics.padding.top, _safeTop),
      bottom: widget.releasesBottomInset ?? widget.hidden
          ? metrics.padding.bottom
          : math.max(metrics.padding.bottom, _bottomInset),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        MediaQuery(
          // UIKit owns keyboard positioning. Its current search-field frame
          // supplies the full bottom occlusion; never count the keyboard twice.
          data: metrics.copyWith(padding: padding, viewInsets: EdgeInsets.zero),
          child: Visibility(
            visible:
                widget.hidden ||
                (_ready && (!isSearch || _searchTopInset != null)),
            maintainState: true,
            maintainAnimation: true,
            maintainSize: true,
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (n) => _syncScroll(n.metrics, n.depth, n.context),
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: (n) =>
                    _syncScroll(n.metrics, n.depth, n.context),
                child: Builder(builder: widget.builder),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          width: 1,
          height: 1,
          child: IgnorePointer(
            child: UiKitView(
              viewType: 'adaptive_platform_ui/search_tabs',
              creationParams: _configuration(),
              creationParamsCodec: const StandardMessageCodec(),
              onPlatformViewCreated: (id) {
                _channel = MethodChannel('adaptive_platform_ui/search_tabs_$id')
                  ..setMethodCallHandler(_onNativeCall);
                _channel!.invokeMethod<void>('configure', _configuration());
                if (_scrollOffset != 0) {
                  _channel!.invokeMethod<void>(
                    'setScrollOffset',
                    _scrollOffset,
                  );
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}
