import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../crashlytics/crashlytics.dart';

const bool crashTestEnabled =
  bool.fromEnvironment('CRASH_TEST_ENABLED');

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Ayarlar / Tanımlar',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final crossAxisCount = AppResponsive.gridColumnsForWidth(
            width,
            mobile: 1,
            tablet: 2,
            desktop: 2,
          );
          final childAspectRatio = crossAxisCount == 1 ? 2.4 : 2.1;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Şirket bilgileri, numaratörler ve yazdırma ayarlarını yönetin.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodySmall?.color
                      ?.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: AppSpacing.s16),
              Expanded(
                child: GridView.count(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: childAspectRatio,
                  children: const [
                    _SettingsHubCard(
                      icon: Icons.business_outlined,
                      title: 'Şirket & Belge Ayarları',
                      subtitle:
                          'Ünvan, vergi, adres ve PDF alt bilgilerini yönetin',
                      route: '/settings/company',
                    ),
                    _SettingsHubCard(
                      icon: Icons.confirmation_number_outlined,
                      title: 'Numaratörler',
                      subtitle:
                          'Sipariş ve fatura numara formatları ile başlangıç değerleri',
                      route: '/settings/numbering',
                    ),
                    _SettingsHubCard(
                      icon: Icons.print_outlined,
                      title: 'Yazdırma / Şablonlar',
                      subtitle:
                          'Fatura, sipariş fişi ve genel yazdırma stilleri',
                      route: '/settings/print',
                    ),
                  ],
                ),
              ),
              if ((kDebugMode || crashTestEnabled) && !kIsWeb) ...[
                const SizedBox(height: AppSpacing.s12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: ElevatedButton(
                    onPressed: testCrash,
                    child: Text('Crash Test'),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SettingsHubCard extends StatelessWidget {
  const _SettingsHubCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: () => GoRouter.of(context).go(route),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 28, color: color),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color
                              ?.withValues(alpha: 0.8),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
