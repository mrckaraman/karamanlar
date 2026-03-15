import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

class PdfFontBundle {
  const PdfFontBundle({
    required this.regular,
    required this.bold,
  });

  final pw.Font regular;
  final pw.Font bold;
}

class PdfFonts {
  static Future<PdfFontBundle>? _cache;

  static Future<PdfFontBundle> load() {
    return _cache ??= _loadInternal();
  }

  static Future<PdfFontBundle> _loadInternal() async {
    final regularData = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');

    return PdfFontBundle(
      regular: pw.Font.ttf(regularData),
      bold: pw.Font.ttf(boldData),
    );
  }
}
