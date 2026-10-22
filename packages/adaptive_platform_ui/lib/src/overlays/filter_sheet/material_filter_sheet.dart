import 'package:flutter/material.dart';

import 'adaptive_filter_sheet.dart';

/// The Material counterpart of the native filter sheet: a modal bottom sheet
/// that rests at the detents the native one would, drawn from the same
/// control specifications.
Future<Map<String, Object>?> showMaterialFilterSheet({
  required BuildContext context,
  required String title,
  required Color? tint,
  required AdaptiveFilterDetents detents,
  required List<AdaptiveFilterControl> controls,
  required Map<String, Object> values,
  required Map<String, Object> cleared,
  required int Function(Map<String, Object>) count,
}) => showModalBottomSheet<Map<String, Object>>(
  context: context,
  isScrollControlled: true,
  useRootNavigator: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _MaterialFilterSheet(
    title: title,
    tint: tint ?? Theme.of(context).colorScheme.primary,
    detents: detents,
    controls: controls,
    initial: values,
    cleared: cleared,
    count: count,
  ),
);

class _MaterialFilterSheet extends StatefulWidget {
  const _MaterialFilterSheet({
    required this.title,
    required this.tint,
    required this.detents,
    required this.controls,
    required this.initial,
    required this.cleared,
    required this.count,
  });
  final String title;
  final Color tint;
  final AdaptiveFilterDetents detents;
  final List<AdaptiveFilterControl> controls;
  final Map<String, Object> initial, cleared;
  final int Function(Map<String, Object>) count;

  @override
  State<_MaterialFilterSheet> createState() => _MaterialFilterSheetState();
}

class _MaterialFilterSheetState extends State<_MaterialFilterSheet> {
  late Map<String, Object> values = {...widget.initial};
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool get _isCleared {
    for (final e in widget.cleared.entries) {
      final v = values[e.key];
      final c = e.value;
      if (v is List && c is List) {
        if (v.length != c.length || !v.every(c.contains)) return false;
      } else if (v != c) {
        return false;
      }
    }
    return true;
  }

  void _set(String id, Object value) =>
      setState(() => values = {...values, id: value});

  List<String> _chosen(String id) => (values[id] as List<String>?) ?? const [];

  void _choose(AdaptiveFilterChoices control, String option) {
    final chosen = _chosen(control.id);
    if (control.multiple) {
      _set(control.id, [
        if (chosen.contains(option))
          ...chosen.where((e) => e != option)
        else ...[
          ...chosen,
          option,
        ],
      ]);
    } else {
      _set(control.id, [option]);
    }
  }

  (double initial, double min, List<double> snaps) get _sizes =>
      switch (widget.detents) {
        AdaptiveFilterDetents.halfAndFull => (0.5, 0.5, const [0.5, 0.95]),
        AdaptiveFilterDetents.full => (0.95, 0.95, const [0.95]),
        AdaptiveFilterDetents.short => (0.34, 0.34, const [0.34]),
      };

