import 'package:flutter/material.dart';

/// App bar title in the app's own typeface. It is a plain `Text` so the native
/// bar can draw it itself.
Text barTitle(String text) => Text(
  text,
  style: const TextStyle(
    fontFamily: 'Arial Rounded MT Bold',
    fontSize: 22,
    color: Colors.white,
  ),
);
