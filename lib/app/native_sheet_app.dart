import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:native_widgets_on_duo/app/native_sheet_codec.dart';
import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/features/activity/models/activity_filter.dart';
import 'package:native_widgets_on_duo/features/activity/view/activity_filter_sheet.dart';
import 'package:native_widgets_on_duo/features/markets/view/market_filter_sheet.dart';
import 'package:native_widgets_on_duo/features/orders/models/order.dart';
import 'package:native_widgets_on_duo/features/orders/view/orders_filter_sheet.dart';
import 'package:native_widgets_on_duo/features/sign_in/view/sign_in_sheet.dart';
import 'package:native_widgets_on_duo/features/watchlist/models/watchlist_filter.dart';
import 'package:native_widgets_on_duo/features/watchlist/view/watchlist_filter_sheet.dart';

Future<void> runNativeSheetApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  final configuration = await AdaptiveNativeSheet.bootstrap(
    encodeResult: NativeSheetCodec.encode,
  );
  runApp(_NativeSheetApp(configuration: configuration));
}

/// A sheet gets a dedicated widget tree and draft, without installing the
/// page's native navigation host in its engine.
class _NativeSheetApp extends StatefulWidget {
  const _NativeSheetApp({required this.configuration});

  final Map<String, dynamic> configuration;

  @override
  State<_NativeSheetApp> createState() => _NativeSheetAppState();
}

class _NativeSheetAppState extends State<_NativeSheetApp> {
  final _notifiers = <ChangeNotifier>[];
  late final Widget _content;

  ValueNotifier<T> _own<T>(T value) {
    final notifier = ValueNotifier(value);
    _notifiers.add(notifier);
    return notifier;
  }

  @override
  void initState() {
    super.initState();
    final argument = widget.configuration['arguments'];
    _content = switch (widget.configuration['route']) {
      'watchlist' => _watchlist(argument as Object),
      'activity' => _activity(argument as Object),
      'date' => DateSheetContent(
        chosen: _own(NativeSheetCodec.date(argument!)),
      ),
      'orders' => OrdersFilterContent(
        draft: _own(NativeSheetCodec.orders(argument!)),
      ),
      'accounts' => _accounts(argument as Object),
      'markets' => MarketFilterContent(
        draft: _own(NativeSheetCodec.markets(argument!)),
      ),
      'signIn' => const SignInContent(),
      final route => throw ArgumentError.value(route, 'route', 'Unknown sheet'),
    };
  }

  Widget _watchlist(Object argument) {
    final current = NativeSheetCodec.watchlist(argument);
    return WatchlistFilterContent(
      draft: _own(current),
      more: _own(
        current.maxPrice < WatchlistFilter.ceiling || current.types.isNotEmpty,
      ),
    );
  }

  Widget _activity(Object argument) {
    final current = NativeSheetCodec.activity(argument);
    return ActivityFilterContent(
      draft: _own(current),
      more: _own(
        current.period != ActivityPeriod.all ||
            current.minAmount > 0 ||
            current.since != null,
      ),
    );
  }

  Widget _accounts(Object argument) {
    final initial = NativeSheetCodec.accounts(argument);
    return AccountsSheetContent(
      chosen: _own(initial.isEmpty ? Account.values.toSet() : initial),
    );
  }

  @override
  void dispose() {
    for (final notifier in _notifiers) {
      notifier.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const theme = AdaptiveThemeData(primaryColor: red, background: paper);
    final brightness = widget.configuration['brightness'] == 'dark'
        ? Brightness.dark
        : Brightness.light;
    final background = widget.configuration['backgroundColor'] as int?;
    final fits =
        widget.configuration['route'] != 'signIn' &&
        (widget.configuration['detents'] == null ||
            widget.configuration['detents'] == 'fit');
    return AdaptiveStyleScope(
      style: AdaptiveStyle.native,
      child: CupertinoApp(
        debugShowCheckedModeBanner: false,
        initialRoute: '/',
        theme: theme.cupertino(brightness),
        localizationsDelegates: const [DefaultMaterialLocalizations.delegate],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(platformBrightness: brightness),
          child: AdaptiveTheme(
            data: theme,
            child: Theme(data: theme.material(brightness), child: child!),
          ),
        ),
        home: AdaptiveNativeSheetContent(
          fits: fits,
          backgroundColor: background == null ? null : Color(background),
          child: _content,
        ),
      ),
    );
  }
}
