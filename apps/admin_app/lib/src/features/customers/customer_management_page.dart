import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../constants/ui_copy_tr.dart';

class CustomerManagementPage extends StatelessWidget {
  const CustomerManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: 'Cari / Müşteriler Yönetimi',
      icon: Icons.people_alt,
      subtitle: UiCopyTr.customersManagementSubtitle,
      child: GridView.count(
        crossAxisCount: 2,
        crossAxisSpacing: AppSpacing.s12,
        mainAxisSpacing: AppSpacing.s12,
        childAspectRatio: 1.1,
        children: [
          AdminDashboardCard(
            icon: Icons.person_add,
            title: 'Yeni Cari Ekle',
            subtitle: UiCopyTr.customersMenuNewSubtitle,
            onTap: () => GoRouter.of(context).go('/customers/new'),
          ),
          AdminDashboardCard(
            icon: Icons.people,
            title: 'Cari Bilgileri',
            subtitle: UiCopyTr.customersMenuInfoSubtitle,
            onTap: () => GoRouter.of(context).go('/customers'),
          ),
          AdminDashboardCard(
            icon: Icons.receipt_long,
            title: 'Cari Hesap / Ekstre',
            subtitle: UiCopyTr.customersMenuLedgerSubtitle,
            onTap: () => GoRouter.of(context).go('/customers/ledger'),
          ),
          AdminDashboardCard(
            icon: Icons.payments,
            title: 'Tahsilatlar',
            subtitle: UiCopyTr.customersMenuPaymentsSubtitle,
            onTap: () =>
                GoRouter.of(context).go('/customers/payments/_all'),
          ),
          AdminDashboardCard(
            icon: Icons.import_export,
            title: 'Cari İçe / Dışa Aktarma',
            subtitle: 'Excel/CSV ile cari aktarın veya dışa alın.',
            onTap: () => GoRouter.of(context).go('/customers/transfer'),
          ),
          AdminDashboardCard(
            icon: Icons.bar_chart,
            title: 'Raporlar',
            subtitle: UiCopyTr.customersMenuReportsSubtitle,
            onTap: () => GoRouter.of(context).go('/customers/reports'),
          ),
        ],
      ),
    );
  }
}
