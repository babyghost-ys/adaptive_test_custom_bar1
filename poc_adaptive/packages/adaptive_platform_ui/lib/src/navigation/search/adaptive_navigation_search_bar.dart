import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/adaptive_theme.dart';
import '../app_bar/adaptive_navigation_scroll_controller.dart';

/// Own one per search page and dispose with the page.
class AdaptiveNavigationSearchController extends ValueNotifier<bool> {
  AdaptiveNavigationSearchController() : super(false);

  /// The page's scroll link to the native search header. `AdaptiveScaffold`
  /// offers it to the body, so a plain scroll view follows the header.
  /// Disposed with this search controller.
  final scrollController = AdaptiveNavigationScrollController();
  // Bootstrap only, so the platform view can mount before UIKit reports layout.
  double _navigationHeight = kMinInteractiveDimensionCupertino;
  double get navigationHeight => _navigationHeight;

  void _applyNativeLayout(
    double height,
    bool active,
    double bottom,
    double underlapTop,
  ) {
    if (!height.isFinite ||
        height <= 0 ||
        !bottom.isFinite ||
        bottom <= 0 ||
        !underlapTop.isFinite) {
      return;
    }
    scrollController.contentTopInset.value = bottom;
    scrollController.navigationBarBottom.value = bottom;
    final heightChanged = height != _navigationHeight;
    _navigationHeight = height;
    if (value != active) {
      value = active;
    } else if (heightChanged) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }
}

/// Native navigation search on iOS, including UIKit's focused search transition.
/// Supply as `AdaptiveAppBar.cupertinoNavigationBar`. A plain scroll view in
/// the scaffold's body scrolls beneath the native glass and starts below the
/// header's measured inset.
/// On Android, supply the same widget as AdaptiveAppBar.appBar. It uses a
/// Material AppBar, BackButton and SearchBar, with text retained across rebuilds.
class AdaptiveNavigationSearchBar extends StatefulWidget
    implements ObstructingPreferredSizeWidget {
  const AdaptiveNavigationSearchBar({
    super.key,
    required this.title,
    required this.controller,
    required this.onChanged,
    required this.onBack,
    this.placeholder = 'Search',
  });
  final AdaptiveNavigationSearchController controller;
  final String title;
  final String placeholder;
  final ValueChanged<String> onChanged;
  final VoidCallback onBack;
  @override
  Size get preferredSize => Size.fromHeight(
    defaultTargetPlatform == TargetPlatform.iOS
        ? controller.navigationHeight
        : kToolbarHeight + _materialSearchHeight,
  );
  @override
  bool shouldFullyObstruct(BuildContext context) => false;
  @override
  State<AdaptiveNavigationSearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<AdaptiveNavigationSearchBar> {
  final _textController = TextEditingController();
  MethodChannel? _channel;
  @override
  void initState() {
    super.initState();
    widget.controller.scrollController.addListener(_syncScroll);
  }

  void _syncScroll() {
    final scroll = widget.controller.scrollController;
    _channel?.invokeMethod<void>('scroll', {
      'offset': scroll.hasClients ? scroll.offset : scroll.initialScrollOffset,
    });
  }

  @override
  void dispose() {
    widget.controller.scrollController.removeListener(_syncScroll);
    _channel?.invokeMethod<void>('dismiss');
    _channel?.setMethodCallHandler(null);
    _textController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AdaptiveNavigationSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.scrollController.removeListener(_syncScroll);
      widget.controller.scrollController.addListener(_syncScroll);
      _syncScroll();
      _channel?.invokeMethod<void>('measure');
    }
    if (oldWidget.title != widget.title ||
        oldWidget.placeholder != widget.placeholder) {
      _channel?.invokeMethod<void>('configure', _configuration());
    }
  }

  Map<String, Object?> _configuration() {
    final theme = CupertinoTheme.of(context);
    final bar = AdaptiveTheme.of(context).barStyle;
    return {
      'title': widget.title,
      'placeholder': widget.placeholder,
      'isDark': theme.brightness == Brightness.dark,
      'active':
          TickerMode.valuesOf(context).enabled &&
          (ModalRoute.of(context)?.isCurrent ?? true),
      'tint':
          (bar.foreground ??
                  CupertinoDynamicColor.resolve(theme.primaryColor, context))
              .toARGB32(),
      'navigationBarColor': bar.color?.toARGB32(),
      'navigationBarShadow': bar.shadow,
      'hidesNavigationButtonBackground': bar.plainButtons,
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _channel?.invokeMethod<void>('configure', _configuration());
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      final bar = AdaptiveTheme.of(context).barStyle;
      return AppBar(
        backgroundColor: bar.color,
        foregroundColor: bar.foreground,
        title: Text(widget.title),
        leading: BackButton(onPressed: widget.onBack),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(_materialSearchHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchBar(
              controller: _textController,
              hintText: widget.placeholder,
              leading: const Icon(Icons.search),
              trailing: [
                if (_textController.text.isNotEmpty)
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).clearButtonTooltip,
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      setState(_textController.clear);
                      widget.onChanged('');
                    },
                  ),
              ],
              onChanged: (value) {
                setState(() {});
                widget.onChanged(value);
              },
              textInputAction: TextInputAction.search,
            ),
          ),
        ),
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: widget.controller,
      builder: (context, active, child) => SizedBox(
        height: top + widget.controller.navigationHeight,
        child: child,
      ),
      child: UiKitView(
        viewType: 'adaptive_platform_ui/navigation_search',
        creationParams: _configuration(),
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: {
          Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
        },
        onPlatformViewCreated: (id) {
          final channel = MethodChannel(
            'adaptive_platform_ui/navigation_search_$id',
          );
          _channel = channel;
          channel.setMethodCallHandler((call) async {
            if (!mounted) return;
            if (call.method == 'changed') {
              widget.onChanged(call.arguments as String? ?? '');
            }
            if (call.method == 'layout') {
              final layout = call.arguments as Map;
              widget.controller._applyNativeLayout(
                (layout['height'] as num).toDouble(),
                layout['active'] == true,
                (layout['bottom'] as num).toDouble(),
                (layout['underlapTop'] as num).toDouble(),
              );
            }
            if (call.method == 'back') widget.onBack();
          });
          channel.invokeMethod<void>('measure');
          _syncScroll();
        },
      ),
    );
  }
}

const _materialSearchHeight = 72.0;
