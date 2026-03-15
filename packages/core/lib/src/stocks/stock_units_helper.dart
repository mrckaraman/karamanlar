import 'package:flutter/foundation.dart';

class UnitOption {
  const UnitOption({
    required this.code,
    required this.name,
    required this.multiplier,
  });

  final String code; // 'piece' | 'pack' | 'box'
  final String name;
  final num multiplier;

  String get label => '$name (${multiplier.toString()} adet)';

  @override
  String toString() => 'UnitOption(code: $code, name: $name, multiplier: $multiplier)';
}

List<UnitOption> buildUnitOptions({
  required String baseUnitName,
  required num baseMultiplier,
  String? packUnitName,
  num? packMultiplier,
  String? boxUnitName,
  num? boxMultiplier,
  String? stockId,
}) {
  final options = <UnitOption>[
    UnitOption(
      code: 'piece',
      name: baseUnitName,
      multiplier: baseMultiplier,
    ),
  ];

  if (packMultiplier != null && packMultiplier > 0) {
    options.add(
      UnitOption(
        code: 'pack',
        name: packUnitName ?? 'paket',
        multiplier: packMultiplier,
      ),
    );
  }

  if (boxMultiplier != null && boxMultiplier > 0) {
    options.add(
      UnitOption(
        code: 'box',
        name: boxUnitName ?? 'koli',
        multiplier: boxMultiplier,
      ),
    );
  }

  if (kDebugMode) {
    debugPrint(
      '[UNIT] stockId=$stockId packQty=$packMultiplier boxQty=$boxMultiplier packName=$packUnitName boxName=$boxUnitName options=$options',
    );
  }

  return options;
}
