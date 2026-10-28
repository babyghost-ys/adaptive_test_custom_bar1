import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';
import 'package:native_widgets_on_duo/core/widgets/page_scroll.dart';
import 'package:native_widgets_on_duo/features/learn/models/quiz.dart';

/// One question; choosing an answer pushes the next one.
class QuestionContent extends StatefulWidget {
  const QuestionContent({super.key, required this.index, required this.picks});

  /// Zero-based position in [quiz].
  final int index;

  /// Answers chosen on earlier pages.
  final List<int> picks;

  @override
  State<QuestionContent> createState() => _QuestionContentState();
}

class _QuestionContentState extends State<QuestionContent> {
  int? picked;

  Question get question => quiz[widget.index];

  Future<void> choose(int i) async {
    if (picked != null) return;
    setState(() => picked = i);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    final picks = [...widget.picks, i];
    final next = widget.index + 2;
    await context.push(
      next > quiz.length ? '/learn/done' : '/learn/$next',
      extra: picks,
    );
    if (mounted) setState(() => picked = null);
  }

  @override
  Widget build(BuildContext context) => PageScroll(
    storageKey: 'learn-${widget.index}',
    children: [
      Row(
        children: [
          for (var i = 0; i < quiz.length; i++) ...[
            Expanded(
              child: Container(
                height: 4,
                color: i <= widget.index ? red : const Color(0xFFE4E2DA),
              ),
            ),
            if (i < quiz.length - 1) const SizedBox(width: 4),
          ],
        ],
      ),
      const SizedBox(height: 36),
      Align(
        alignment: Alignment.centerLeft,
        child: Icon(question.icon, size: 44, color: red),
      ),
      const SizedBox(height: 16),
      label(question.prompt, size: 26, weight: FontWeight.w600),
      const SizedBox(height: 28),
      for (var i = 0; i < question.choices.length; i++) ...[
        const Divider(height: 1),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          leading: CircleAvatar(
            backgroundColor: picked == i ? red : const Color(0xFFEDEBE4),
            child: label(
              String.fromCharCode(65 + i),
              size: 14,
              weight: FontWeight.w600,
              color: picked == i ? Colors.white : ink,
            ),
          ),
          title: label(question.choices[i], size: 17),
          onTap: () => choose(i),
        ),
      ],
      const Divider(height: 1),
    ],
  );
}
