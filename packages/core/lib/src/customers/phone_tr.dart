const String trCountryCodeE164 = '+90';

/// Normalizes a Turkish GSM number to E.164 format: `+90XXXXXXXXXX`.
///
/// Accepts input in common forms like:
/// - `+905334464480`
/// - `905334464480`
/// - `05334464480`
/// - `5334464480`
///
/// Any non-digit characters (spaces, parentheses, dashes) are stripped
/// before validation.
///
/// Throws [ArgumentError] if the result is not a 10-digit GSM number
/// starting with `5`.
String normalizeTrPhone(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');

  if (digits.isEmpty) {
    throw ArgumentError('Telefon numarası zorunludur.');
  }

  // Convert common Turkish formats to local 10-digit GSM.
  // +905XXXXXXXXX / 905XXXXXXXXX
  if (digits.startsWith('90') && digits.length == 12) {
    digits = digits.substring(2);
  }
  // 0XXXXXXXXXX
  else if (digits.startsWith('0') && digits.length == 11) {
    digits = digits.substring(1);
  }

  if (digits.length != 10) {
    throw ArgumentError('Telefon numarası 10 haneli GSM olmalıdır.');
  }
  if (!digits.startsWith('5')) {
    throw ArgumentError('Telefon numarası 5 ile başlamalıdır.');
  }

  return '$trCountryCodeE164$digits';
}

/// Parses a stored Turkish phone number and returns the local 10-digit part
/// (for example `5334464480`).
///
/// Accepts values in forms like:
/// - `+905334464480`
/// - `905334464480`
/// - `05334464480`
/// - `5334464480`
///
/// Returns `null` if the input cannot be normalized to a valid GSM local part.
String? parseTrPhoneLocalPart(String? stored) {
  if (stored == null) return null;
  var digits = stored.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;

  if (digits.startsWith('90') && digits.length >= 12) {
    digits = digits.substring(2);
  } else if (digits.startsWith('0') && digits.length >= 11) {
    digits = digits.substring(1);
  }

  if (digits.length != 10) {
    return null;
  }
  if (!digits.startsWith('5')) {
    return null;
  }

  return digits;
}
