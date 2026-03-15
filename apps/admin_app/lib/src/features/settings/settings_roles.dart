enum AdminSettingsRole { owner, admin, staff }

// Şimdilik mock: gerçek rol entegrasyonu daha sonra eklenecek.
const AdminSettingsRole currentSettingsRole = AdminSettingsRole.owner;

String adminSettingsRoleLabel(AdminSettingsRole role) {
  switch (role) {
    case AdminSettingsRole.owner:
      return 'Owner';
    case AdminSettingsRole.admin:
      return 'Admin';
    case AdminSettingsRole.staff:
      return 'Staff';
  }
}
