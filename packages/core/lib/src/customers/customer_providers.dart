import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'customer_repository.dart';

/// Riverpod provider sarmalayıcısı; admin ve customer uygulamaları
/// CustomerRepository erişimini standart bir desenle kullanabilir.
final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return customerRepository;
});
