import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'package:native_widgets_on_duo/app/router.dart';
import 'package:native_widgets_on_duo/app/theme/palette.dart';

class MeridianApp extends StatelessWidget {
  const MeridianApp({super.key});
  @override
  Widget build(BuildContext context) => AdaptiveApp.router(
    routerConfig: router,
    title: 'Meridian',
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    themeMode: ThemeMode.light,
    theme: const AdaptiveThemeData(
      primaryColor: red,
      background: paper,
      barStyle: AdaptiveBarStyle.solid(
        red,
        foreground: Colors.white,
        shadow: true,
        plainButtons: true,
      ),
    ),
  );
}
