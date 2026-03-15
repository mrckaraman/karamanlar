import 'package:intl/intl.dart';

final NumberFormat _trCurrency = NumberFormat.currency(
  locale: 'tr_TR',
  symbol: '₺',
  decimalDigits: 2,
);

final DateFormat _trDate = DateFormat('dd.MM.yyyy', 'tr_TR');
final DateFormat _trDateTime = DateFormat('dd.MM.yyyy HH:mm', 'tr_TR');

String formatMoney(num? value) {
  if (value == null) return '-';
  return _trCurrency.format(value);
}

String formatDate(DateTime? dt) {
  if (dt == null) return '-';
  return _trDate.format(dt);
}

String formatDateTime(DateTime? dt) {
  if (dt == null) return '-';
  return _trDateTime.format(dt.toLocal());
}
