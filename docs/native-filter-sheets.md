# Native filter sheets

How the filter sheets in this app are built: a real UIKit sheet on iOS, a Material
bottom sheet everywhere else, both drawn from one declarative description of the
controls. Every code listing below is the actual source, included in full.

## Contents

1. [What it does](#what-it-does)
2. [Why it is built this way](#why-it-is-built-this-way)
3. [Architecture](#architecture)
4. [The platform channel contract](#the-platform-channel-contract)
5. [Package code](#package-code)
6. [App code, end to end](#app-code-end-to-end)
7. [Every control layout](#every-control-layout)
8. [Problems found while testing, and the fixes](#problems-found-while-testing-and-the-fixes)
9. [How it was tested](#how-it-was-tested)
10. [Adding a filter sheet to a new page](#adding-a-filter-sheet-to-a-new-page)

## What it does

Four pages have a filter button beside a section title. Tapping it opens a sheet:

| Page | Sheet | Heights | Layouts used |
|---|---|---|---|
| Markets | movement, sort, price, type, change, symbols | half, draggable to full | blocks, chips, slider, swatches |
| Activity | type, symbols, period, amount | half, draggable to full | stack, swatches, strip, slider |
| Watchlist | movement | short | blocks |
| Portfolio holdings | sort, movement, type, size, change, symbols | full only | strip, stack, blocks, sliders, swatches |

On iOS the sheet is a `UISheetPresentationController`. It floats above the whole window,
so it covers the navigation bar and tab bar, and it dims everything behind it. On
Android and other platforms the same controls draw in a Material bottom sheet that
rests at the same heights and covers the bottom bar.

Every change reports back to Dart, which returns how many results the current choices
give. The apply button shows that number live. The reset icon restores the cleared
values. Dismissing without applying returns `null`, so the page keeps its old filter.

## Why it is built this way

* A Flutter route can only draw inside the Flutter view. This app's navigation bar
  and tab bar are native UIKit views above it, so a Flutter sheet stops below them.
  A `UISheetPresentationController` presented from the root view controller sits above
  everything.
* Native UIKit needs native views. Hosting a second Flutter view inside a native sheet
  would mean a second engine and state passing, so the sheet is described to native
  code as data instead (a list of controls) and UIKit draws it.
* The page owns what the filter means. The sheet owns drawing, the draft, the live
  count and the apply button. The page hands over controls and gets values back.
* The Material fallback reads the same control list, so Android needs no second
  description of the sheet.

## Architecture

```
page (Markets, Activity, ...)
  |  builds controls + current values + cleared values + count()
  v
AdaptiveFilterSheet.show(...)                 packages/adaptive_platform_ui
  |-- native style (iOS) --> MethodChannel "adaptive_platform_ui/filter_sheet"
  |                              show(spec)  --> NativeFilterSheet.swift
  |                              <-- changed(values) -- count --> Dart count()
  |                              <-- chosen values or null
  '-- material style -----> showMaterialFilterSheet(...)  (all in Dart)
```

Values are plain data: a `List<String>` of chosen option ids for a choices control, a
`double` for a slider. The page converts its own filter model to and from this map.

## The platform channel contract

Channel name: `adaptive_platform_ui/filter_sheet`.

**Dart to native, `show`.** Arguments:

| Key | Type | Meaning |
|---|---|---|
| `title` | String | Heading |
| `tint` | int (ARGB) | Accent colour of the apply button and selections |
| `detents` | String | `halfAndFull`, `full` or `short` |
| `controls` | List of Map | See below |
| `values` | Map | Current value per control id |
| `cleared` | Map | Value per control id that reset restores |
| `count` | int | Initial result count |

A choices control: `{type: 'choices', id, symbol, layout, multiple, columns, options: [{id, title, symbol, tint}]}`.
A slider control: `{type: 'slider', id, symbol, min, max, prefix, suffix, decimals, anyLabel, anyAtMin}`.

The result is the chosen values map, or `null` when dismissed.

**Native to Dart, `changed`.** Sent on every edit with the current values map. Dart
answers with the result count as an `int`.

## Package code

### Register the channel in the plugin

Add this to `register(with:)` in `AdaptivePlatformUiPlugin.swift`:

```swift
        let filterSheetChannel = FlutterMethodChannel(
            name: "adaptive_platform_ui/filter_sheet", binaryMessenger: registrar.messenger())
        let filterSheets = NativeFilterSheet(
            channel: filterSheetChannel, hostProvider: { registrar.viewController })
        filterSheetChannel.setMethodCallHandler { call, result in
            filterSheets.handle(call, result: result)
        }
```

### Export it

In `packages/adaptive_platform_ui/lib/adaptive_platform_ui.dart`:

```dart
export 'src/overlays/filter_sheet/adaptive_filter_sheet.dart';
```

### Dart API and channel client

```dart
// packages/adaptive_platform_ui/lib/src/overlays/filter_sheet/adaptive_filter_sheet.dart
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import '../../core/adaptive_style.dart';
import '../../style/adaptive_icon.dart';
import 'material_filter_sheet.dart';

/// How a group of options is laid out in an [AdaptiveFilterSheet].
enum AdaptiveFilterLayout {
  /// A native segmented control. Single choice only.
  segmented,

  /// A grid of square-cornered blocks, an icon over a word.
  blocks,

  /// Tall full-width bands, one above another, the chosen one ticked.
  stack,

  /// Wrapping pill chips.
  chips,

  /// One horizontally scrolling line of pill chips.
  strip,

  /// Wrapping coloured discs labelled with the option title.
  swatches,
}

/// How tall a filter sheet rests.
enum AdaptiveFilterDetents {
  /// Half height, draggable to full height.
  halfAndFull,

  /// Full height only.
  full,

  /// A short sheet that fits a single control.
  short,
}

/// One choice in an [AdaptiveFilterChoices].
class AdaptiveFilterOption {
  const AdaptiveFilterOption(this.id, this.title, {this.icon, this.tint});
  final String id;
  final String title;

  /// Drawn as an SF Symbol on iOS and a Material icon elsewhere.
  final AdaptiveIcon? icon;

  /// Colour of the chosen state. Defaults to the sheet's tint.
  final Color? tint;
}

/// A control in an [AdaptiveFilterSheet]. Its value is keyed by [id] in the
/// sheet's values: a `List<String>` of chosen option ids for
/// [AdaptiveFilterChoices], a `double` for [AdaptiveFilterSlider].
sealed class AdaptiveFilterControl {
  const AdaptiveFilterControl(this.id, {this.icon});
  final String id;

  /// Icon that names the control.
  final AdaptiveIcon? icon;

  Map<String, Object?> _encode();
}

class AdaptiveFilterChoices extends AdaptiveFilterControl {
  const AdaptiveFilterChoices(
    super.id,
    this.options, {
    super.icon,
    this.layout = AdaptiveFilterLayout.chips,
    this.multiple = false,
    this.columns = 3,
  });
  final List<AdaptiveFilterOption> options;
  final AdaptiveFilterLayout layout;
  final bool multiple;

  /// Columns of an [AdaptiveFilterLayout.blocks] grid.
  final int columns;

  @override
  Map<String, Object?> _encode() => {
    'type': 'choices',
    'id': id,
    'symbol': icon?.sfSymbol,
    'layout': layout.name,
    'multiple': multiple,
    'columns': columns,
    'options': [
      for (final o in options)
        {
          'id': o.id,
          'title': o.title,
          'symbol': o.icon?.sfSymbol,
          'tint': o.tint?.toARGB32(),
        },
    ],
  };
}

class AdaptiveFilterSlider extends AdaptiveFilterControl {
  const AdaptiveFilterSlider(
    super.id, {
    super.icon,
    required this.min,
    required this.max,
    this.prefix = '',
    this.suffix = '',
    this.decimals = 0,
    this.anyLabel,
    this.anyAtMin = true,
  });
  final double min, max;

  /// Text around the number in the live readout.
  final String prefix, suffix;
  final int decimals;

  /// Readout shown instead of a number when the slider rests at its
  /// unrestricted end, [min] when [anyAtMin], otherwise [max].
  final String? anyLabel;
  final bool anyAtMin;

  @override
  Map<String, Object?> _encode() => {
    'type': 'slider',
    'id': id,
    'symbol': icon?.sfSymbol,
    'min': min,
    'max': max,
    'prefix': prefix,
    'suffix': suffix,
    'decimals': decimals,
    'anyLabel': anyLabel,
    'anyAtMin': anyAtMin,
  };
}

/// A real UIKit sheet (`UISheetPresentationController`) of filter controls.
///
/// It floats above the whole window, so it covers native navigation and tab
/// bars. The caller describes the controls; UIKit draws them, and the sheet
/// asks [count] after every change so its apply button shows how many
/// results the current choices give.
///
/// Where [AdaptiveStyle] is material the same controls draw in a Material
/// bottom sheet that rests at the same heights.
class AdaptiveFilterSheet {
  AdaptiveFilterSheet._();
  static const _channel = MethodChannel('adaptive_platform_ui/filter_sheet');

  /// Whether the sheet is a native UIKit sheet for [context]. Elsewhere it is
  /// a Material bottom sheet with the same controls.
  static bool isNative(BuildContext context) =>
      AdaptiveStyle.of(context) == AdaptiveStyle.native;

  /// Shows the sheet and returns the chosen values, or null when it is
  /// dismissed without applying.
  ///
  /// [values] and [cleared] map each control id to its value: the current
  /// choice, and what the reset button restores.
  static Future<Map<String, Object>?> show({
    required BuildContext context,
    required List<AdaptiveFilterControl> controls,
    required Map<String, Object> values,
    required Map<String, Object> cleared,
    required int Function(Map<String, Object> values) count,
    String title = '',
    Color? tint,
    AdaptiveFilterDetents detents = AdaptiveFilterDetents.halfAndFull,
  }) async {
    if (!isNative(context)) {
      return showMaterialFilterSheet(
        context: context,
        title: title,
        tint: tint,
        detents: detents,
        controls: controls,
        values: values,
        cleared: cleared,
        count: count,
      );
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'changed') return null;
      return count(_decode(call.arguments));
    });
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('show', {
        'title': title,
        'tint': tint?.toARGB32(),
        'detents': detents.name,
        'controls': [for (final c in controls) c._encode()],
        'values': values,
        'cleared': cleared,
        'count': count(values),
      });
      return result == null ? null : _decode(result);
    } on PlatformException {
      return null;
    } finally {
      _channel.setMethodCallHandler(null);
    }
  }

  static Map<String, Object> _decode(Object? raw) => {
    for (final entry in (raw as Map).entries)
      entry.key as String: switch (entry.value) {
        final List<Object?> list => [for (final v in list) v as String],
        final num number => number.toDouble(),
        _ => entry.value!,
      },
  };
}
```

### Native sheet (Swift, UIKit)

```swift
// packages/adaptive_platform_ui/ios/adaptive_platform_ui/Sources/adaptive_platform_ui/Overlays/NativeFilterSheet.swift
import Flutter
import UIKit

// MARK: - Specification

struct FilterOptionSpec {
    let id: String
    let title: String
    let symbol: String?
    let tint: UIColor?
}

enum FilterControlKind {
    case choices(options: [FilterOptionSpec], multiple: Bool, layout: String, columns: Int)
    case slider(min: Double, max: Double, prefix: String, suffix: String, decimals: Int,
                anyLabel: String?, anyAtMin: Bool)
}

struct FilterControlSpec {
    let id: String
    let symbol: String?
    let kind: FilterControlKind
}

private func filterColor(_ value: Any?) -> UIColor? {
    guard let argb = (value as? NSNumber)?.int64Value else { return nil }
    return UIColor(
        red: CGFloat((argb >> 16) & 0xFF) / 255,
        green: CGFloat((argb >> 8) & 0xFF) / 255,
        blue: CGFloat(argb & 0xFF) / 255,
        alpha: CGFloat((argb >> 24) & 0xFF) / 255)
}

private func parseControls(_ raw: [[String: Any]]) -> [FilterControlSpec] {
    raw.compactMap { entry in
        guard let id = entry["id"] as? String, let type = entry["type"] as? String else { return nil }
        let symbol = entry["symbol"] as? String
        switch type {
        case "choices":
            let options = (entry["options"] as? [[String: Any]] ?? []).compactMap { option -> FilterOptionSpec? in
                guard let optionId = option["id"] as? String, let title = option["title"] as? String else { return nil }
                return FilterOptionSpec(id: optionId, title: title,
                                        symbol: option["symbol"] as? String,
                                        tint: filterColor(option["tint"]))
            }
            return FilterControlSpec(id: id, symbol: symbol, kind: .choices(
                options: options,
                multiple: entry["multiple"] as? Bool ?? false,
                layout: entry["layout"] as? String ?? "chips",
                columns: entry["columns"] as? Int ?? 3))
        case "slider":
            return FilterControlSpec(id: id, symbol: symbol, kind: .slider(
                min: (entry["min"] as? NSNumber)?.doubleValue ?? 0,
                max: (entry["max"] as? NSNumber)?.doubleValue ?? 1,
                prefix: entry["prefix"] as? String ?? "",
                suffix: entry["suffix"] as? String ?? "",
                decimals: entry["decimals"] as? Int ?? 0,
                anyLabel: entry["anyLabel"] as? String,
                anyAtMin: entry["anyAtMin"] as? Bool ?? true))
        default:
            return nil
        }
    }
}

/// Normalises a values map so equal selections compare equal.
private func normalised(_ values: [String: Any]) -> [String: Any] {
    var result: [String: Any] = [:]
    for (key, value) in values {
        if let list = value as? [String] {
            result[key] = list.sorted()
        } else if let number = value as? NSNumber {
            result[key] = number.doubleValue
        }
    }
    return result
}

// MARK: - Presenter

/// A UIKit sheet (`UISheetPresentationController`) built from a declarative
/// list of controls. It floats above the whole window, navigation bars
/// included, and reports each change to Dart so the apply button can show a
/// live result count.
final class NativeFilterSheet: NSObject, UIAdaptivePresentationControllerDelegate {
    private let channel: FlutterMethodChannel
    private let hostProvider: () -> UIViewController?
    private var pending: FlutterResult?
    private weak var presented: FilterSheetController?

    init(channel: FlutterMethodChannel, hostProvider: @escaping () -> UIViewController?) {
        self.channel = channel
        self.hostProvider = hostProvider
    }

    private func visibleHost() -> UIViewController? {
        if let host = hostProvider(), host.viewIfLoaded?.window != nil { return host }
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap { $0.windows }
        return windows.first(where: { $0.isKeyWindow })?.rootViewController
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "show" else {
            result(FlutterMethodNotImplemented)
            return
        }
        if pending != nil {
            if let sheet = presented, sheet.presentingViewController != nil {
                result(FlutterError(code: "busy", message: "A filter sheet is already open", details: nil))
                return
            }
            finish(nil)
        }
        guard let host = visibleHost(),
              let args = call.arguments as? [String: Any],
              let rawControls = args["controls"] as? [[String: Any]] else {
            result(FlutterError(code: "unavailable", message: "No visible host for the filter sheet", details: nil))
            return
        }
        var presenter = host
        while let next = presenter.presentedViewController { presenter = next }
        guard !presenter.isBeingDismissed else {
            result(nil)
            return
        }

        let controller = FilterSheetController(
            title: args["title"] as? String ?? "",
            controls: parseControls(rawControls),
            values: normalised(args["values"] as? [String: Any] ?? [:]),
            cleared: normalised(args["cleared"] as? [String: Any] ?? [:]),
            accent: filterColor(args["tint"]) ?? .systemRed,
            detents: args["detents"] as? String ?? "halfAndFull",
            count: (args["count"] as? NSNumber)?.intValue ?? 0)
        controller.onChange = { [weak self] values, update in
            self?.channel.invokeMethod("changed", arguments: values) { reply in
                if let count = (reply as? NSNumber)?.intValue { update(count) }
            }
        }
        controller.onFinish = { [weak self] values in self?.finish(values) }
        controller.presentationController?.delegate = self
        pending = result
        presented = controller
        presenter.present(controller, animated: true)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finish(nil)
    }

    private func finish(_ values: [String: Any]?) {
        let callback = pending
        pending = nil
        callback?(values)
    }
}

// MARK: - Sheet content

final class FilterSheetController: UIViewController {
    var onChange: (([String: Any], @escaping (Int) -> Void) -> Void)?
    var onFinish: (([String: Any]?) -> Void)?

    private let sheetTitle: String
    private let controls: [FilterControlSpec]
    private let cleared: [String: Any]
    private let accent: UIColor
    private let detents: String
    private var values: [String: Any]
    private var count: Int

    private let titleLabel = UILabel()
    private let resetButton = UIButton(type: .system)
    private let applyButton = UIButton(type: .system)
    private let sections = UIStackView()
    private var selectionRefreshers: [String: () -> Void] = [:]

    init(title: String, controls: [FilterControlSpec], values: [String: Any],
         cleared: [String: Any], accent: UIColor, detents: String, count: Int) {
        self.sheetTitle = title
        self.controls = controls
        self.values = values
        self.cleared = cleared
        self.accent = accent
        self.detents = detents
        self.count = count
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        configureSheet()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func configureSheet() {
        guard let sheet = sheetPresentationController else { return }
        switch detents {
        case "full":
            sheet.detents = [.large()]
        case "short":
            if #available(iOS 16.0, *) {
                sheet.detents = [.custom(identifier: UISheetPresentationController.Detent.Identifier("short")) {
                    context in
                    min(context.maximumDetentValue, max(context.maximumDetentValue * 0.34, 300))
                }]
            } else {
                sheet.detents = [.medium()]
            }
        default:
            sheet.detents = [.medium(), .large()]
        }
        sheet.prefersGrabberVisible = true
        sheet.prefersScrollingExpandsWhenScrolledToEdge = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        titleLabel.text = sheetTitle
        titleLabel.font = UIFont.systemFont(ofSize: 22, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        resetButton.setImage(UIImage(systemName: "arrow.counterclockwise"), for: .normal)
        resetButton.tintColor = .label
        resetButton.accessibilityLabel = "Reset filters"
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.addAction(UIAction { [weak self] _ in self?.reset() }, for: .touchUpInside)

        var apply = UIButton.Configuration.filled()
        apply.baseBackgroundColor = accent
        apply.baseForegroundColor = .white
        apply.cornerStyle = .capsule
        apply.image = UIImage(systemName: "checkmark")
        apply.imagePadding = 8
        apply.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
        applyButton.configuration = apply
        applyButton.translatesAutoresizingMaskIntoConstraints = false
        applyButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.dismiss(animated: true)
            self.onFinish?(self.values)
        }, for: .touchUpInside)

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        sections.axis = .vertical
        sections.spacing = 0
        sections.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(sections)

        view.addSubview(titleLabel)
        view.addSubview(resetButton)
        view.addSubview(scroll)
        view.addSubview(applyButton)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            resetButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            resetButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            resetButton.widthAnchor.constraint(equalToConstant: 44),
            resetButton.heightAnchor.constraint(equalToConstant: 44),
            scroll.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: applyButton.topAnchor, constant: -8),
            sections.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            sections.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            sections.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            sections.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
            applyButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            applyButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            applyButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -8),
        ])

        buildSections()
        refreshChrome()
    }

    // MARK: State

    private func reset() {
        values = cleared
        buildSections()
        notify()
    }

    private func notify() {
        refreshChrome()
        onChange?(values) { [weak self] count in
            self?.count = count
            self?.refreshChrome()
        }
    }

    private func refreshChrome() {
        resetButton.isEnabled = !NSDictionary(dictionary: values).isEqual(to: cleared)
        var config = applyButton.configuration
        config?.title = "\(count)"
        config?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
            return attributes
        }
        applyButton.configuration = config
    }

    private func selected(_ id: String) -> [String] { values[id] as? [String] ?? [] }

    private func choose(_ control: FilterControlSpec, option: String, multiple: Bool) {
        if multiple {
            var set = Set(selected(control.id))
            if set.contains(option) { set.remove(option) } else { set.insert(option) }
            values[control.id] = Array(set).sorted()
        } else {
            values[control.id] = [option]
        }
        selectionRefreshers[control.id]?()
        notify()
    }

    // MARK: Sections

    private func buildSections() {
        sections.arrangedSubviews.forEach { $0.removeFromSuperview() }
        selectionRefreshers = [:]
        for (index, control) in controls.enumerated() {
            sections.addArrangedSubview(makeSection(control, shaded: index % 2 == 1))
        }
    }

    private func makeSection(_ control: FilterControlSpec, shaded: Bool) -> UIView {
        let band = UIView()
        band.backgroundColor = shaded ? .secondarySystemBackground : .clear

        let column = UIStackView()
        column.axis = .vertical
        column.spacing = 14
        column.translatesAutoresizingMaskIntoConstraints = false
        band.addSubview(column)

        var edgeToEdge = false
        if case .choices(_, _, let layout, _) = control.kind, layout == "stack" { edgeToEdge = true }

        let insets: CGFloat = edgeToEdge ? 0 : 24
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: band.topAnchor, constant: edgeToEdge ? 0 : 18),
            column.bottomAnchor.constraint(equalTo: band.bottomAnchor, constant: edgeToEdge ? 0 : -22),
            column.leadingAnchor.constraint(equalTo: band.leadingAnchor, constant: insets),
            column.trailingAnchor.constraint(equalTo: band.trailingAnchor, constant: -insets),
        ])

        if !edgeToEdge, let symbol = control.symbol {
            let icon = UIImageView(image: UIImage(systemName: symbol))
            icon.tintColor = .secondaryLabel
            icon.contentMode = .left
            icon.setContentHuggingPriority(.required, for: .vertical)
            column.addArrangedSubview(icon)
        }

        switch control.kind {
        case .choices(let options, let multiple, let layout, let columns):
            column.addArrangedSubview(
                makeChoices(control, options: options, multiple: multiple, layout: layout, columns: columns))
        case .slider(let min, let max, let prefix, let suffix, let decimals, let anyLabel, let anyAtMin):
            column.addArrangedSubview(makeSlider(
                control, min: min, max: max, prefix: prefix, suffix: suffix,
                decimals: decimals, anyLabel: anyLabel, anyAtMin: anyAtMin))
        }
        return band
    }

    // MARK: Choices

    private func makeChoices(_ control: FilterControlSpec, options: [FilterOptionSpec],
                             multiple: Bool, layout: String, columns: Int) -> UIView {
        if layout == "segmented" {
            let segmented = UISegmentedControl(items: options.map { $0.title })
            segmented.selectedSegmentTintColor = accent
            segmented.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
            let apply = { [weak self] in
                guard let self else { return }
                let chosen = self.selected(control.id).first
                segmented.selectedSegmentIndex = options.firstIndex { $0.id == chosen } ?? UISegmentedControl.noSegment
            }
            apply()
            selectionRefreshers[control.id] = apply
            segmented.addAction(UIAction { [weak self] _ in
                let index = segmented.selectedSegmentIndex
                guard index >= 0 else { return }
                self?.choose(control, option: options[index].id, multiple: false)
            }, for: .valueChanged)
            return segmented
        }

        var buttons: [(FilterOptionSpec, UIButton)] = []
        for option in options {
            let button = makeChoiceButton(option, layout: layout)
            button.addAction(UIAction { [weak self] _ in
                self?.choose(control, option: option.id, multiple: multiple)
            }, for: .touchUpInside)
            buttons.append((option, button))
        }
        let refresh = { [weak self] in
            guard let self else { return }
            let chosen = Set(self.selected(control.id))
            for (option, button) in buttons { button.isSelected = chosen.contains(option.id) }
        }
        refresh()
        selectionRefreshers[control.id] = refresh

        switch layout {
        case "blocks":
            let grid = UIStackView()
            grid.axis = .vertical
            grid.spacing = 2
            let perRow = max(1, columns)
            for start in stride(from: 0, to: buttons.count, by: perRow) {
                let row = UIStackView()
                row.axis = .horizontal
                row.distribution = .fillEqually
                row.spacing = 2
                let slice = buttons[start..<min(start + perRow, buttons.count)]
                slice.forEach { row.addArrangedSubview($0.1) }
                for _ in slice.count..<perRow { row.addArrangedSubview(UIView()) }
                grid.addArrangedSubview(row)
            }
            return grid
        case "stack":
            let list = UIStackView(arrangedSubviews: buttons.map { $0.1 })
            list.axis = .vertical
            list.spacing = 2
            return list
        case "strip":
            let scroll = UIScrollView()
            scroll.showsHorizontalScrollIndicator = false
            scroll.clipsToBounds = false
            let row = UIStackView(arrangedSubviews: buttons.map { $0.1 })
            row.axis = .horizontal
            row.spacing = 8
            row.translatesAutoresizingMaskIntoConstraints = false
            scroll.addSubview(row)
            NSLayoutConstraint.activate([
                row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
                row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
                row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
                row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
                scroll.heightAnchor.constraint(equalTo: row.heightAnchor),
            ])
            return scroll
        default:
            let flow = FilterFlowView(spacing: layout == "swatches" ? 14 : 8)
            buttons.forEach { flow.addArrangedSubview($0.1) }
            return flow
        }
    }

    private func makeChoiceButton(_ option: FilterOptionSpec, layout: String) -> UIButton {
        let tint = option.tint ?? accent
        let symbol = option.symbol.flatMap { UIImage(systemName: $0) }
        var config = UIButton.Configuration.filled()
        config.title = option.title
        config.baseBackgroundColor = .tertiarySystemFill

        let button: UIButton = layout == "swatches" ? SwatchButton(configuration: config) : UIButton(configuration: config)
        var badge: UIImageView?

        switch layout {
        case "blocks":
            config.imagePlacement = .top
            config.imagePadding = 8
            config.cornerStyle = .fixed
            config.background.cornerRadius = 0
            config.contentInsets = NSDirectionalEdgeInsets(top: 20, leading: 8, bottom: 20, trailing: 8)
        case "stack":
            config.imagePlacement = .leading
            config.imagePadding = 14
            config.cornerStyle = .fixed
            config.background.cornerRadius = 0
            config.contentInsets = NSDirectionalEdgeInsets(top: 22, leading: 20, bottom: 22, trailing: 20)
            button.contentHorizontalAlignment = .leading
            let check = UIImageView(image: UIImage(systemName: "checkmark"))
            check.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(check)
            NSLayoutConstraint.activate([
                check.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                check.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -20),
            ])
            badge = check
        case "swatches":
            config.cornerStyle = .capsule
            config.contentInsets = .zero
            config.title = option.title
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = UIFont.systemFont(ofSize: 12, weight: .bold)
                return attributes
            }
        default:
            config.cornerStyle = .capsule
            config.imagePadding = 6
            config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        }
        if layout != "swatches" { config.image = symbol }
        button.configuration = config

        button.configurationUpdateHandler = { [accent] button in
            var updated = button.configuration
            let on = button.isSelected
            switch layout {
            case "blocks":
                updated?.baseBackgroundColor = on ? tint : .tertiarySystemFill
                updated?.baseForegroundColor = on ? .white : .label
                updated?.image = symbol?.withTintColor(on ? .white : tint, renderingMode: .alwaysOriginal)
            case "stack":
                updated?.baseBackgroundColor = on ? tint.withAlphaComponent(0.14) : .tertiarySystemFill
                updated?.baseForegroundColor = .label
                updated?.image = symbol?.withTintColor(tint, renderingMode: .alwaysOriginal)
                badge?.tintColor = tint
                badge?.isHidden = !on
            case "swatches":
                updated?.baseBackgroundColor = tint
                updated?.baseForegroundColor = .white
                updated?.background.strokeColor = accent
                updated?.background.strokeWidth = on ? 3 : 0
                updated?.background.strokeOutset = on ? 3 : 0
            default:
                updated?.baseBackgroundColor = on ? tint : .tertiarySystemFill
                updated?.baseForegroundColor = on ? .white : .label
                updated?.image = symbol?.withTintColor(on ? .white : tint, renderingMode: .alwaysOriginal)
            }
            button.configuration = updated
        }
        return button
    }

    // MARK: Slider

    private func makeSlider(_ control: FilterControlSpec, min: Double, max: Double, prefix: String,
                            suffix: String, decimals: Int, anyLabel: String?, anyAtMin: Bool) -> UIView {
        let readout = UILabel()
        readout.font = UIFont.systemFont(ofSize: 34, weight: .semibold)
        readout.adjustsFontSizeToFitWidth = true
        readout.minimumScaleFactor = 0.6

        let slider = UISlider()
        slider.minimumValue = Float(min)
        slider.maximumValue = Float(max)
        slider.minimumTrackTintColor = accent
        slider.value = Float((values[control.id] as? Double) ?? min)

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals

        let update = {
            let value = Double(slider.value)
            let atAny = anyAtMin ? value <= min : value >= max
            if atAny, let anyLabel {
                readout.text = anyLabel
            } else {
                readout.text = prefix + (formatter.string(from: NSNumber(value: value)) ?? "") + suffix
            }
        }
        update()
        slider.addAction(UIAction { [weak self] _ in
            self?.values[control.id] = Double(slider.value)
            update()
            self?.notify()
        }, for: .valueChanged)

        let column = UIStackView(arrangedSubviews: [readout, slider])
        column.axis = .vertical
        column.spacing = 10
        return column
    }
}

// MARK: - Swatch

/// A disc of fixed size. The size comes from the intrinsic content size so the
/// flow layout can measure it without extra constraints.
final class SwatchButton: UIButton {
    override var intrinsicContentSize: CGSize { CGSize(width: 64, height: 64) }
}

// MARK: - Wrapping layout

/// Lays its subviews out left to right, wrapping onto new lines, and sizes
/// itself to the lines it needs.
final class FilterFlowView: UIView {
    private let spacing: CGFloat
    private var heightConstraint: NSLayoutConstraint?

    init(spacing: CGFloat) {
        self.spacing = spacing
        super.init(frame: .zero)
        let constraint = heightAnchor.constraint(equalToConstant: 0)
        constraint.priority = .required
        constraint.isActive = true
        heightConstraint = constraint
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func addArrangedSubview(_ view: UIView) { addSubview(view) }

    private func place(width: CGFloat, apply: Bool) -> CGFloat {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for view in subviews {
            let intrinsic = view.intrinsicContentSize
            let size = intrinsic.width == UIView.noIntrinsicMetric
                ? view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
                : intrinsic
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            if apply { view.frame = CGRect(origin: CGPoint(x: x, y: y), size: size) }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return y + lineHeight
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        let height = place(width: bounds.width, apply: true)
        if heightConstraint?.constant != height { heightConstraint?.constant = height }
    }
}
```

### Material fallback

```dart
// packages/adaptive_platform_ui/lib/src/overlays/filter_sheet/material_filter_sheet.dart
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
```

## App code, end to end

The Markets page shows every layer: the filter model, the sheet description, and the
page wiring.

### Helpers shared by the sheets

```dart
// lib/core/filtering/filter_values.dart
import 'package:flutter/painting.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'package:native_widgets_on_duo/features/investment/models/asset.dart';

/// Reads the chosen option ids of a choices control.
List<String> chosenIds(Map<String, Object> values, String id) =>
    (values[id] as List<String>?) ?? const [];

/// The first chosen id of a single-choice control, as the matching enum.
T chosenEnum<T extends Enum>(
  Map<String, Object> values,
  String id,
  List<T> all,
) {
  final ids = chosenIds(values, id);
  return all.firstWhere(
    (e) => ids.isNotEmpty && e.name == ids.first,
    orElse: () => all.first,
  );
}

/// Every chosen id of a multiple-choice control, as the matching enums.
Set<T> chosenEnums<T extends Enum>(
  Map<String, Object> values,
  String id,
  List<T> all,
) {
  final ids = chosenIds(values, id).toSet();
  return {
    for (final e in all)
      if (ids.contains(e.name)) e,
  };
}

/// One option per asset, drawn as a coloured disc.
List<AdaptiveFilterOption> assetSwatches(List<Asset> assets) => [
  for (final a in assets)
    AdaptiveFilterOption(a.symbol, a.symbol, tint: Color(a.color)),
];
```

### The filter model (pure data)

```dart
// lib/features/markets/models/market_filter.dart
import 'package:equatable/equatable.dart';

import 'package:native_widgets_on_duo/features/investment/models/asset.dart';
import 'package:native_widgets_on_duo/features/portfolio/models/holdings_filter.dart';

enum MarketMovement { all, gainers, losers }

enum MarketSort { symbol, price, change }

class MarketFilter extends Equatable {
  const MarketFilter({
    this.movement = MarketMovement.all,
    this.sort = MarketSort.symbol,
    this.maxPrice = ceiling,
    this.types = const {},
    this.minChange = floor,
    this.symbols = const {},
  });

  static const double ceiling = 600;
  static const double floor = -5;

  final MarketMovement movement;
  final MarketSort sort;
  final double maxPrice;

  /// Empty means every type.
  final Set<HoldingType> types;
  final double minChange;

  /// Empty means every symbol.
  final Set<String> symbols;

  int get activeCount =>
      (movement != MarketMovement.all ? 1 : 0) +
      (sort != MarketSort.symbol ? 1 : 0) +
      (maxPrice < ceiling ? 1 : 0) +
      (types.isEmpty ? 0 : 1) +
      (minChange > floor ? 1 : 0) +
      (symbols.isEmpty ? 0 : 1);

  MarketFilter copyWith({
    MarketMovement? movement,
    MarketSort? sort,
    double? maxPrice,
    Set<HoldingType>? types,
    double? minChange,
    Set<String>? symbols,
  }) => MarketFilter(
    movement: movement ?? this.movement,
    sort: sort ?? this.sort,
    maxPrice: maxPrice ?? this.maxPrice,
    types: types ?? this.types,
    minChange: minChange ?? this.minChange,
    symbols: symbols ?? this.symbols,
  );

  List<Asset> apply(List<Asset> source) {
    final result = source
        .where(
          (a) =>
              a.price <= maxPrice &&
              a.change >= minChange &&
              (types.isEmpty || types.contains(holdingType(a))) &&
              (symbols.isEmpty || symbols.contains(a.symbol)) &&
              switch (movement) {
                MarketMovement.all => true,
                MarketMovement.gainers => a.change > 0,
                MarketMovement.losers => a.change < 0,
              },
        )
        .toList();
    result.sort(
      (a, b) => switch (sort) {
        MarketSort.symbol => a.symbol.compareTo(b.symbol),
        MarketSort.price => b.price.compareTo(a.price),
        MarketSort.change => b.change.compareTo(a.change),
      },
    );
    return result;
  }

  @override
  List<Object> get props => [
    movement,
    sort,
    maxPrice,
    types,
    minChange,
    symbols,
  ];
}
```

### The sheet description

```dart
// lib/features/markets/view/market_filter_sheet.dart
import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/filtering/filter_values.dart';
import 'package:native_widgets_on_duo/features/investment/data/demo_assets.dart';
import 'package:native_widgets_on_duo/features/markets/models/market_filter.dart';
import 'package:native_widgets_on_duo/features/portfolio/models/holdings_filter.dart';

const _controls = <AdaptiveFilterControl>[
  AdaptiveFilterChoices(
    'movement',
    icon: AdaptiveIcon(
      sfSymbol: 'chart.line.uptrend.xyaxis',
      icon: Icons.trending_up_rounded,
    ),
    layout: AdaptiveFilterLayout.blocks,
    [
      AdaptiveFilterOption(
        'all',
        'All',
        icon: AdaptiveIcon(
          sfSymbol: 'infinity',
          icon: Icons.all_inclusive_rounded,
        ),
      ),
      AdaptiveFilterOption(
        'gainers',
        'Gainers',
        icon: AdaptiveIcon(
          sfSymbol: 'arrow.up.right',
          icon: Icons.north_east_rounded,
        ),
        tint: green,
      ),
      AdaptiveFilterOption(
        'losers',
        'Losers',
        icon: AdaptiveIcon(
          sfSymbol: 'arrow.down.right',
          icon: Icons.south_east_rounded,
        ),
      ),
    ],
  ),
  AdaptiveFilterChoices(
    'sort',
    icon: AdaptiveIcon(
      sfSymbol: 'arrow.up.arrow.down',
      icon: Icons.swap_vert_rounded,
    ),
    [
      AdaptiveFilterOption(
        'symbol',
        'A-Z',
        icon: AdaptiveIcon(
          sfSymbol: 'textformat.abc',
          icon: Icons.sort_by_alpha_rounded,
        ),
      ),
      AdaptiveFilterOption(
        'price',
        'Price',
        icon: AdaptiveIcon(
          sfSymbol: 'dollarsign',
          icon: Icons.attach_money_rounded,
        ),
      ),
      AdaptiveFilterOption(
        'change',
        'Change',
        icon: AdaptiveIcon(sfSymbol: 'percent', icon: Icons.percent_rounded),
      ),
    ],
  ),
  AdaptiveFilterSlider(
    'maxPrice',
    icon: AdaptiveIcon(sfSymbol: 'tag', icon: Icons.sell_outlined),
    min: 100,
    max: MarketFilter.ceiling,
    prefix: 'Up to \$',
    anyLabel: 'Any price',
    anyAtMin: false,
  ),
  AdaptiveFilterChoices(
    'types',
    icon: AdaptiveIcon(
      sfSymbol: 'square.grid.2x2',
      icon: Icons.grid_view_rounded,
    ),
    layout: AdaptiveFilterLayout.blocks,
    multiple: true,
    columns: 2,
    [
      AdaptiveFilterOption(
        'stock',
        'Stocks',
        icon: AdaptiveIcon(
          sfSymbol: 'building.2',
          icon: Icons.business_rounded,
        ),
      ),
      AdaptiveFilterOption(
        'etf',
        'ETFs',
        icon: AdaptiveIcon(
          sfSymbol: 'chart.pie',
          icon: Icons.pie_chart_outline_rounded,
        ),
      ),
    ],
  ),
  AdaptiveFilterSlider(
    'minChange',
    icon: AdaptiveIcon(sfSymbol: 'percent', icon: Icons.percent_rounded),
    min: MarketFilter.floor,
    max: 3,
    prefix: 'Above ',
    suffix: '%',
    decimals: 1,
    anyLabel: 'Any change',
  ),
];

Map<String, Object> _values(MarketFilter f) => {
  'movement': [f.movement.name],
  'sort': [f.sort.name],
  'maxPrice': f.maxPrice,
  'types': [for (final t in f.types) t.name],
  'minChange': f.minChange,
  'symbols': f.symbols.toList(),
};

MarketFilter _filter(Map<String, Object> v) => MarketFilter(
  movement: chosenEnum(v, 'movement', MarketMovement.values),
  sort: chosenEnum(v, 'sort', MarketSort.values),
  maxPrice: v['maxPrice'] as double,
  types: chosenEnums(v, 'types', HoldingType.values),
  minChange: v['minChange'] as double,
  symbols: chosenIds(v, 'symbols').toSet(),
);

/// Shows the market filter sheet and returns the chosen filter.
Future<MarketFilter?> showMarketFilterSheet(
  BuildContext context,
  MarketFilter current,
) async {
  final result = await AdaptiveFilterSheet.show(
    context: context,
    title: 'Filters',
    tint: red,
    controls: [
      ..._controls,
      AdaptiveFilterChoices(
        'symbols',
        icon: AdaptiveIcon(sfSymbol: 'tag.circle', icon: Icons.sell_outlined),
        layout: AdaptiveFilterLayout.swatches,
        multiple: true,
        assetSwatches(assets),
      ),
    ],
    values: _values(current),
    cleared: _values(const MarketFilter()),
    count: (v) => _filter(v).apply(assets).length,
  );
  return result == null ? null : _filter(result);
}
```

### The page

```dart
// lib/features/markets/view/markets_page.dart
import 'package:flutter/material.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/widgets/chart_painter.dart';
import 'package:native_widgets_on_duo/core/widgets/filter_section_header.dart';
import 'package:native_widgets_on_duo/core/widgets/metric.dart';
import 'package:native_widgets_on_duo/core/widgets/page_scroll.dart';
import 'package:native_widgets_on_duo/core/widgets/section.dart';
import 'package:native_widgets_on_duo/features/investment/data/demo_assets.dart';
import 'package:native_widgets_on_duo/features/investment/widgets/asset_row.dart';
import 'package:native_widgets_on_duo/features/markets/models/market_filter.dart';
import 'package:native_widgets_on_duo/features/markets/view/market_filter_sheet.dart';

class Markets extends StatefulWidget {
  const Markets({super.key});
  @override
  State<Markets> createState() => _MarketsState();
}

class _MarketsState extends State<Markets> {
  MarketFilter filter = const MarketFilter();

  Future<void> openFilters() async {
    final result = await showMarketFilterSheet(context, filter);
    if (result != null && mounted) setState(() => filter = result);
  }

  @override
  Widget build(BuildContext context) => PageScroll(
    storageKey: 'markets',
    children: [
      section('Market overview', 'Demo prices'),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(child: metric('S&P 500', '5,892.16')),
          const SizedBox(width: 12),
          Expanded(child: metric('NASDAQ', '18,421.09')),
        ],
      ),
      const SizedBox(height: 22),
      SizedBox(
        height: 150,
        child: CustomPaint(painter: ChartPainter(seed: 7, filled: true)),
      ),
      const SizedBox(height: 24),
      FilterSectionHeader(
        title: 'Explore',
        onPressed: openFilters,
        activeCount: filter.activeCount,
      ),
      const SizedBox(height: 8),
      ...filter.apply(assets).map((a) => AssetRow(asset: a)),
      if (filter.apply(assets).isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Icon(Icons.search_off_rounded, size: 40, color: muted),
        ),
    ],
  );
}
```

### The filter button and section header

```dart
// lib/core/widgets/filter_button.dart
import 'package:flutter/material.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';

/// Opens a filter sheet. Shows how many filters are active.
class FilterButton extends StatelessWidget {
  const FilterButton({
    super.key,
    required this.onPressed,
    this.activeCount = 0,
  });
  final VoidCallback onPressed;
  final int activeCount;

  @override
  Widget build(BuildContext context) {
    final active = activeCount > 0;
    return Semantics(
      button: true,
      label: active ? 'Filters, $activeCount active' : 'Filters',
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Badge(
            isLabelVisible: active,
            label: Text('$activeCount'),
            backgroundColor: red,
            child: Icon(
              Icons.tune_rounded,
              size: 24,
              color: active ? red : ink,
            ),
          ),
        ),
      ),
    );
  }
}
```

```dart
// lib/core/widgets/filter_section_header.dart
import 'package:flutter/material.dart';

import 'package:native_widgets_on_duo/core/widgets/filter_button.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';

/// A page section title with the filter button at its trailing edge.
class FilterSectionHeader extends StatelessWidget {
  const FilterSectionHeader({
    super.key,
    required this.title,
    required this.onPressed,
    required this.activeCount,
  });
  final String title;
  final VoidCallback onPressed;
  final int activeCount;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.centerRight,
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: label(title, size: 20, weight: FontWeight.w600),
        ),
      ),
      FilterButton(onPressed: onPressed, activeCount: activeCount),
    ],
  );
}
```

## Every control layout

The other three pages show the remaining layouts and detents.

### Activity: stack, swatches, strip and a slider

```dart
// lib/features/activity/models/activity_filter.dart
import 'package:equatable/equatable.dart';

import 'package:native_widgets_on_duo/features/investment/models/asset.dart';

enum ActivityKind { all, bought, dividends }

/// How far back to look. The demo rows are one per day, newest first.
enum ActivityPeriod {
  all(12),
  week(7),
  threeDays(3);

  const ActivityPeriod(this.days);
  final int days;
}

class ActivityFilter extends Equatable {
  const ActivityFilter({
    this.kind = ActivityKind.all,
    this.symbols = const {},
    this.period = ActivityPeriod.all,
    this.minAmount = 0,
  });

  static const double maxAmount = 600;

  final ActivityKind kind;

  /// Empty means every symbol.
  final Set<String> symbols;
  final ActivityPeriod period;
  final double minAmount;

  int get activeCount =>
      (kind != ActivityKind.all ? 1 : 0) +
      (symbols.isEmpty ? 0 : 1) +
      (period != ActivityPeriod.all ? 1 : 0) +
      (minAmount > 0 ? 1 : 0);

  ActivityFilter copyWith({
    ActivityKind? kind,
    Set<String>? symbols,
    ActivityPeriod? period,
    double? minAmount,
  }) => ActivityFilter(
    kind: kind ?? this.kind,
    symbols: symbols ?? this.symbols,
    period: period ?? this.period,
    minAmount: minAmount ?? this.minAmount,
  );

  bool allows({
    required bool dividend,
    required String symbol,
    required int day,
    required double amount,
  }) =>
      switch (kind) {
        ActivityKind.all => true,
        ActivityKind.bought => !dividend,
        ActivityKind.dividends => dividend,
      } &&
      (symbols.isEmpty || symbols.contains(symbol)) &&
      day < period.days &&
      amount >= minAmount;

  /// Indices of the demo rows that pass the filter. Every third row is a
  /// VOO dividend; the rest are purchases of the cycling demo assets.
  List<int> matching(List<Asset> assets) => [
    for (var i = 0; i < 12; i++)
      if (allows(
        dividend: i % 3 == 0,
        symbol: i % 3 == 0 ? 'VOO' : assets[i % 6].symbol,
        day: i,
        amount: i % 3 == 0 ? 128.40 : assets[i % 6].price,
      ))
        i,
  ];

  @override
  List<Object> get props => [kind, symbols, period, minAmount];
}
```

```dart
// lib/features/activity/view/activity_filter_sheet.dart
import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/filtering/filter_values.dart';
import 'package:native_widgets_on_duo/features/activity/models/activity_filter.dart';
import 'package:native_widgets_on_duo/features/investment/data/demo_assets.dart';

Map<String, Object> _values(ActivityFilter f) => {
  'kind': [f.kind.name],
  'symbols': f.symbols.toList(),
  'period': [f.period.name],
  'minAmount': f.minAmount,
};

ActivityFilter _filter(Map<String, Object> v) => ActivityFilter(
  kind: chosenEnum(v, 'kind', ActivityKind.values),
  symbols: chosenIds(v, 'symbols').toSet(),
  period: chosenEnum(v, 'period', ActivityPeriod.values),
  minAmount: v['minAmount'] as double,
);

/// Shows the activity filter sheet and returns the chosen filter.
Future<ActivityFilter?> showActivityFilterSheet(
  BuildContext context,
  ActivityFilter current,
) async {
  final result = await AdaptiveFilterSheet.show(
    context: context,
    title: 'Filters',
    tint: red,
    controls: [
      const AdaptiveFilterChoices('kind', layout: AdaptiveFilterLayout.stack, [
        AdaptiveFilterOption(
          'all',
          'All',
          icon: AdaptiveIcon(
            sfSymbol: 'infinity',
            icon: Icons.all_inclusive_rounded,
          ),
        ),
        AdaptiveFilterOption(
          'bought',
          'Bought',
          icon: AdaptiveIcon(
            sfSymbol: 'plus.circle',
            icon: Icons.add_circle_outline_rounded,
          ),
        ),
        AdaptiveFilterOption(
          'dividends',
          'Dividends',
          icon: AdaptiveIcon(
            sfSymbol: 'arrow.down.left',
            icon: Icons.south_west_rounded,
          ),
          tint: green,
        ),
      ]),
      AdaptiveFilterChoices(
        'symbols',
        icon: AdaptiveIcon(sfSymbol: 'tag.circle', icon: Icons.sell_outlined),
        layout: AdaptiveFilterLayout.swatches,
        multiple: true,
        assetSwatches(assets),
      ),
      const AdaptiveFilterChoices(
        'period',
        icon: AdaptiveIcon(
          sfSymbol: 'calendar',
          icon: Icons.calendar_month_outlined,
        ),
        layout: AdaptiveFilterLayout.strip,
        [
          AdaptiveFilterOption(
            'all',
            'Any time',
            icon: AdaptiveIcon(
              sfSymbol: 'infinity',
              icon: Icons.all_inclusive_rounded,
            ),
          ),
          AdaptiveFilterOption(
            'week',
            '7 days',
            icon: AdaptiveIcon(
              sfSymbol: 'calendar',
              icon: Icons.calendar_month_outlined,
            ),
          ),
          AdaptiveFilterOption(
            'threeDays',
            '3 days',
            icon: AdaptiveIcon(sfSymbol: 'clock', icon: Icons.schedule_rounded),
          ),
        ],
      ),
      const AdaptiveFilterSlider(
        'minAmount',
        icon: AdaptiveIcon(sfSymbol: 'banknote', icon: Icons.payments_outlined),
        min: 0,
        max: ActivityFilter.maxAmount,
        prefix: 'Over \$',
        anyLabel: 'Any amount',
      ),
    ],
    values: _values(current),
    cleared: _values(const ActivityFilter()),
    count: (v) => _filter(v).matching(assets).length,
  );
  return result == null ? null : _filter(result);
}
```

### Watchlist: a short sheet

```dart
// lib/features/watchlist/models/watchlist_filter.dart
import 'package:equatable/equatable.dart';

import 'package:native_widgets_on_duo/features/investment/models/asset.dart';
import 'package:native_widgets_on_duo/features/markets/models/market_filter.dart';

class WatchlistFilter extends Equatable {
  const WatchlistFilter({this.movement = MarketMovement.all});
  final MarketMovement movement;

  int get activeCount => movement == MarketMovement.all ? 0 : 1;

  bool allows(Asset a) => switch (movement) {
    MarketMovement.all => true,
    MarketMovement.gainers => a.change > 0,
    MarketMovement.losers => a.change < 0,
  };

  @override
  List<Object> get props => [movement];
}
```

```dart
// lib/features/watchlist/view/watchlist_filter_sheet.dart
import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/filtering/filter_values.dart';
import 'package:native_widgets_on_duo/features/investment/data/demo_assets.dart';
import 'package:native_widgets_on_duo/features/markets/models/market_filter.dart';
import 'package:native_widgets_on_duo/features/watchlist/models/watchlist_filter.dart';

Map<String, Object> _values(WatchlistFilter f) => {
  'movement': [f.movement.name],
};

WatchlistFilter _filter(Map<String, Object> v) =>
    WatchlistFilter(movement: chosenEnum(v, 'movement', MarketMovement.values));

/// A short sheet with a single control.
Future<WatchlistFilter?> showWatchlistFilterSheet(
  BuildContext context,
  WatchlistFilter current,
) async {
  final result = await AdaptiveFilterSheet.show(
    context: context,
    title: 'Filters',
    tint: red,
    detents: AdaptiveFilterDetents.short,
    controls: const [
      AdaptiveFilterChoices(
        'movement',
        icon: AdaptiveIcon(
          sfSymbol: 'chart.line.uptrend.xyaxis',
          icon: Icons.trending_up_rounded,
        ),
        layout: AdaptiveFilterLayout.blocks,
        [
          AdaptiveFilterOption(
            'all',
            'All',
            icon: AdaptiveIcon(
              sfSymbol: 'infinity',
              icon: Icons.all_inclusive_rounded,
            ),
          ),
          AdaptiveFilterOption(
            'gainers',
            'Gainers',
            icon: AdaptiveIcon(
              sfSymbol: 'arrow.up.right',
              icon: Icons.north_east_rounded,
            ),
            tint: green,
          ),
          AdaptiveFilterOption(
            'losers',
            'Losers',
            icon: AdaptiveIcon(
              sfSymbol: 'arrow.down.right',
              icon: Icons.south_east_rounded,
            ),
          ),
        ],
      ),
    ],
    values: _values(current),
    cleared: _values(const WatchlistFilter()),
    count: (v) => assets.where(_filter(v).allows).length,
  );
  return result == null ? null : _filter(result);
}
```

### Portfolio holdings: a full-height sheet

```dart
// lib/features/portfolio/models/holdings_filter.dart
import 'package:equatable/equatable.dart';

import 'package:native_widgets_on_duo/features/investment/models/asset.dart';
import 'package:native_widgets_on_duo/features/markets/models/market_filter.dart';

enum HoldingsSort { value, change, symbol }

enum HoldingType { stock, etf }

const _etfs = {'VOO', 'VTI'};

HoldingType holdingType(Asset a) =>
    _etfs.contains(a.symbol) ? HoldingType.etf : HoldingType.stock;

class HoldingsFilter extends Equatable {
  const HoldingsFilter({
    this.sort = HoldingsSort.value,
    this.movement = MarketMovement.all,
    this.types = const {},
    this.symbols = const {},
    this.minValue = 0,
    this.minChange = floor,
  });

  static const double floor = -5;
  static const double maxValue = 50000;

  final HoldingsSort sort;
  final MarketMovement movement;

  /// Empty means every type.
  final Set<HoldingType> types;

  /// Empty means every symbol.
  final Set<String> symbols;
  final double minValue;
  final double minChange;

  int get activeCount =>
      (sort != HoldingsSort.value ? 1 : 0) +
      (movement != MarketMovement.all ? 1 : 0) +
      (types.isEmpty ? 0 : 1) +
      (symbols.isEmpty ? 0 : 1) +
      (minValue > 0 ? 1 : 0) +
      (minChange > floor ? 1 : 0);

  HoldingsFilter copyWith({
    HoldingsSort? sort,
    MarketMovement? movement,
    Set<HoldingType>? types,
    Set<String>? symbols,
    double? minValue,
    double? minChange,
  }) => HoldingsFilter(
    sort: sort ?? this.sort,
    movement: movement ?? this.movement,
    types: types ?? this.types,
    symbols: symbols ?? this.symbols,
    minValue: minValue ?? this.minValue,
    minChange: minChange ?? this.minChange,
  );

  List<Asset> apply(List<Asset> source, double scale) {
    double value(Asset a) => a.price * a.shares * scale;
    final result = source
        .where(
          (a) =>
              value(a) >= minValue &&
              a.change >= minChange &&
              (types.isEmpty || types.contains(holdingType(a))) &&
              (symbols.isEmpty || symbols.contains(a.symbol)) &&
              switch (movement) {
                MarketMovement.all => true,
                MarketMovement.gainers => a.change > 0,
                MarketMovement.losers => a.change < 0,
              },
        )
        .toList();
    result.sort(
      (a, b) => switch (sort) {
        HoldingsSort.value => value(b).compareTo(value(a)),
        HoldingsSort.change => b.change.compareTo(a.change),
        HoldingsSort.symbol => a.symbol.compareTo(b.symbol),
      },
    );
    return result;
  }

  @override
  List<Object> get props => [
    sort,
    movement,
    types,
    symbols,
    minValue,
    minChange,
  ];
}
```

```dart
// lib/features/portfolio/view/holdings_filter_sheet.dart
import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/filtering/filter_values.dart';
import 'package:native_widgets_on_duo/features/investment/data/demo_assets.dart';
import 'package:native_widgets_on_duo/features/markets/models/market_filter.dart';
import 'package:native_widgets_on_duo/features/portfolio/models/holdings_filter.dart';

Map<String, Object> _values(HoldingsFilter f) => {
  'sort': [f.sort.name],
  'movement': [f.movement.name],
  'types': [for (final t in f.types) t.name],
  'minValue': f.minValue,
  'minChange': f.minChange,
  'symbols': f.symbols.toList(),
};

HoldingsFilter _filter(Map<String, Object> v) => HoldingsFilter(
  sort: chosenEnum(v, 'sort', HoldingsSort.values),
  movement: chosenEnum(v, 'movement', MarketMovement.values),
  types: chosenEnums(v, 'types', HoldingType.values),
  minValue: v['minValue'] as double,
  minChange: v['minChange'] as double,
  symbols: chosenIds(v, 'symbols').toSet(),
);

/// A very long sheet: full height only. [scale] is the selected account's
/// share of the demo holdings.
Future<HoldingsFilter?> showHoldingsFilterSheet(
  BuildContext context,
  HoldingsFilter current, {
  required double scale,
}) async {
  final result = await AdaptiveFilterSheet.show(
    context: context,
    title: 'Filters',
    tint: red,
    detents: AdaptiveFilterDetents.full,
    controls: [
      const AdaptiveFilterChoices(
        'sort',
        icon: AdaptiveIcon(
          sfSymbol: 'arrow.up.arrow.down',
          icon: Icons.swap_vert_rounded,
        ),
        layout: AdaptiveFilterLayout.strip,
        [
          AdaptiveFilterOption(
            'value',
            'Value',
            icon: AdaptiveIcon(
              sfSymbol: 'wallet.bifold',
              icon: Icons.account_balance_wallet_outlined,
            ),
          ),
          AdaptiveFilterOption(
            'change',
            'Change',
            icon: AdaptiveIcon(
              sfSymbol: 'percent',
              icon: Icons.percent_rounded,
            ),
          ),
          AdaptiveFilterOption(
            'symbol',
            'A-Z',
            icon: AdaptiveIcon(
              sfSymbol: 'textformat.abc',
              icon: Icons.sort_by_alpha_rounded,
            ),
          ),
        ],
      ),
      const AdaptiveFilterChoices(
        'movement',
        layout: AdaptiveFilterLayout.stack,
        [
          AdaptiveFilterOption(
            'all',
            'All',
            icon: AdaptiveIcon(
              sfSymbol: 'infinity',
              icon: Icons.all_inclusive_rounded,
            ),
          ),
          AdaptiveFilterOption(
            'gainers',
            'Gainers',
            icon: AdaptiveIcon(
              sfSymbol: 'arrow.up.right',
              icon: Icons.north_east_rounded,
            ),
            tint: green,
          ),
          AdaptiveFilterOption(
            'losers',
            'Losers',
            icon: AdaptiveIcon(
              sfSymbol: 'arrow.down.right',
              icon: Icons.south_east_rounded,
            ),
          ),
        ],
      ),
      const AdaptiveFilterChoices(
        'types',
        icon: AdaptiveIcon(
          sfSymbol: 'square.grid.2x2',
          icon: Icons.grid_view_rounded,
        ),
        layout: AdaptiveFilterLayout.blocks,
        multiple: true,
        columns: 2,
        [
          AdaptiveFilterOption(
            'stock',
            'Stocks',
            icon: AdaptiveIcon(
              sfSymbol: 'building.2',
              icon: Icons.business_rounded,
            ),
          ),
          AdaptiveFilterOption(
            'etf',
            'ETFs',
            icon: AdaptiveIcon(
              sfSymbol: 'chart.pie',
              icon: Icons.pie_chart_outline_rounded,
            ),
          ),
        ],
      ),
      const AdaptiveFilterSlider(
        'minValue',
        icon: AdaptiveIcon(sfSymbol: 'banknote', icon: Icons.payments_outlined),
        min: 0,
        max: HoldingsFilter.maxValue,
        prefix: 'Over \$',
        anyLabel: 'Any size',
      ),
      const AdaptiveFilterSlider(
        'minChange',
        icon: AdaptiveIcon(sfSymbol: 'percent', icon: Icons.percent_rounded),
        min: HoldingsFilter.floor,
        max: 3,
        prefix: 'Above ',
        suffix: '%',
        decimals: 1,
        anyLabel: 'Any change',
      ),
      AdaptiveFilterChoices(
        'symbols',
        icon: AdaptiveIcon(sfSymbol: 'tag.circle', icon: Icons.sell_outlined),
        layout: AdaptiveFilterLayout.swatches,
        multiple: true,
        assetSwatches(assets),
      ),
    ],
    values: _values(current),
    cleared: _values(const HoldingsFilter()),
    count: (v) => _filter(v).apply(assets, scale).length,
  );
  return result == null ? null : _filter(result);
}
```

## Problems found while testing, and the fixes

| Symptom | Cause | Fix |
|---|---|---|
| Sheet did not open on the iPhone Duo; the button showed a touch ripple and nothing happened | The Duo screen is short, so a half and an expanded height both clamped to the same cap and tripped an assertion that required the expanded height to be larger | Relaxed the assertion to allow equal heights |
| Asset discs rendered as squashed pills | The flow layout set button frames while fixed-size constraints fought them | `SwatchButton` reports a fixed `intrinsicContentSize`, and `FilterFlowView` measures children by intrinsic size |
| Unselected colour blocks vanished on a white band | Blocks and band were both white | Unselected tile colour is darker than both band tones |
| Block grid overflowed by 6 px on a 320 px screen | Fixed aspect ratio gave too little height for icon and label | Aspect ratio comes from cell width, clamped so the height never drops below the content |
| Android sheet stopped above the bottom bar | It opened in the nested navigator of the shell | `showModalBottomSheet(useRootNavigator: true)` |
| Android full-height sheet would not scroll | A `DraggableScrollableSheet` with equal min and max sizes treats an upward drag as a resize that cannot happen, so the list never scrolls | Single-detent sheets use a fixed-height `FractionallySizedBox` instead |
| `Set.remove` used as a boolean in Swift failed to compile | It returns the removed element | Check `contains` first |
| Taps on the Duo simulator missed their target | The simulator had rotated to portrait | Re-read the screenshot orientation before computing tap points |

## How it was tested

Static checks:

```sh
flutter analyze lib packages/adaptive_platform_ui/lib
```

Widget tests with a real font (the default test font is wide enough to cause false
overflows) at five sizes, plus 1.8x text scale. The sheet is opened, options are tapped,
the count and the applied list are asserted. Load Roboto from the Flutter SDK:

```dart
Future<void> loadFonts() async {
  final loader = FontLoader('Roboto');
  for (final f in ['Regular', 'Medium', 'Bold']) {
    final bytes = File(
      '<flutter-sdk>/bin/cache/artifacts/material_fonts/Roboto-$f.ttf',
    ).readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}
```

Real devices:

* iPhone simulators (iPhone Duo on iOS 27.1, iPhone 17 Pro on iOS 26.2 and 27.0) built
  and launched with XcodeBuildMCP, driven with the simulator control tool and checked
  with `snapshot_ui`, which lists buttons and the live count text.
* Android emulators (API 35 and API 37):

```sh
export PATH=$PATH:$HOME/Library/Android/sdk/platform-tools:$HOME/Library/Android/sdk/emulator
emulator -avd Medium_Phone_API_35 -no-snapshot-save -no-audio &
flutter run -d emulator-5554 --debug
adb -s emulator-5554 shell input tap 964 792
adb -s emulator-5554 shell input swipe 540 1500 540 300 400
adb -s emulator-5554 exec-out screencap -p > shot.png
```

Android screenshot coordinates are in physical pixels (1080 by 2400 on both emulators).

## Adding a filter sheet to a new page

1. Write a pure data filter model with `activeCount`, `copyWith`, and an `apply` (or
   equivalent) that returns the filtered items. Extend `Equatable` so reset detection
   works.
2. Write `show<Name>FilterSheet(BuildContext, <Name>Filter)` that maps the model to and
   from the values map, describes the controls with an `AdaptiveIcon` (SF Symbol plus
   Material icon) on each, and passes `count: (v) => _filter(v).apply(items).length`.
3. In the page state, keep the filter, call the show function from `openFilters`, and
   rebuild with the result when it is not `null`.
4. Put `FilterSectionHeader(title: ..., onPressed: openFilters, activeCount: filter.activeCount)`
   where the filter button should appear.

Pick the layout per control: `segmented` for two or three exclusive choices, `blocks`
for a grid of icon tiles, `stack` for tall bands, `chips` or `strip` for pills,
`swatches` for coloured discs, and `AdaptiveFilterSlider` for a numeric limit.
