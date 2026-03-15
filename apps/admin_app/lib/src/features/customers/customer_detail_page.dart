import 'package:core/core.dart' hide isValidUuid;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'customer_general_tab.dart';
import 'customer_statement_page.dart';
import 'customer_payments_tab.dart';
import 'customer_risk_tab.dart';
import '../../utils/uuid_utils.dart';

class CustomerDetailPage extends ConsumerWidget {
  const CustomerDetailPage({
    super.key,
    required this.customerId,
    this.initialTabIndex = 0,
  });

  final String customerId;
  final int initialTabIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isValidUuid(customerId)) {
      return const AppScaffold(
        title: 'Cari / Müşteriler Yönetimi',
        body: Center(
          child: Text('Geçersiz veya eksik müşteri ID bilgisi.'),
        ),
      );
    }

    final customerAsync = ref.watch(customerDetailProvider(customerId));

    final customerName = customerAsync.maybeWhen(
      data: (c) => c.name,
      orElse: () => null,
    );

    const baseTitle = 'Cari / Müşteriler Yönetimi';
    final title = customerName != null
        ? '$baseTitle > $customerName'
        : baseTitle;

    final safeIndex = initialTabIndex.clamp(0, 3);

    return DefaultTabController(
      length: 4,
      initialIndex: safeIndex,
      child: AppScaffold(
        title: title,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'Genel'),
                Tab(text: 'Cari Hesap / Ekstre'),
                Tab(text: 'Tahsilatlar'),
                Tab(text: 'Risk & Limit'),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            Expanded(
              child: TabBarView(
                children: [
                  CustomerGeneralTab(customerId: customerId),
                  CustomerStatementPage(customerId: customerId),
                  CustomerPaymentsTab(customerId: customerId),
                  CustomerRiskTab(customerId: customerId),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
