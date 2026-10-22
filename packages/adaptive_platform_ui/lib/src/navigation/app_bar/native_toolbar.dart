import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'adaptive_navigation_scroll_controller.dart';
import 'adaptive_app_bar_action.dart';

/// UIKit's measured bottom edge of the window's native navigation bar, in
/// window coordinates, reported by whichever page currently owns it. Null
/// until UIKit has laid the bar out.
final nativeNavigationBarBottom = ValueNotifier<double?>(null);

/// Native iOS 26 UINavigationBar widget using platform views
/// Implements Liquid Glass design with native blur effects
class NativeToolbar extends StatefulWidget {
  const NativeToolbar({
    super.key,
    this.title,
    this.scrollController,
    this.largeTitle = false,
    this.leading,
    this.leadingText,
    this.actions,
    this.onLeadingTap,
    this.onActionTap,
    this.titleWidget,
    this.tintColor,
    this.navigationBarColor,
    this.navigationBarShadow = false,
    this.titleStyle,
    this.hidesNavigationButtonBackground = false,
    this.height = 44.0,
    this.showNativeView = true,
    this.verticalNavigation = false,
    this.active = true,
    this.covered = false,
  });

  final String? title;
  final bool largeTitle;
  final AdaptiveNavigationScrollController? scrollController;
  final Widget? leading;
  final String? leadingText;
  final List<AdaptiveAppBarAction>? actions;
  final VoidCallback? onLeadingTap;
  final ValueChanged<int>? onActionTap;

  /// Custom widget overlaid at the title position.
  /// When set, the native title is hidden and this widget is centered instead.
  final Widget? titleWidget;

  /// Tint color for bar button items (action buttons and back button)
  ///
  /// When set, this color is applied to the UINavigationBar's tintColor,
  /// which colors all UIBarButtonItem instances.
  /// If null, the system default tint color is used.
  final Color? tintColor;

  /// Opaque native navigation background, including its scroll-edge appearance.
  final Color? navigationBarColor;

  /// Subtle native shadow below a [navigationBarColor] bar.
  final bool navigationBarShadow;

  /// Font of the native title. Applied to the bar's appearance, so the system
  /// still draws and collapses the title.
  final TextStyle? titleStyle;

  /// Removes the shared glass background from native navigation buttons.
  final bool hidesNavigationButtonBackground;

  final double height;
  final bool showNativeView;

  /// Whether this page owns the window's native navigation bar.
  /// Set false for retained routes and inactive tabs.
  final bool active;

  /// Whether a sheet, dialog or popup covers the page. The native bar stays
  /// on screen with dimmed tint and ignores touches, as UIKit does behind a
  /// presented sheet.
  final bool covered;

  /// Let UIKit place navigation actions in the system vertical bar on Duo.
  /// Uses a full-window, touch-transparent native controller.
  final bool verticalNavigation;

  @override
  State<NativeToolbar> createState() => _NativeToolbarState();
}

class _NativeToolbarState extends State<NativeToolbar> {
  MethodChannel? _channel;
  int _channelGeneration = 0;
  int _propertyRevision = 0;
  final Map<String, int> _propertyRevisions = {};
  int _scrollGeneration = 0;
  bool? _lastActive;
  bool? _lastCovered;
  bool? _lastIsDark;
  int? _lastTint;
  int? _lastNavigationBarColor;
  bool? _lastNavigationBarShadow;
  bool? _lastHidesNavigationButtonBackground;
  List<AdaptiveAppBarAction>? _lastActions;

  bool get _isDark => CupertinoTheme.of(context).brightness == Brightness.dark;

  int _colorToARGB(Color color) {
    // Resolve CupertinoDynamicColor if needed
    Color resolvedColor = color;
    if (color is CupertinoDynamicColor) {
      final brightness = MediaQuery.platformBrightnessOf(context);
      resolvedColor = brightness == Brightness.dark
          ? color.darkColor
          : color.color;
    }

    return ((resolvedColor.a * 255.0).round() & 0xff) << 24 |
        ((resolvedColor.r * 255.0).round() & 0xff) << 16 |
        ((resolvedColor.g * 255.0).round() & 0xff) << 8 |
        ((resolvedColor.b * 255.0).round() & 0xff);
  }

