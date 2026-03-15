import 'dart:typed_data';

import 'pdf_share_stub.dart'
    if (dart.library.io) 'pdf_share_io.dart';

Future<void> saveAndSharePdf(
  Uint8List bytes,
  String filename, {
  String? subject,
  String? text,
}) {
  return saveAndSharePdfImpl(
    bytes,
    filename,
    subject: subject,
    text: text,
  );
}
