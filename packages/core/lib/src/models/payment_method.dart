import 'package:flutter/foundation.dart';

enum PaymentMethod { cash, card, transfer, check }

extension PaymentMethodX on PaymentMethod {
  String get dbValue {
    switch (this) {
      case PaymentMethod.cash:
        return 'cash';
      case PaymentMethod.card:
        return 'card';
      case PaymentMethod.transfer:
        return 'transfer';
      case PaymentMethod.check:
        return 'check';
    }
  }

  String get labelTr {
    switch (this) {
      case PaymentMethod.cash:
        return 'Nakit';
      case PaymentMethod.card:
        return 'Kart';
      case PaymentMethod.transfer:
        return 'Havale-EFT';
      case PaymentMethod.check:
        return 'Çek';
    }
  }

  static PaymentMethod fromDb(String value) {
    switch (value) {
      case 'cash':
        return PaymentMethod.cash;
      case 'card':
        return PaymentMethod.card;
      case 'transfer':
        return PaymentMethod.transfer;
      case 'check':
        return PaymentMethod.check;
      default:
        if (kDebugMode) {
          debugPrint('[PaymentMethod] Unknown db value: $value, fallback=cash');
        }
        return PaymentMethod.cash;
    }
  }
}
