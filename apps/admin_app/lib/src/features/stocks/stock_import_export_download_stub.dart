import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<bool> saveBytesFile(
  String fileName,
  List<int> bytes, {
  String? mimeType,
}) async {
  try {
    // Desktop: let user pick a save location.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final ext = p.extension(fileName).replaceFirst('.', '');
      final allowedExt = ext.isEmpty ? const <String>[] : <String>[ext];
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Dosya kaydet',
        fileName: fileName,
        type: allowedExt.isEmpty ? FileType.any : FileType.custom,
        allowedExtensions: allowedExt.isEmpty ? null : allowedExt,
      );
      if (path == null) return false;
      await File(path).writeAsBytes(bytes, flush: true);

      final result = await OpenFilex.open(path, type: mimeType);
      return result.type == ResultType.done;
    }

    // Mobile: write file then open it.
    Directory dir;
    if (Platform.isAndroid) {
      dir = (await getExternalStorageDirectory()) ??
          await getApplicationDocumentsDirectory();
    } else if (Platform.isIOS) {
      dir = await getApplicationDocumentsDirectory();
    } else {
      dir = await getTemporaryDirectory();
    }

    final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File('${dir.path}${Platform.pathSeparator}$safeName');
    await file.writeAsBytes(bytes, flush: true);

    // Excel-first: try Excel-friendly MIME types.
    if (mimeType != null) {
      final direct = await OpenFilex.open(file.path, type: mimeType);
      if (direct.type == ResultType.done) return true;
    }

    final resultExcel = await OpenFilex.open(
      file.path,
      type: 'application/vnd.ms-excel',
    );
    if (resultExcel.type == ResultType.done) return true;

    final resultXlsx = await OpenFilex.open(
      file.path,
      type:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    if (resultXlsx.type == ResultType.done) return true;

    final resultCsv = await OpenFilex.open(
      file.path,
      type: 'text/csv',
    );
    if (resultCsv.type == ResultType.done) return true;

    final resultPlain = await OpenFilex.open(
      file.path,
      type: 'text/plain',
    );
    return resultPlain.type == ResultType.done;
  } catch (_) {
    return false;
  }
}

Future<bool> saveCsvFile(String fileName, String content) async {
  return saveBytesFile(
    fileName,
    utf8.encode(content),
    mimeType: 'text/csv',
  );
}
