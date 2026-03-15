import 'dart:typed_data';

import 'package:flutter/material.dart';

Future<void> platformSaveBytesAsFile(
  Uint8List bytes,
  String filename,
  String mimeType,
  BuildContext context,
) async {
  // Desktop/mobile stub: just inform the user for now.
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Dosya indirme şimdilik web için tam destekleniyor.'),
    ),
  );
}
