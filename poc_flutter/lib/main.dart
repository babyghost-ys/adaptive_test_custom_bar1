import 'package:flutter/material.dart';

void main() => runApp(const SheetRotationApp());

class SheetRotationApp extends StatelessWidget {
  const SheetRotationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sheet Rotation',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: const SheetRotationPage(),
    );
  }
}

class SheetRotationPage extends StatelessWidget {
  const SheetRotationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sheet Rotation')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final item in const ['First', 'Second', 'Third'])
            ListTile(title: Text(item)),
          const SizedBox(height: 16),
          Center(
            child: FilledButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (sheetContext) => SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Short Sheet',
                                style: Theme.of(sheetContext)
                                    .textTheme
                                    .titleLarge,
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(sheetContext).pop(),
                              child: const Text('Done'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Rotate your device while this sheet is open.',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              child: const Text('Open Sheet'),
            ),
          ),
        ],
      ),
    );
  }
}
