import 'package:intl/intl.dart';

final NumberFormat _trCurrency = NumberFormat.currency(
  locale: 'tr_TR',
  symbol: '₺',
  decimalDigits: 2,
);

final DateFormat _trDate = DateFormat('dd.MM.yyyy', 'tr_TR');
final DateFormat _trDateTime = DateFormat('dd.MM.yyyy HH:mm', 'tr_TR');

final NumberFormat _trQty = NumberFormat.decimalPattern('tr_TR')
  ..minimumFractionDigits = 0
  ..maximumFractionDigits = 3;

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

String formatQtyTr(num? value) {
  if (value == null) return '-';

  final doubleVal = value.toDouble();
  // Tam sayı ise küsurat gösterme
  if (doubleVal == doubleVal.roundToDouble()) {
    return _trQty.format(doubleVal.toInt());
  }

  return _trQty.format(doubleVal);
}
