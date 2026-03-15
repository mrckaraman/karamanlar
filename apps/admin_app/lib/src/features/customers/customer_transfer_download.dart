import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'customer_transfer_download_stub.dart'
    if (dart.library.html) 'customer_transfer_download_web.dart';

Future<void> saveBytesAsFile(
  Uint8List bytes,
  String filename,
  String mimeType,
  BuildContext context,
) {
  return platformSaveBytesAsFile(bytes, filename, mimeType, context);
}
