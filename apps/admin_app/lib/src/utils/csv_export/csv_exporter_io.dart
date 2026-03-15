import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> exportCsvBytes({
  required List<int> bytes,
  required String fileName,
}) async {
  final directory = await getTemporaryDirectory();
  final filePath = '${directory.path}${Platform.pathSeparator}$fileName';
  final file = File(filePath);

  await file.writeAsBytes(bytes, flush: true);

  final xFile = XFile(file.path, mimeType: 'text/csv');
  await Share.shareXFiles(
    [xFile],
    subject: fileName,
    text: 'CSV raporu ektedir.',
  );
}

Future<void> printPageIfSupported() async {
  // Mobil/desktop için şu an destek yok.
}
