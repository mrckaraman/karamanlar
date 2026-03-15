import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

class PdfFonts {
  PdfFonts._();

  static pw.Font? _regular;
  static pw.Font? _bold;

  static Future<pw.Font> regular() async {
    final cached = _regular;
    if (cached != null) return cached;

    final data = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    final font = pw.Font.ttf(data);
    _regular = font;
    return font;
  }

  static Future<pw.Font> bold() async {
    final cached = _bold;
    if (cached != null) return cached;

    final data = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    final font = pw.Font.ttf(data);
    _bold = font;
    return font;
  }

  static Future<pw.ThemeData> theme() async {
    final base = await regular();
    final boldFont = await PdfFonts.bold();
    return pw.ThemeData.withFont(base: base, bold: boldFont);
  }
}
