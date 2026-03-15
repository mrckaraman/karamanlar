import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'reports/balance_report_tab.dart';
import 'reports/risk_report_tab.dart';
import 'reports/shipment_list_tab.dart';

enum _ReportsTab {
  balances('Bakiye Listesi'),
  risk('Risk Analizi'),
  shipments('Sevkiyat Listesi');

  const _ReportsTab(this.label);
  final String label;
}

class CustomerReportsPage extends ConsumerStatefulWidget {
  const CustomerReportsPage({super.key});

  @override
  ConsumerState<CustomerReportsPage> createState() =>
      _CustomerReportsPageState();
}

class _CustomerReportsPageState extends ConsumerState<CustomerReportsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: _ReportsTab.values.length, vsync: this);
    _controller.addListener(() {
      if (!mounted) return;
      // TabBarView yerine içerik seçimi yaptığımız için index değişiminde
      // sayfayı yeniden çizdiriyoruz.
      setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final tab = GoRouterState.of(context).uri.queryParameters['tab'];
    if (tab == null || tab.isEmpty) {
      return;
    }

    final targetIndex = switch (tab) {
      'balances' => _ReportsTab.balances.index,
      'risk' => _ReportsTab.risk.index,
      'shipments' => _ReportsTab.shipments.index,
      _ => null,
    };

    if (targetIndex != null && _controller.index != targetIndex) {
      _controller.index = targetIndex;
      // didChangeDependencies içinde controller index değişimi her zaman
      // dinleyicileri tetiklemeyebilir; UI'nin senkron kalması için.
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedTab = _ReportsTab.values[_controller.index];

    Widget tabContent() {
      switch (selectedTab) {
        case _ReportsTab.balances:
          return const BalanceReportTab();
        case _ReportsTab.risk:
          return const RiskReportTab();
        case _ReportsTab.shipments:
          return const ShipmentListTab();
      }
    }

    return AppScaffold(
      title: 'Cari / Müşteri Raporları',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _ReportsHeaderCard(),
          const SizedBox(height: AppSpacing.s16),
          _PremiumTabs(controller: _controller),
          const SizedBox(height: AppSpacing.s12),
          tabContent(),
        ],
      ),
    );
  }
}

class _ReportsHeaderCard extends StatelessWidget {
  const _ReportsHeaderCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.bar_chart,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cari / Müşteri Raporları',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    'Finans kontrol merkezi: risk, limit, nakit akışı ve sevkiyat tek ekranda.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumTabs extends StatelessWidget {
  const _PremiumTabs({required this.controller});

  final TabController controller;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9FB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: TabBar(
          controller: controller,
          isScrollable: true,
          dividerColor: Colors.transparent,
          indicator: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurfaceVariant,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600),
          tabs: [
            for (final t in _ReportsTab.values)
              Tab(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(t.label),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