  @override
  void initState() {
    super.initState();
    widget.scrollController?.addListener(_syncScroll);
  }

  void _syncScroll() {
    final controller = widget.scrollController;
    if (controller == null || controller.activePosition == null) return;
    _channel?.invokeMethod<void>('setScrollOffset', {
      'offset': controller.activeOffset,
      'generation': _scrollGeneration,
    });
  }

  @override
  void dispose() {
    widget.scrollController?.removeListener(_syncScroll);
    final channel = _channel;
    _channel = null;
    _channelGeneration++;
    if (channel != null) {
      _sendPropertySnapshot(
        channel,
        _channelGeneration,
        'active',
        ++_propertyRevision,
        'setActive',
        {'active': false},
        () {},
      );
      channel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPropsToNativeIfNeeded();
    // Render the title now, not after the page's first frame, so a heavy
    // page does not hold it back.
    if (!_titleStarted && widget.titleWidget != null) {
      _titleStarted = true;
      _renderTitleImage();
    }
  }

  @override
  void didUpdateWidget(NativeToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      _scrollGeneration++;
      oldWidget.scrollController?.removeListener(_syncScroll);
      widget.scrollController?.addListener(_syncScroll);
      _syncNavigationPage();
      final generation = _scrollGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _scrollGeneration) _syncNavigationPage();
      });
    }
    _syncPropsToNativeIfNeeded();

    if (widget.title != oldWidget.title) {
      final ch = _channel;
      // Skip when a titleWidget overlay is shown — the native title stays hidden
      if (ch != null && widget.title != null && widget.titleWidget == null) {
        ch.invokeMethod('updateTitle', {'title': widget.title!});
      }
    }
  }

  Map<String, Object?>? _lastTitleStyle;

  Map<String, Object?>? get _titleStyleMap {
    final style = widget.titleStyle;
    if (style == null) return null;
    return {
      'fontFamily': style.fontFamily,
      'fontSize': style.fontSize,
      'fontWeight': style.fontWeight?.value,
    };
  }

  Uint8List? _titleBytes;
  (Uint8List, double)? _renderedTitle;
  bool _titleImageScheduled = false;
  bool _titleStarted = false;

  /// Renders [NativeToolbar.titleWidget] and sets it as the native bar's
  /// title view, so it is drawn inside the bar, centred by UIKit, over the
  /// bar's own background. Re-sent only when the rendered pixels change.
  void _scheduleTitleImage() {
    if (_titleImageScheduled) return;
    _titleImageScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _titleImageScheduled = false;
      _renderTitleImage();
    });
  }

  Future<void> _renderTitleImage() async {
    {
      if (!mounted) return;
      final title = widget.titleWidget;
      if (title == null) {
        _renderedTitle = null;
        if (_titleBytes == null) return;
        _titleBytes = null;
        _channel?.invokeMethod<void>('setTitleImage', {'bytes': null});
        return;
      }
      final view = View.of(context);
      final ratio = view.devicePixelRatio;
      final image = await _renderOffscreen(
        InheritedTheme.captureAll(
          context,
          Directionality(
            textDirection: Directionality.of(context),
            child: MediaQuery(
              data: MediaQuery.of(context),
              // Room for descenders a font draws below its line box.
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                child: title,
              ),
            ),
          ),
        ),
        view,
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (!mounted || data == null) return;
      _renderedTitle = (data.buffer.asUint8List(), ratio);
      _sendTitleImage();
    }
  }

  /// Sends the rendered title once the native bar exists; rendering starts
  /// with the widget so the image is usually ready when the bar is.
  void _sendTitleImage() {
    final channel = _channel;
    final rendered = _renderedTitle;
    if (channel == null || rendered == null) return;
    final (bytes, ratio) = rendered;
    if (listEquals(bytes, _titleBytes)) return;
    _titleBytes = bytes;
    channel.invokeMethod<void>('setTitleImage', {
      'bytes': bytes,
      'scale': ratio,
    });
  }

  /// Paints [widget] in a render tree of its own. The page's tree cannot be
  /// captured instead: a route fading in does not paint until it is visible.
  static Future<ui.Image> _renderOffscreen(Widget widget, ui.FlutterView view) {
    final boundary = RenderRepaintBoundary();
    final renderView = RenderView(
      view: view,
      configuration: ViewConfiguration(
        logicalConstraints: const BoxConstraints(
          maxWidth: 1000,
          maxHeight: 200,
        ),
        devicePixelRatio: view.devicePixelRatio,
      ),
      child: RenderPositionedBox(child: boundary),
    );
    final pipeline = PipelineOwner()..rootNode = renderView;
    renderView.prepareInitialFrame();
    final owner = BuildOwner(focusManager: FocusManager());
    final root = RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: widget,
    ).attachToRenderTree(owner);
    owner.buildScope(root);
    owner.finalizeTree();
    pipeline
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();
    return boundary.toImage(pixelRatio: view.devicePixelRatio).whenComplete(() {
      RenderObjectToWidgetAdapter<RenderBox>(
        container: boundary,
      ).attachToRenderTree(owner, root);
      owner.buildScope(root);
      owner.finalizeTree();
      pipeline.rootNode = null;
      renderView.dispose();
    });
  }

  void _syncNavigationPage() {
    final controller = widget.scrollController;
    if (controller == null) return;
    _channel?.invokeMethod<void>('setNavigationPage', {
      'title': widget.titleWidget == null ? (widget.title ?? '') : '',
      'offset': controller.activeOffset,
      'generation': _scrollGeneration,
    });
  }

  Future<void> _syncPropsToNativeIfNeeded({bool force = false}) async {
    final channel = _channel;
    if (!mounted || channel == null) return;
    final generation = _channelGeneration;
    final revision = ++_propertyRevision;

    // Snapshot and record every requested value before yielding. A rapid
    // true -> false -> true ownership change must send both final intents,
    // even while an earlier platform reply is still pending.
    final active = widget.active && widget.showNativeView;
    final isDark = _isDark;
    final actions = widget.actions == null
        ? null
        : List<AdaptiveAppBarAction>.unmodifiable(widget.actions!);
    final tint = widget.tintColor != null
        ? _colorToARGB(widget.tintColor!)
        : null;
    final requests = <Future<void>>[];

    void send(
      String property,
      String method,
      Map<String, dynamic> arguments,
      VoidCallback restore,
    ) {
      _propertyRevisions[property] = revision;
      requests.add(
        _sendPropertySnapshot(
          channel,
          generation,
          property,
          revision,
          method,
          arguments,
          restore,
        ),
      );
    }

    if (force || _lastActive != active) {
      final previous = _lastActive;
      _lastActive = active;
      send('active', 'setActive', {
        'active': active,
      }, () => _lastActive = previous);
    }
    final covered = widget.covered;
    if (force || _lastCovered != covered) {
      final previous = _lastCovered;
      _lastCovered = covered;
      send('covered', 'setCovered', {
        'covered': covered,
      }, () => _lastCovered = previous);
    }
    if (force || _lastIsDark != isDark) {
      final previous = _lastIsDark;
      _lastIsDark = isDark;
      send('brightness', 'setBrightness', {
        'isDark': isDark,
      }, () => _lastIsDark = previous);
    }
    if (force || !_actionsEqual(_lastActions, actions)) {
      final previous = _lastActions;
      _lastActions = actions;
      send('actions', 'updateActions', {
        if (actions != null && actions.isNotEmpty)
          'actions': actions.map((action) => action.toNativeMap()).toList(),
      }, () => _lastActions = previous);
    }
    if (force || _lastTint != tint) {
      final previous = _lastTint;
      _lastTint = tint;
      send('tint', 'setStyle', {'tint': tint}, () => _lastTint = previous);
    }

    final barColor = widget.navigationBarColor?.toARGB32();
    final barShadow = widget.navigationBarShadow;
    final titleStyle = _titleStyleMap;
    if (force ||
        _lastNavigationBarColor != barColor ||
        _lastNavigationBarShadow != barShadow ||
        !mapEquals(_lastTitleStyle, titleStyle)) {
      final previous = _lastNavigationBarColor;
      final previousShadow = _lastNavigationBarShadow;
      final previousTitleStyle = _lastTitleStyle;
      _lastNavigationBarColor = barColor;
      _lastNavigationBarShadow = barShadow;
      _lastTitleStyle = titleStyle;
      send(
        'navigationBarColor',
        'setNavigationBarColor',
        {
          'navigationBarColor': barColor,
          'navigationBarShadow': barShadow,
          'titleStyle': titleStyle,
        },
        () {
          _lastNavigationBarColor = previous;
          _lastNavigationBarShadow = previousShadow;
          _lastTitleStyle = previousTitleStyle;
        },
      );
    }

    if (force ||
        _lastHidesNavigationButtonBackground !=
            widget.hidesNavigationButtonBackground) {
      final previous = _lastHidesNavigationButtonBackground;
      _lastHidesNavigationButtonBackground =
          widget.hidesNavigationButtonBackground;
      send('buttonBackground', 'setButtonBackground', {
        'hidden': widget.hidesNavigationButtonBackground,
      }, () => _lastHidesNavigationButtonBackground = previous);
    }

    // MethodChannel preserves send order. Do not serialize new ownership
    // behind old replies or write acknowledged values back over newer intent.
    await Future.wait(requests);
  }

  Future<void> _sendPropertySnapshot(
    MethodChannel channel,
    int generation,
    String property,
    int revision,
    String method,
    Map<String, dynamic> arguments,
    VoidCallback restore,
  ) async {
    try {
      await channel.invokeMethod<void>(method, arguments);
    } catch (error) {
      if (error is! PlatformException && error is! MissingPluginException) {
        rethrow;
      }
      // Only the latest request for this property may invalidate its cache.
      // Replies from a removed/recreated anchor have no authority here.
      if (mounted &&
          identical(_channel, channel) &&
          generation == _channelGeneration &&
          _propertyRevisions[property] == revision) {
        restore();
      }
    }
  }

  bool _actionsEqual(
    List<AdaptiveAppBarAction>? a,
    List<AdaptiveAppBarAction>? b,
  ) {
    if (identical(a, b)) return true;
    a ??= const <AdaptiveAppBarAction>[];
    b ??= const <AdaptiveAppBarAction>[];
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return _buildFallbackToolbar();
    }

    final safePadding = MediaQuery.of(context).padding.top;
    if ((widget.titleWidget != null) || _titleBytes != null) {
      _scheduleTitleImage();
    }

    final creationParams = <String, dynamic>{
      // Hide native title when a titleWidget overlay is provided
      if (widget.title != null && widget.titleWidget == null)
        'title': widget.title!,
      if (widget.leading == null && widget.leadingText != null)
        'leading': widget.leadingText!,
      if (widget.actions != null && widget.actions!.isNotEmpty)
        'actions': widget.actions!.map((a) => a.toNativeMap()).toList(),
      'isDark': _isDark,
      'active': widget.active && widget.showNativeView,
      'covered': widget.covered,
      'largeTitle': widget.largeTitle,
      'verticalNavigation': widget.verticalNavigation,
      'scrollLinked': widget.scrollController != null,
      'scrollOffset': widget.scrollController?.activeOffset ?? 0.0,
      if (widget.tintColor != null) 'tint': _colorToARGB(widget.tintColor!),
      'navigationBarColor': widget.navigationBarColor?.toARGB32(),
      'navigationBarShadow': widget.navigationBarShadow,
      'titleStyle': _titleStyleMap,
      'hidesNavigationButtonBackground': widget.hidesNavigationButtonBackground,
    };

    return SizedBox(
      height: widget.verticalNavigation
          ? MediaQuery.sizeOf(context).height
          : widget.scrollController == null
          ? widget.height + safePadding
          : (widget.scrollController!.navigationBarBottom.value ??
                MediaQuery.sizeOf(context).height),
      child: Stack(
        children: [
          // UIKit hosts the real bar above Flutter's rendering surface. This
          // tiny, noninteractive view only anchors its channel to the window.
          if (widget.showNativeView)
            Positioned(
              left: 0,
              top: 0,
              width: 1,
              height: 1,
              child: IgnorePointer(
                child: UiKitView(
                  key: ValueKey((
                    widget.scrollController != null,
                    widget.largeTitle,
                    widget.verticalNavigation,
                  )),
                  viewType: 'adaptive_platform_ui/ios26_toolbar',
                  creationParams: creationParams,
                  creationParamsCodec: const StandardMessageCodec(),
                  onPlatformViewCreated: _onPlatformViewCreated,
                  hitTestBehavior: PlatformViewHitTestBehavior.transparent,
                ),
              ),
            ),
          if (widget.leading != null)
            Positioned(
              left: 16,
              top: safePadding + 3,
              child: Align(
                alignment: Alignment.centerLeft,
                child: widget.leading!,
              ),
            ),
        ],
      ),
    );
  }

  void _onPlatformViewCreated(int id) {
    _channel?.setMethodCallHandler(null);
    final generation = ++_channelGeneration;
    final channel = MethodChannel('adaptive_platform_ui/ios26_toolbar_$id');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (!mounted ||
          generation != _channelGeneration ||
          !identical(_channel, channel)) {
        return null;
      }
      return _handleMethodCall(call);
    });
    if (widget.scrollController != null) {
      _syncNavigationPage();
    }
    _titleBytes = null;
    if (widget.titleWidget != null) {
      _renderedTitle == null ? _scheduleTitleImage() : _sendTitleImage();
    }
    _syncScroll();
    // Creation parameters may precede a route/focus update. Reconcile the
    // mounted anchor with the latest widget, including null/empty properties.
    _syncPropsToNativeIfNeeded(force: true);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onNavigationMetrics':
        final args = call.arguments as Map?;
        final inset = (args?['contentInset'] as num?)?.toDouble();
        final bottom = (args?['barBottom'] as num?)?.toDouble();
        if (mounted &&
            args?['generation'] == _scrollGeneration &&
            inset != null &&
            bottom != null &&
            inset.isFinite &&
            bottom.isFinite &&
            inset > 0 &&
            bottom > 0) {
          nativeNavigationBarBottom.value = bottom;
          final controller = widget.scrollController;
          controller?.contentTopInset.value = inset;
          controller?.navigationBarBottom.value = bottom;
          setState(() {});
        }
        break;
      case 'onLeadingTapped':
        widget.onLeadingTap?.call();
        break;
      case 'onMenuItemTapped':
        if (call.arguments is Map) {
          final args = call.arguments as Map;
          final actionIndex = args['action'] as int?;
          final itemIndex = args['item'] as int?;
          final actions = widget.actions;
          if (actions != null &&
              actionIndex != null &&
              itemIndex != null &&
              actionIndex >= 0 &&
              actionIndex < actions.length) {
            actions[actionIndex].selectMenuItem(itemIndex);
          }
        }
        break;
      case 'onActionTapped':
        if (call.arguments is Map) {
          final index = (call.arguments as Map)['index'] as int?;
          if (index != null) widget.onActionTap?.call(index);
        }
        break;
    }
  }

  Widget _buildFallbackToolbar() {
    return CupertinoNavigationBar(
      middle:
          widget.titleWidget ??
          (widget.title != null ? Text(widget.title!) : null),
      leading: widget.leading,
      trailing: widget.actions != null && widget.actions!.isNotEmpty
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: widget.actions!.map((action) {
                return Builder(
                  builder: (context) => CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => action.press(context),
                    child: action.wrapWithBadge(
                      action.title != null || action.icon == null
                          ? Text(action.title ?? '')
                          : action.icon!.build(),
                    ),
                  ),
                );
              }).toList(),
            )
          : null,
    );
  }
}
