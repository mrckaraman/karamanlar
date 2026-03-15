import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_roles.dart';

final _adminCompanySettingsProvider =
    FutureProvider<AdminCompanySettings>((ref) async {
  return adminSettingsRepository.fetchCompanySettings();
});

class SettingsCompanyPage extends ConsumerStatefulWidget {
  const SettingsCompanyPage({super.key});

  @override
  ConsumerState<SettingsCompanyPage> createState() =>
      _SettingsCompanyPageState();
}

class _SettingsCompanyPageState
    extends ConsumerState<SettingsCompanyPage> {
  AdminCompanySettings? _settings;
  bool _initialized = false;
  bool _saving = false;
  bool _dirty = false;
  String? _errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsAsync = ref.watch(_adminCompanySettingsProvider);

    return AppScaffold(
      title: 'Şirket & Belge Ayarları',
      body: settingsAsync.when(
        loading: () => const AppLoadingState(),
        error: (e, _) => AppErrorState(
          message: 'Şirket ayarları yüklenemedi: $e',
          onRetry: () =>
              ref.refresh(_adminCompanySettingsProvider.future),
        ),
        data: (settings) {
            if (!_initialized) {
              _settings = settings;
              _initialized = true;
            }

            final current = _settings!;
            const role = currentSettingsRole;
            const isOwner = role == AdminSettingsRole.owner;

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Şirket bilgileriniz ve belge görünüm ayarları.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color
                          ?.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    'Rol: ${adminSettingsRoleLabel(role)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color
                          ?.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  _CompanyInfoCard(
                    settings: current,
                    onChanged: _updateSettings,
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  _CompanyDocumentCard(
                    settings: current,
                    onChanged: _updateSettings,
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  _CompanyPreviewCard(settings: current),
                  if (_errorText != null) ...[
                    const SizedBox(height: AppSpacing.s12),
                    Text(
                      _errorText!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.s16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: PrimaryButton(
                      label: _saving ? 'Kaydediliyor...' : 'Kaydet',
                      onPressed: (!isOwner || !_dirty || _saving)
                          ? null
                          : _saveSettings,
                    ),
                  ),
                  if (!isOwner) ...[
                    const SizedBox(height: AppSpacing.s8),
                    Text(
                      'Bu ayarları yalnızca Owner rolü güncelleyebilir.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.s32),
                ],
              ),
            );
          },
        ),
    );
  }

  void _updateSettings(AdminCompanySettings updated) {
    setState(() {
      _settings = updated;
      _dirty = true;
    });
  }

  Future<void> _saveSettings() async {
    final current = _settings!;
    final title = current.companyTitle.trim();
    if (title.isEmpty) {
      setState(() {
        _errorText = 'Şirket ünvanı boş olamaz.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _errorText = null;
    });

    try {
      await adminSettingsRepository.updateCompanySettings(current);
      setState(() {
        _dirty = false;
      });
    } catch (e) {
      setState(() {
        _errorText = 'Kaydedilirken bir hata oluştu: $e';
      });
    } finally {
      setState(() {
        _saving = false;
      });
    }
  }
}

class _CompanyInfoCard extends StatelessWidget {
  const _CompanyInfoCard({
    required this.settings,
    required this.onChanged,
  });

  final AdminCompanySettings settings;
  final ValueChanged<AdminCompanySettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Şirket Bilgileri',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final columns = AppResponsive.gridColumnsForWidth(
                  width,
                  mobile: 1,
                  tablet: 2,
                  desktop: 2,
                );
                const spacing = AppSpacing.s16;
                final columnWidth =
                    (width - (spacing * (columns - 1))) / columns;

                double spanWidth(int span) {
                  final clampedSpan = span.clamp(1, columns);
                  if (clampedSpan == columns) return width;
                  return (columnWidth * clampedSpan) +
                      (spacing * (clampedSpan - 1));
                }

                Widget field({int span = 1, required Widget child}) {
                  return SizedBox(width: spanWidth(span), child: child);
                }

                return Wrap(
                  runSpacing: AppSpacing.s12,
                  spacing: spacing,
                  children: [
                    field(
                      span: 2,
                      child: TextFormField(
                        initialValue: settings.companyTitle,
                        decoration: const InputDecoration(
                          labelText: 'Ünvan *',
                        ),
                        onChanged: (value) => onChanged(
                          settings.copyWith(companyTitle: value),
                        ),
                      ),
                    ),
                    field(
                      child: TextFormField(
                        initialValue: settings.taxOffice,
                        decoration: const InputDecoration(
                          labelText: 'Vergi Dairesi',
                        ),
                        onChanged: (value) => onChanged(
                          settings.copyWith(taxOffice: value),
                        ),
                      ),
                    ),
                    field(
                      child: TextFormField(
                        initialValue: settings.taxNo,
                        decoration: const InputDecoration(
                          labelText: 'Vergi No / TCKN',
                        ),
                        onChanged: (value) => onChanged(
                          settings.copyWith(taxNo: value),
                        ),
                      ),
                    ),
                    field(
                      child: TextFormField(
                        initialValue: settings.phone,
                        decoration: const InputDecoration(
                          labelText: 'Telefon',
                        ),
                        onChanged: (value) => onChanged(
                          settings.copyWith(phone: value),
                        ),
                      ),
                    ),
                    field(
                      child: TextFormField(
                        initialValue: settings.email,
                        decoration: const InputDecoration(
                          labelText: 'E-posta',
                        ),
                        onChanged: (value) => onChanged(
                          settings.copyWith(email: value),
                        ),
                      ),
                    ),
                    field(
                      child: TextFormField(
                        initialValue: settings.website,
                        decoration: const InputDecoration(
                          labelText: 'Web',
                        ),
                        onChanged: (value) => onChanged(
                          settings.copyWith(website: value),
                        ),
                      ),
                    ),
                    field(
                      span: 2,
                      child: TextFormField(
                        initialValue: settings.address,
                        decoration: const InputDecoration(
                          labelText: 'Adres',
                        ),
                        maxLines: 3,
                        onChanged: (value) => onChanged(
                          settings.copyWith(address: value),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CompanyDocumentCard extends StatelessWidget {
  const _CompanyDocumentCard({
    required this.settings,
    required this.onChanged,
  });

  final AdminCompanySettings settings;
  final ValueChanged<AdminCompanySettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Belge Ayarları',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final columns = AppResponsive.gridColumnsForWidth(
                  width,
                  mobile: 1,
                  tablet: 2,
                  desktop: 2,
                );
                const spacing = AppSpacing.s16;
                final columnWidth =
                    (width - (spacing * (columns - 1))) / columns;

                double spanWidth(int span) {
                  final clampedSpan = span.clamp(1, columns);
                  if (clampedSpan == columns) return width;
                  return (columnWidth * clampedSpan) +
                      (spacing * (clampedSpan - 1));
                }

                Widget field({int span = 1, required Widget child}) {
                  return SizedBox(width: spanWidth(span), child: child);
                }

                Widget toggle({
                  required bool value,
                  required ValueChanged<bool> onChanged,
                  required String label,
                }) {
                  return field(
                    child: Row(
                      children: [
                        Switch(value: value, onChanged: onChanged),
                        const SizedBox(width: AppSpacing.s4),
                        Expanded(
                          child: Text(
                            label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Wrap(
                  runSpacing: AppSpacing.s12,
                  spacing: spacing,
                  children: [
                    field(
                      span: 2,
                      child: TextFormField(
                        initialValue: settings.pdfFooterNote,
                        decoration: const InputDecoration(
                          labelText: 'PDF Alt Bilgi',
                        ),
                        maxLines: 3,
                        onChanged: (value) => onChanged(
                          settings.copyWith(pdfFooterNote: value),
                        ),
                      ),
                    ),
                    field(
                      child: DropdownButtonFormField<AdminCompanyCurrency>(
                        initialValue: settings.currency,
                        decoration: const InputDecoration(
                          labelText: 'Para Birimi',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: AdminCompanyCurrency.tryTr,
                            child: Text('TRY'),
                          ),
                          DropdownMenuItem(
                            value: AdminCompanyCurrency.usd,
                            child: Text('USD'),
                          ),
                          DropdownMenuItem(
                            value: AdminCompanyCurrency.eur,
                            child: Text('EUR'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          onChanged(settings.copyWith(currency: value));
                        },
                      ),
                    ),
                    toggle(
                      value: settings.showVatOnTotals,
                      onChanged: (value) => onChanged(
                        settings.copyWith(showVatOnTotals: value),
                      ),
                      label: 'Toplamlarda KDV’yi göster',
                    ),
                    toggle(
                      value: settings.showSignatureArea,
                      onChanged: (value) => onChanged(
                        settings.copyWith(showSignatureArea: value),
                      ),
                      label: 'İmza/kaşe alanı göster',
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CompanyPreviewCard extends StatelessWidget {
  const _CompanyPreviewCard({
    required this.settings,
  });

  final AdminCompanySettings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Önizleme',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(
              settings.companyTitle.isEmpty
                  ? 'Şirket ünvanı henüz girilmedi.'
                  : settings.companyTitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (settings.address.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s4),
              Text(
                settings.address,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (settings.pdfFooterNote.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s8),
              Divider(
                height: 1,
                color: theme.dividerColor,
              ),
              const SizedBox(height: AppSpacing.s8),
              Text(
                settings.pdfFooterNote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodySmall?.color
                      ?.withValues(alpha: 0.9),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
