import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';
import 'package:native_widgets_on_duo/features/learn/models/quiz.dart';

/// Full-bleed red band that opens the quiz.
class LearnBanner extends StatelessWidget {
  const LearnBanner({super.key});

  @override
  Widget build(BuildContext context) => Material(
    child: Ink(
      height: 120,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [red, redLight],
        ),
      ),
      child: InkWell(
        onTap: () => context.push('/learn/1'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              const Icon(Icons.school_rounded, size: 40, color: Colors.white),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    label(
                      'Order basics',
                      size: 20,
                      weight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.help_outline_rounded,
                          size: 15,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 4),
                        label(
                          '${quiz.length}',
                          size: 14,
                          color: Colors.white70,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    ),
  );
}
