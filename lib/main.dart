import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:native_widgets_on_duo/app/meridian_app.dart';
import 'package:native_widgets_on_duo/app/native_sheet_app.dart';
import 'package:native_widgets_on_duo/features/investment/bloc/investment_bloc.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    BlocProvider(create: (_) => InvestmentBloc(), child: const MeridianApp()),
  );
}

/// Native sheets start their own isolate while the page keeps rendering.
@pragma('vm:entry-point')
void nativeSheetMain() {
  runNativeSheetApp();
}
