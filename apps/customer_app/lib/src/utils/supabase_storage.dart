import 'package:core/core.dart';

/// `stocks/<uuid>.png` gibi relative image path'ten
/// Supabase Storage public URL üretir.
///
/// Hata durumunda veya boş/null path'te null döner.
String? mapStockImagePathToPublicUrl(String? imagePath) {
  final raw = imagePath?.trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }

  try {
    final url = supabaseClient
        .storage
        .from(kStockImagesBucketId)
        .getPublicUrl(raw);

    if (url.isEmpty) {
      return null;
    }

    return url;
  } catch (_) {
    // Supabase henüz init edilmediyse veya başka bir hata varsa
    // null dönerek UI'da placeholder gösterilmesini sağlar.
    return null;
  }
}

/// `image_path` için signed URL üretir.
///
/// Bucket private ise (ve policy izin veriyorsa) bu URL ile görsel
/// görüntülenebilir. Hata durumunda null döner.
Future<String?> createStockImageSignedUrl(
  String? imagePath, {
  Duration expiresIn = const Duration(hours: 1),
}) async {
  final raw = imagePath?.trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }

  try {
    final url = await supabaseClient
        .storage
        .from(kStockImagesBucketId)
        .createSignedUrl(raw, expiresIn.inSeconds);
    if (url.isEmpty) return null;
    return url;
  } catch (_) {
    return null;
  }
}
