import 'package:flutter/material.dart';

class Question {
  const Question(this.icon, this.prompt, this.choices, this.answer);
  final IconData icon;
  final String prompt;
  final List<String> choices;

  /// Index into [choices].
  final int answer;
}

const quiz = [
  Question(Icons.price_change_outlined, 'A limit order fills…', [
    'At any price',
    'At your price or better',
    'Only at market close',
  ], 1),
  Question(Icons.bolt_rounded, 'A market order prioritises…', [
    'Speed',
    'Price',
    'Dividends',
  ], 0),
  Question(Icons.pie_chart_outline, 'Spreading money across many assets is…', [
    'Leverage',
    'Diversification',
    'Shorting',
  ], 1),
  Question(Icons.savings_outlined, 'An ISA shelters gains from…', [
    'Fees',
    'Volatility',
    'Tax',
  ], 2),
];

int score(List<int> picks) => [
  for (var i = 0; i < picks.length; i++)
    if (picks[i] == quiz[i].answer) 1,
].length;
