import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:core/core.dart' show isAdminProvider;

import '../constants/app_layout.dart';
import '../features/dashboard/dashboard_refresh_provider.dart';

enum AdminShellSection {
  dashboard,
  stocks,
  orders,
  invoices,
  customers,
  settings,
}

/// Üst app bar + sol sidebar + içerik alanından oluşan
/// kurumsal admin shell layout.
class AdminShell extends StatelessWidget {
  const AdminShell({
    super.key,
    required this.currentSection,
    required this.child,
  });

  final AdminShellSection currentSection;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;

        if (isWide) {
          return Scaffold(
            appBar: _buildAppBar(context, showMenuButton: false),
            body: Row(
              children: [
                SizedBox(
                  width: AppLayout.sidebarWidth,
                  child: _Sidebar(
                    currentSection: currentSection,
                    isInDrawer: false,
                  ),
                ),
                const VerticalDivider(
                  width: 1,
                  color: Color(0xFFE5E7EB),
                ),
                Expanded(
                  child: Container(
                    color: const Color(0xFFF8FAFC),
                    child: child,
                  ),
                ),
              ],
            ),
          );
        }

        // Mobil / dar ekran: sidebar Drawer olarak.
        return Scaffold(
          appBar: _buildAppBar(context, showMenuButton: true),
          drawer: Drawer(
            child: SafeArea(
              child: _Sidebar(
                currentSection: currentSection,
                isInDrawer: true,
              ),
            ),
          ),
          body: Container(
            color: const Color(0xFFF8FAFC),
            child: child,
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context,
      {required bool showMenuButton}) {
    return AppBar(
      toolbarHeight: AppLayout.appBarHeight,
      automaticallyImplyLeading: false,
      titleSpacing: 16,
      title: Row(
        children: [
          if (showMenuButton)
            Builder(
              builder: (context) {
                return IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () {
                    Scaffold.of(context).openDrawer();
                  },
                );
              },
            ),
          Image.asset(
            'assets/images/Karamanlar_Yonetici_Uygulama.png',
            width: 32,
            height: 32,
          ),
          const SizedBox(width: 12),
          const Flexible(
            child: Text(
              'Karamanlar Ticaret',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
          ),
        ],
      ),
      actions: [
        if (currentSection == AdminShellSection.dashboard)
          Consumer(
            builder: (context, ref, _) {
              return IconButton(
                tooltip: 'Yenile',
                onPressed: () {
                  ref
                      .read(dashboardRefreshTickProvider.notifier)
                      .state++;
                },
                icon: const Icon(Icons.refresh),
              );
            },
          ),
        const SizedBox(
          width: 260,
          child: SizedBox(
            height: 44,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Arama...',
                prefixIcon: Icon(Icons.search, size: 18),
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.notifications_none_outlined),
        ),
        const SizedBox(width: 8),
        const Padding(
          padding: EdgeInsets.only(right: 16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Color(0xFFE5E7EB),
                child: Icon(
                  Icons.person_outline,
                  size: 18,
                  color: Color(0xFF374151),
                ),
              ),
              SizedBox(width: 8),
              Text(
                'Miraç Karaman',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF111827),
                  fontWeight: FontWeight.w500,
                ),
              ),
              Icon(Icons.keyboard_arrow_down_rounded),
            ],
          ),
        ),
      ],
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(
          height: 1,
          color: Color(0xFFE5E7EB),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.currentSection,
    required this.isInDrawer,
  });

  final AdminShellSection currentSection;
  final bool isInDrawer;

  @override
  Widget build(BuildContext context) {
    const bgColor = Color(0xFFF8FAFC);

    return Container(
      color: bgColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SidebarSectionHeader(label: 'GENEL'),
              _SidebarItem(
                section: AdminShellSection.dashboard,
                icon: Icons.dashboard_outlined,
                label: 'Genel Bakış',
                routeName: 'dashboard',
                currentSection: currentSection,
                isInDrawer: isInDrawer,
              ),
              const SizedBox(height: 16),
              const _SidebarSectionHeader(label: 'OPERASYON'),
              _SidebarItem(
                section: AdminShellSection.stocks,
                icon: Icons.inventory_2_outlined,
                label: 'Stoklar',
                routeName: 'stocks',
                currentSection: currentSection,
                isInDrawer: isInDrawer,
              ),
              _SidebarItem(
                section: AdminShellSection.orders,
                icon: Icons.shopping_cart_outlined,
                label: 'Siparişler',
                routeName: 'orders',
                currentSection: currentSection,
                isInDrawer: isInDrawer,
              ),
              _SidebarItem(
                section: AdminShellSection.invoices,
                icon: Icons.receipt_long_outlined,
                label: 'Faturalar',
                routeName: 'invoices',
                currentSection: currentSection,
                isInDrawer: isInDrawer,
              ),
              _SidebarItem(
                section: AdminShellSection.customers,
                icon: Icons.people_outline,
                label: 'Müşteriler',
                routeName: 'customers',
                currentSection: currentSection,
                isInDrawer: isInDrawer,
              ),
              _SidebarItem(
                section: AdminShellSection.customers,
                icon: Icons.account_balance_wallet_outlined,
                label: 'Cari Yönetimi',
                routeName: 'customerManagement',
                currentSection: currentSection,
                isInDrawer: isInDrawer,
              ),
              const SizedBox(height: 16),
              const _SidebarSectionHeader(label: 'YÖNETİM'),
              Consumer(
                builder: (context, ref, _) {
                  final isAdminAsync = ref.watch(isAdminProvider);
                  final isAdmin = isAdminAsync.value ?? false;
                  if (!isAdmin) {
                    return const SizedBox.shrink();
                  }

                  return _SidebarItem(
                    section: AdminShellSection.settings,
                    icon: Icons.fact_check_outlined,
                    label: 'Audit Logs',
                    routeName: 'auditLogs',
                    currentSection: currentSection,
                    isInDrawer: isInDrawer,
                  );
                },
              ),
              _SidebarItem(
                section: AdminShellSection.settings,
                icon: Icons.settings_outlined,
                label: 'Ayarlar',
                routeName: 'settings',
                currentSection: currentSection,
                isInDrawer: isInDrawer,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarSectionHeader extends StatelessWidget {
  const _SidebarSectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 4),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w600,
          color: Color(0xFF9CA3AF),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.section,
    required this.icon,
    required this.label,
    required this.routeName,
    required this.currentSection,
    required this.isInDrawer,
  });

  final AdminShellSection section;
  final IconData icon;
  final String label;
  final String routeName;
  final AdminShellSection currentSection;
  final bool isInDrawer;

  @override
  Widget build(BuildContext context) {
    const selectedBg = Color(0xFFE0F2F1);
    const primary = Color(0xFF22A38C);

    final selected = currentSection == section;

    return InkWell(
      onTap: () {
        context.goNamed(routeName);
        if (isInDrawer) {
          Navigator.of(context).pop();
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? selectedBg : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 24,
              decoration: BoxDecoration(
                color: selected ? primary : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              icon,
              size: 18,
              color:
                  selected ? const Color(0xFF111827) : const Color(0xFF6B7280),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected
                      ? const Color(0xFF111827)
                      : const Color(0xFF374151),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mobil ekranlar için bottom navigation tabbar kullanan
/// alternatif admin shell.
class AdminMobileShell extends StatelessWidget {
  const AdminMobileShell({
    super.key,
    required this.currentSection,
    required this.child,
  });

  final AdminShellSection currentSection;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final currentIndex = _indexForSection(currentSection);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 16),
            Image.asset(
              'assets/images/Karamanlar_Yonetici_Uygulama.png',
              width: 32,
              height: 32,
            ),
            const SizedBox(width: 12),
            const Flexible(
              child: Text(
                'Karamanlar Ticaret',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (currentSection == AdminShellSection.dashboard)
            Consumer(
              builder: (context, ref, _) {
                return IconButton(
                  tooltip: 'Yenile',
                  onPressed: () {
                    ref
                        .read(dashboardRefreshTickProvider.notifier)
                        .state++;
                  },
                  icon: const Icon(Icons.refresh),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                builder: (sheetContext) {
                  return SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.receipt_long_outlined),
                          title: const Text('Faturalar'),
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            context.goNamed('invoices');
                          },
                        ),
                        ListTile(
                          leading:
                              const Icon(Icons.assignment_return_outlined),
                          title: const Text('İadeler'),
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            context.goNamed('returns');
                          },
                        ),
                        ListTile(
                          leading:
                              const Icon(Icons.notifications_none_outlined),
                          title: const Text('Bildirimler'),
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            context.goNamed('notifications');
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.settings_outlined),
                          title: const Text('Ayarlar'),
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            context.goNamed('settings');
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
      body: Container(
        color: const Color(0xFFF8FAFC),
        child: child,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          if (index == currentIndex) {
            return;
          }

          final target = _sectionForIndex(index);
          switch (target) {
            case AdminShellSection.dashboard:
              context.goNamed('dashboard');
              break;
            case AdminShellSection.stocks:
              context.goNamed('stocks');
              break;
            case AdminShellSection.orders:
              context.goNamed('orders');
              break;
            case AdminShellSection.invoices:
              // Mobil alt barda ayrı bir sekme yok, siparişlerle grupla.
              context.goNamed('orders');
              break;
            case AdminShellSection.customers:
              context.goNamed('customers');
              break;
            case AdminShellSection.settings:
              context.goNamed('settings');
              break;
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            label: 'Genel',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            label: 'Stok',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_cart_outlined),
            label: 'Sipariş',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            label: 'Müşteri',
          ),
        ],
      ),
    );
  }

  int _indexForSection(AdminShellSection section) {
    switch (section) {
      case AdminShellSection.dashboard:
        return 0;
      case AdminShellSection.stocks:
        return 1;
      case AdminShellSection.orders:
        return 2;
      case AdminShellSection.customers:
        return 3;
      case AdminShellSection.invoices:
        // Fatura/iadeleri sipariş sekmesi altında grupla.
        return 2;
      case AdminShellSection.settings:
        // Ayarlar ayrı bir bottom tab olarak yok, dashboard ile grupla.
        return 0;
    }
  }

  AdminShellSection _sectionForIndex(int index) {
    switch (index) {
      case 0:
        return AdminShellSection.dashboard;
      case 1:
        return AdminShellSection.stocks;
      case 2:
        return AdminShellSection.orders;
      case 3:
      default:
        return AdminShellSection.customers;
    }
  }
}
