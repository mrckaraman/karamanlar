Future<void> exportCsvBytes({
  required List<int> bytes,
  required String fileName,
}) async {
  throw UnsupportedError('CSV export is not supported on this platform.');
}

Future<void> printPageIfSupported() async {
  // No-op on unsupported platforms.
}
