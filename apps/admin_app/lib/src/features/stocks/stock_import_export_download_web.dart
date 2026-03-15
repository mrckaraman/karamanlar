// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
// ignore: deprecated_member_use
import 'dart:html' as html;

Future<bool> saveBytesFile(
  String fileName,
  List<int> bytes, {
  String? mimeType,
}) async {
  final blob = html.Blob([bytes], mimeType ?? 'application/octet-stream');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
  return true;
}

Future<bool> saveCsvFile(String fileName, String content) async {
  return saveBytesFile(
    fileName,
    utf8.encode(content),
    mimeType: 'text/csv',
  );
}
