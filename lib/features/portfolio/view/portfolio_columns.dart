import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';

/// Aligns the divider with the centre of the window, including the space
/// reserved for Duo's vertical system controls.
class PortfolioColumns extends StatelessWidget {
  const PortfolioColumns({
    super.key,
    required this.portfolio,
    required this.detail,
  });

  final Widget portfolio;
  final Widget detail;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final pose = DuoPoseScope.of(context);
      final strip = pose == null
          ? 0.0
          : (pose.onLeft ? -pose.stripWidth : pose.stripWidth);
      final leftWidth = ((constraints.maxWidth + strip - 1) / 2).clamp(
        0.0,
        constraints.maxWidth - 1,
      );
      final media = MediaQuery.of(context);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: leftWidth,
            child: MediaQuery(
              data: media.copyWith(padding: media.padding.copyWith(right: 0)),
              child: portfolio,
            ),
          ),
          const VerticalDivider(
            width: 1,
            thickness: 1,
            color: Color(0xFFE6E5DF),
          ),
          Expanded(
            child: MediaQuery(
              data: media.copyWith(padding: media.padding.copyWith(left: 0)),
              child: detail,
            ),
          ),
        ],
      );
    },
  );
}
