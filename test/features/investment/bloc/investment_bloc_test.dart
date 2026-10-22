import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_widgets_on_duo/features/investment/bloc/investment_bloc.dart';

void main() {
  group('InvestmentBloc', () {
    test('starts on all accounts, one month and the default watchlist', () {
      expect(InvestmentBloc().state, const InvestmentState());
    });

    blocTest<InvestmentBloc, InvestmentState>(
      'AccountSelected switches the account and scales the balance',
      build: InvestmentBloc.new,
      act: (bloc) => bloc.add(const AccountSelected(1)),
      expect: () => [const InvestmentState(account: 1)],
      verify: (bloc) {
        expect(bloc.state.accountName, 'Personal');
        expect(bloc.state.accountScale, 0.6);
      },
    );

    blocTest<InvestmentBloc, InvestmentState>(
      'RangeSelected changes the chart range',
      build: InvestmentBloc.new,
      act: (bloc) => bloc.add(const RangeSelected(4)),
      expect: () => [const InvestmentState(range: 4)],
    );

    blocTest<InvestmentBloc, InvestmentState>(
      'WatchToggled removes a followed asset and adds it back',
      build: InvestmentBloc.new,
      act: (bloc) => bloc
        ..add(const WatchToggled('AAPL'))
        ..add(const WatchToggled('AAPL')),
      expect: () => [
        const InvestmentState(watchlist: {'NVDA', 'VOO'}),
        const InvestmentState(watchlist: {'NVDA', 'VOO', 'AAPL'}),
      ],
    );
  });
}