  @override
  Widget build(BuildContext context) {
    final (initial, min, snaps) = _sizes;
    // A draggable sheet with one resting height treats every upward drag as
    // a resize that cannot happen, so its list would never scroll. Single
    // detents are a plain fixed-height sheet instead.
    if (snaps.length == 1) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: snaps.single,
          child: _surface(context, _scroll),
        ),
      );
    }
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: initial,
      minChildSize: min,
      maxChildSize: snaps.last,
      snap: true,
      snapSizes: snaps,
      builder: _surface,
    );
  }

  Widget _surface(BuildContext context, ScrollController scroll) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              controller: scroll,
              padding: EdgeInsets.zero,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 32,
                    height: 4,
                    decoration: ShapeDecoration(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
                _header(context),
                for (final (i, c) in widget.controls.indexed)
                  _band(context, c, shaded: i.isOdd),
              ],
            ),
          ),
          _footer(context),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) => Stack(
    alignment: Alignment.centerRight,
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 72, 12),
          child: Text(
            widget.title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(right: 12),
        child: IconButton(
          tooltip: 'Reset filters',
          onPressed: _isCleared
              ? null
              : () => setState(() => values = {...widget.cleared}),
          icon: const Icon(Icons.restart_alt_rounded),
        ),
      ),
    ],
  );

  Widget _footer(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      8,
      24,
      MediaQuery.paddingOf(context).bottom + 12,
    ),
    child: SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: widget.tint,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: () => Navigator.pop(context, values),
        icon: const Icon(Icons.check_rounded),
        label: Text(
          '${widget.count(values)}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
    ),
  );

  Widget _band(
    BuildContext context,
    AdaptiveFilterControl control, {
    required bool shaded,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final edgeToEdge =
        control is AdaptiveFilterChoices &&
        control.layout == AdaptiveFilterLayout.stack;
    final body = switch (control) {
      final AdaptiveFilterChoices c => _choices(context, c),
      final AdaptiveFilterSlider s => _slider(context, s),
    };
    return ColoredBox(
      color: shaded ? scheme.surfaceContainer : Colors.transparent,
      child: SizedBox(
        width: double.infinity,
        child: edgeToEdge
            ? body
            : Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (control.icon != null) ...[
                      control.icon!.build(color: scheme.onSurfaceVariant),
                      const SizedBox(height: 12),
                    ],
                    body,
                  ],
                ),
              ),
      ),
    );
  }

  Widget _slider(BuildContext context, AdaptiveFilterSlider s) {
    final value = (values[s.id] as double?) ?? s.min;
    final atAny = s.anyAtMin ? value <= s.min : value >= s.max;
    final text = atAny && s.anyLabel != null
        ? s.anyLabel!
        : '${s.prefix}${_format(value, s.decimals)}${s.suffix}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        Slider(
          value: value.clamp(s.min, s.max),
          min: s.min,
          max: s.max,
          activeColor: widget.tint,
          onChanged: (v) => _set(s.id, v),
        ),
      ],
    );
  }

  String _format(double v, int decimals) {
    final fixed = v.toStringAsFixed(decimals);
    final parts = fixed.split('.');
    final whole = parts.first.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]},',
    );
    return parts.length > 1 ? '$whole.${parts[1]}' : whole;
  }

  Widget _choices(BuildContext context, AdaptiveFilterChoices c) {
    final scheme = Theme.of(context).colorScheme;
    bool on(AdaptiveFilterOption o) => _chosen(c.id).contains(o.id);
    Color tintOf(AdaptiveFilterOption o) => o.tint ?? widget.tint;

    switch (c.layout) {
      case AdaptiveFilterLayout.segmented:
        return SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            for (final o in c.options)
              ButtonSegment(value: o.id, label: Text(o.title)),
          ],
          selected: {if (_chosen(c.id).isNotEmpty) _chosen(c.id).first},
          onSelectionChanged: (s) => _choose(c, s.first),
        );
      case AdaptiveFilterLayout.blocks:
        return LayoutBuilder(
          builder: (context, box) {
            final cell = (box.maxWidth - 2 * (c.columns - 1)) / c.columns;
            return GridView.count(
              crossAxisCount: c.columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
              childAspectRatio: (cell / 84).clamp(1.0, 1.8),
              children: [
                for (final o in c.options)
                  Material(
                    color: on(o) ? tintOf(o) : scheme.surfaceContainerHighest,
                    child: InkWell(
                      onTap: () => _choose(c, o.id),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (o.icon != null)
                              o.icon!.build(
                                color: on(o) ? Colors.white : tintOf(o),
                                size: 28,
                              ),
                            const SizedBox(height: 8),
                            Text(
                              o.title,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: on(o) ? Colors.white : scheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      case AdaptiveFilterLayout.stack:
        return Column(
          spacing: 2,
          children: [
            for (final o in c.options)
              Material(
                color: on(o)
                    ? tintOf(o).withValues(alpha: 0.14)
                    : scheme.surfaceContainerHighest,
                child: InkWell(
                  onTap: () => _choose(c, o.id),
                  child: SizedBox(
                    width: double.infinity,
                    child: Stack(
                      alignment: Alignment.centerRight,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 22,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  if (o.icon != null)
                                    WidgetSpan(
                                      alignment: PlaceholderAlignment.middle,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          right: 14,
                                        ),
                                        child: o.icon!.build(color: tintOf(o)),
                                      ),
                                    ),
                                  TextSpan(text: o.title),
                                ],
                              ),
                              style: TextStyle(
                                fontSize: 17,
                                color: scheme.onSurface,
                                fontWeight: on(o)
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                        if (on(o))
                          Padding(
                            padding: const EdgeInsets.only(right: 20),
                            child: Icon(Icons.check_rounded, color: tintOf(o)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      case AdaptiveFilterLayout.chips:
      case AdaptiveFilterLayout.strip:
        final chips = [
          for (final o in c.options)
            FilterChip(
              avatar: o.icon?.build(
                color: on(o) ? tintOf(o) : scheme.onSurfaceVariant,
                size: 18,
              ),
              label: Text(o.title),
              selected: on(o),
              showCheckmark: false,
              selectedColor: tintOf(o).withValues(alpha: 0.16),
              side: BorderSide(
                color: on(o) ? tintOf(o) : scheme.outlineVariant,
              ),
              shape: const StadiumBorder(),
              onSelected: (_) => _choose(c, o.id),
            ),
        ];
        return c.layout == AdaptiveFilterLayout.strip
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                child: Wrap(spacing: 8, children: chips),
              )
            : Wrap(spacing: 8, runSpacing: 8, children: chips);
      case AdaptiveFilterLayout.swatches:
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final o in c.options)
              InkResponse(
                onTap: () => _choose(c, o.id),
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          width: 2.5,
                          color: on(o) ? widget.tint : Colors.transparent,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 30,
                        backgroundColor: tintOf(o),
                        child: Text(
                          o.title,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    if (on(o))
                      CircleAvatar(
                        radius: 10,
                        backgroundColor: widget.tint,
                        child: const Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
    }
  }
}
