class AdminSystemSettings {
  const AdminSystemSettings({
    required this.maintenanceMode,
  });

  final bool maintenanceMode;

  factory AdminSystemSettings.defaults() {
    return const AdminSystemSettings(
      maintenanceMode: false,
    );
  }

  AdminSystemSettings copyWith({
    bool? maintenanceMode,
  }) {
    return AdminSystemSettings(
      maintenanceMode: maintenanceMode ?? this.maintenanceMode,
    );
  }

  factory AdminSystemSettings.fromMap(Map<String, dynamic> map) {
    return AdminSystemSettings(
      maintenanceMode: (map['maintenance_mode'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'maintenance_mode': maintenanceMode,
    };
  }
}
