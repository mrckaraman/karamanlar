import 'dart:typed_data';

import 'package:printing/printing.dart';

Future<void> saveAndSharePdfImpl(
  Uint8List bytes,
  String filename, {
  String? subject,
  String? text,
}) async {
  // Web ve IO-dışı platformlarda: yazdır/indir diyalogu aç.
  await Printing.layoutPdf(
    onLayout: (_) async => bytes,
  );
}
