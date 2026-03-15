// Shared filter models for customer reports.
// Kept free of Riverpod/repository imports to avoid import cycles.

enum BalanceStatusFilter { all, debitOnly, creditOnly }

class BalanceReportFilters {
  const BalanceReportFilters({
    this.status = BalanceStatusFilter.all,
    this.minAbsNet = 0,
    this.groupName,
    this.subGroup,
    this.altGroup,
    this.marketerName,
    this.search = '',
  });

  final BalanceStatusFilter status;
  final double minAbsNet;
  final String? groupName;
  final String? subGroup;
  final String? altGroup;
  final String? marketerName;
  final String search;

  BalanceReportFilters copyWith({
    BalanceStatusFilter? status,
    double? minAbsNet,
    String? groupName,
    String? subGroup,
    String? altGroup,
    String? marketerName,
    String? search,
    bool clearGroupName = false,
    bool clearSubGroup = false,
    bool clearAltGroup = false,
    bool clearMarketer = false,
  }) {
    return BalanceReportFilters(
      status: status ?? this.status,
      minAbsNet: minAbsNet ?? this.minAbsNet,
      groupName: clearGroupName ? null : (groupName ?? this.groupName),
      subGroup: clearSubGroup ? null : (subGroup ?? this.subGroup),
      altGroup: clearAltGroup ? null : (altGroup ?? this.altGroup),
      marketerName: clearMarketer ? null : (marketerName ?? this.marketerName),
      search: search ?? this.search,
    );
  }

  String get statusRpc => switch (status) {
        BalanceStatusFilter.all => 'all',
        BalanceStatusFilter.debitOnly => 'debitOnly',
        BalanceStatusFilter.creditOnly => 'creditOnly',
      };

  String get statusLabel => switch (status) {
        BalanceStatusFilter.all => 'Tümü',
        BalanceStatusFilter.debitOnly => 'Sadece borçlu',
        BalanceStatusFilter.creditOnly => 'Sadece alacaklı',
      };
}

class BalanceReportNormalizedFilters {
  const BalanceReportNormalizedFilters({
    required this.minAbsNet,
    required this.status,
    required this.groupName,
    required this.subGroup,
    required this.altGroup,
    required this.marketerName,
    required this.search,
  });

  /// `null` means "no minimum".
  final double? minAbsNet;

  /// `null` means "all".
  /// Supported values: `debt`, `credit`.
  final String? status;

  final String? groupName;
  final String? subGroup;
  final String? altGroup;
  final String? marketerName;
  final String? search;

  static String? _normalizeText(String? value) {
    final v = value?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  static double? _normalizeMinAbsNet(double value) {
    return value > 0 ? value : null;
  }

  static String? _mapStatusForRpcNullable(String? uiStatus) {
    if (uiStatus == null || uiStatus.trim().isEmpty) return null;

    switch (uiStatus.trim().toLowerCase()) {
      case 'tümü':
      case 'tum':
      case 'hepsi':
      case 'all':
        return null;
      case 'sadece borçlu':
      case 'borçlu':
      case 'borc':
      case 'debt':
        return 'debt';
      case 'sadece alacaklı':
      case 'alacaklı':
      case 'credit':
        return 'credit';
      default:
        return null;
    }
  }

  factory BalanceReportNormalizedFilters.fromUi(BalanceReportFilters filters) {
    return BalanceReportNormalizedFilters(
      minAbsNet: _normalizeMinAbsNet(filters.minAbsNet),
      status: _mapStatusForRpcNullable(filters.statusLabel),
      groupName: _normalizeText(filters.groupName),
      subGroup: _normalizeText(filters.subGroup),
      altGroup: _normalizeText(filters.altGroup),
      marketerName: _normalizeText(filters.marketerName),
      search: _normalizeText(filters.search),
    );
  }
}
