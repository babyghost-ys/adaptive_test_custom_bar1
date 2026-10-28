import 'package:flutter/material.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';
import 'package:native_widgets_on_duo/core/widgets/page_scroll.dart';
import 'package:native_widgets_on_duo/features/learn/models/quiz.dart';

class LearnResultContent extends StatelessWidget {
  const LearnResultContent({super.key, required this.picks});
  final List<int> picks;

  @override
  Widget build(BuildContext context) => PageScroll(
    storageKey: 'learn-done',
    children: [
      const SizedBox(height: 12),
      const Icon(Icons.emoji_events_rounded, size: 56, color: red),
      const SizedBox(height: 12),
      Center(
        child: label(
          '${score(picks)} / ${quiz.length}',
          size: 44,
          weight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 28),
      for (var i = 0; i < quiz.length; i++) ...[
        const Divider(height: 1),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 6),
          leading: Icon(quiz[i].icon, color: muted),
          title: label(quiz[i].choices[quiz[i].answer]),
          trailing: Icon(
            i < picks.length && picks[i] == quiz[i].answer
                ? Icons.check_circle_rounded
                : Icons.cancel_rounded,
            color: i < picks.length && picks[i] == quiz[i].answer ? green : red,
          ),
        ),
      ],
      const Divider(height: 1),
    ],
  );
}
