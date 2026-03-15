// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

Future<void> exportCsvBytes({
  required List<int> bytes,
  required String fileName,
}) async {
  final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);

  final anchor = html.AnchorElement(href: url)..download = fileName;
  anchor.click();

  html.Url.revokeObjectUrl(url);
}

Future<void> printPageIfSupported() async {
  html.window.print();
}
