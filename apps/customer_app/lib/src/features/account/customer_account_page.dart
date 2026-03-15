import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../customer/home/customer_home_page.dart';

class CustomerAccountPage extends ConsumerWidget {
  const CustomerAccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = supabaseClient.auth.currentUser;
    final customerAsync = ref.watch(currentCustomerProvider);
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Bilgilerim',
      body: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          Card(
            child: Padding(
              padding: AppSpacing.cardPadding,
              child: Row(
                children: [
                  CircleAvatar(
                    child: Text(
                      (user?.email ?? '-').isNotEmpty
                          ? (user!.email![0].toUpperCase())
                          : '-',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.email ?? '-',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.s4),
                        Text(
                          'Müşteri hesabı',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          customerAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
              child: Text(
                'Müşteri bilgileri yüklenemedi: $error',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.red,
                ),
              ),
            ),
            data: (customer) {
              if (customer == null) {
                return const SizedBox.shrink();
              }

              final trade = customer.tradeTitle?.trim();
              final fullName = customer.fullName?.trim();
              final displayName = (trade != null && trade.isNotEmpty)
                  ? trade
                  : (fullName != null && fullName.isNotEmpty)
                      ? fullName
                      : null;

              final phone = customer.phone?.trim();
              final taxOffice = customer.taxOffice?.trim();
              final taxNo = customer.taxNo?.trim();
              final city = customer.city?.trim();
              final district = customer.district?.trim();
              final address = customer.address?.trim();

              String? formattedTax;
              if ((taxOffice != null && taxOffice.isNotEmpty) ||
                  (taxNo != null && taxNo.isNotEmpty)) {
                formattedTax = [taxOffice, taxNo]
                    .where((e) => e != null && e.trim().isNotEmpty)
                    .map((e) => e!.trim())
                    .join(' / ');
              }

              String? formattedAddress;
              final parts = <String?>[address, district, city]
                  .where((e) => e != null && e.trim().isNotEmpty)
                  .map((e) => e!.trim())
                  .toList(growable: false);
              if (parts.isNotEmpty) {
                formattedAddress = parts.join(', ');
              }

              return Card(
                child: Padding(
                  padding: AppSpacing.cardPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Müşteri bilgileri',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s8),
                      if (displayName != null && displayName.isNotEmpty) ...[
                        Text(
                          displayName,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s8),
                      ],
                      _InfoRow(
                        label: 'Cari kodu',
                        value: customer.code,
                      ),
                      if (phone != null && phone.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.s4),
                        _InfoRow(
                          label: 'Telefon',
                          value: phone,
                        ),
                      ],
                      if (formattedTax != null && formattedTax.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.s4),
                        _InfoRow(
                          label: 'Vergi dairesi / No',
                          value: formattedTax,
                        ),
                      ],
                      if (formattedAddress != null &&
                          formattedAddress.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.s4),
                        _InfoRow(
                          label: 'Adres',
                          value: formattedAddress,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.s16),
          Card(
            child: Column(
              children: [
                AppListTile(
                  leading: const Icon(Icons.logout),
                  title: 'Çıkış yap',
                  onTap: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('customer_remember_login', false);
                    await supabaseClient.auth.signOut();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
