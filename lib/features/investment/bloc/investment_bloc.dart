import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'package:native_widgets_on_duo/features/investment/data/demo_assets.dart';

part 'investment_event.dart';
part 'investment_state.dart';

class InvestmentBloc extends Bloc<InvestmentEvent, InvestmentState> {
  InvestmentBloc() : super(const InvestmentState()) {
    on<AccountSelected>(
      (event, emit) => emit(state.copy(account: event.index)),
    );
    on<RangeSelected>((event, emit) => emit(state.copy(range: event.index)));
    on<WatchToggled>((event, emit) {
      final next = {...state.watchlist};
      next.contains(event.symbol)
          ? next.remove(event.symbol)
          : next.add(event.symbol);
      emit(state.copy(watchlist: next));
    });
  }
}
