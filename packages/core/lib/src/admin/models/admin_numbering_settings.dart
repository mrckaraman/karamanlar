enum AdminNumberingResetPolicy { never, yearly }

extension AdminNumberingResetPolicyX on AdminNumberingResetPolicy {
  String get key {
    switch (this) {
      case AdminNumberingResetPolicy.never:
        return 'never';
      case AdminNumberingResetPolicy.yearly:
        return 'yearly';
    }
  }

  static AdminNumberingResetPolicy fromKey(String? value) {
    switch (value) {
      case 'yearly':
        return AdminNumberingResetPolicy.yearly;
      case 'never':
      default:
        return AdminNumberingResetPolicy.never;
    }
  }
}

class AdminNumberingConfig {
  const AdminNumberingConfig({
    required this.key,
    required this.prefix,
    required this.padding,
    required this.nextNumber,
    required this.includeYear,
    required this.separator,
    required this.resetPolicy,
  });

  final String key; // 'order' | 'invoice'
  final String prefix;
  final int padding;
  final int nextNumber;
  final bool includeYear;
  final String separator; // '-' or '/'
  final AdminNumberingResetPolicy resetPolicy;

  AdminNumberingConfig copyWith({
    String? key,
    String? prefix,
    int? padding,
    int? nextNumber,
    bool? includeYear,
    String? separator,
    AdminNumberingResetPolicy? resetPolicy,
  }) {
    return AdminNumberingConfig(
      key: key ?? this.key,
      prefix: prefix ?? this.prefix,
      padding: padding ?? this.padding,
      nextNumber: nextNumber ?? this.nextNumber,
      includeYear: includeYear ?? this.includeYear,
      separator: separator ?? this.separator,
      resetPolicy: resetPolicy ?? this.resetPolicy,
    );
  }

  factory AdminNumberingConfig.fromMap(Map<String, dynamic> map) {
    final key = (map['key'] as String?) ?? '';
    final prefix = (map['prefix'] as String?) ?? '';
    final padding = (map['padding'] as int?) ??
        (map['padding'] as num?)?.toInt() ?? 6;
    final nextNumber = (map['next_number'] as int?) ??
        (map['next_number'] as num?)?.toInt() ?? 1;
    final includeYear = (map['include_year'] as bool?) ?? true;
    final separator = (map['separator'] as String?) ?? '-';
    final resetPolicyKey = map['reset_policy'] as String?;

    return AdminNumberingConfig(
      key: key,
      prefix: prefix,
      padding: padding,
      nextNumber: nextNumber,
      includeYear: includeYear,
      separator: separator,
      resetPolicy:
          AdminNumberingResetPolicyX.fromKey(resetPolicyKey),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'key': key,
      'prefix': prefix,
      'padding': padding,
      'next_number': nextNumber,
      'include_year': includeYear,
      'separator': separator,
      'reset_policy': resetPolicy.key,
    };
  }
}

class AdminNumberingSettings {
  const AdminNumberingSettings({
    required this.order,
    required this.invoice,
  });

  final AdminNumberingConfig order;
  final AdminNumberingConfig invoice;

  factory AdminNumberingSettings.defaults() {
    return AdminNumberingSettings(
      order: AdminNumberingConfig(
        key: 'order',
        prefix: 'SIP',
        padding: 6,
        nextNumber: 1,
        includeYear: true,
        separator: '-',
        resetPolicy: AdminNumberingResetPolicy.yearly,
      ),
      invoice: AdminNumberingConfig(
        key: 'invoice',
        prefix: 'FTR',
        padding: 6,
        nextNumber: 1,
        includeYear: true,
        separator: '-',
        resetPolicy: AdminNumberingResetPolicy.yearly,
      ),
    );
  }
}
