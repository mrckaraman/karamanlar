import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_roles.dart';

final _adminNumberingSettingsProvider =
    FutureProvider<AdminNumberingSettings>((ref) async {
  return adminSettingsRepository.fetchNumberingSettings();
});

class SettingsNumberingPage extends ConsumerStatefulWidget {
  const SettingsNumberingPage({super.key});

  @override
  ConsumerState<SettingsNumberingPage> createState() =>
      _SettingsNumberingPageState();
}

class _SettingsNumberingPageState
    extends ConsumerState<SettingsNumberingPage> {
  AdminNumberingConfig? _orderConfig;
  AdminNumberingConfig? _invoiceConfig;
  bool _initialized = false;

  bool _savingOrder = false;
  bool _savingInvoice = false;
  String? _orderError;
  String? _invoiceError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsAsync = ref.watch(_adminNumberingSettingsProvider);

    return AppScaffold(
      title: 'Numaratörler',
      body: settingsAsync.when(
        loading: () => const AppLoadingState(),
        error: (e, _) => AppErrorState(
          message: 'Numaratör ayarları yüklenemedi: $e',
          onRetry: () =>
              ref.refresh(_adminNumberingSettingsProvider.future),
        ),
        data: (settings) {
            if (!_initialized) {
              _orderConfig = settings.order;
              _invoiceConfig = settings.invoice;
              _initialized = true;
            }

            final orderConfig = _orderConfig!;
            final invoiceConfig = _invoiceConfig!;
            const role = currentSettingsRole;
            const canEdit = role == AdminSettingsRole.owner ||
              role == AdminSettingsRole.admin;

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sipariş ve fatura numara formatlarını yönetin.',
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
                  if (!canEdit) ...[
                    const AppEmptyState(
                      title: 'Bu ayara erişim yetkiniz yok.',
                      subtitle:
                          'Numaratörler yalnızca Owner ve Admin roller tarafından düzenlenebilir.',
                    ),
                  ] else ...[
                    _NumberingSectionCard(
                      title: 'Sipariş',
                      config: orderConfig,
                      saving: _savingOrder,
                      errorText: _orderError,
                      onChanged: (updated) {
                        setState(() {
                          _orderConfig = updated;
                        });
                      },
                      onSave: () async {
                        await _saveConfig(isOrder: true);
                      },
                    ),
                    const SizedBox(height: AppSpacing.s16),
                    _NumberingSectionCard(
                      title: 'Fatura',
                      config: invoiceConfig,
                      saving: _savingInvoice,
                      errorText: _invoiceError,
                      onChanged: (updated) {
                        setState(() {
                          _invoiceConfig = updated;
                        });
                      },
                      onSave: () async {
                        await _saveConfig(isOrder: false);
                      },
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

  Future<void> _saveConfig({required bool isOrder}) async {
    final config = isOrder ? _orderConfig : _invoiceConfig;
    if (config == null) return;

    final error = _validateConfig(config);
    if (error != null) {
      setState(() {
        if (isOrder) {
          _orderError = error;
        } else {
          _invoiceError = error;
        }
      });
      return;
    }

    setState(() {
      if (isOrder) {
        _savingOrder = true;
        _orderError = null;
      } else {
        _savingInvoice = true;
        _invoiceError = null;
      }
    });

    try {
      await adminSettingsRepository.updateNumberingConfig(config);
    } catch (e) {
      setState(() {
        final msg = 'Kaydedilirken bir hata oluştu: $e';
        if (isOrder) {
          _orderError = msg;
        } else {
          _invoiceError = msg;
        }
      });
    } finally {
      setState(() {
        if (isOrder) {
          _savingOrder = false;
        } else {
          _savingInvoice = false;
        }
      });
    }
  }

  String? _validateConfig(AdminNumberingConfig config) {
    final prefix = config.prefix.trim();
    if (prefix.isEmpty) {
      return 'Önek (prefix) boş olamaz.';
    }
    if (prefix.length > 10) {
      return 'Önek en fazla 10 karakter olabilir.';
    }
    if (prefix.contains(RegExp(r'\s'))) {
      return 'Önek içinde boşluk kullanılamaz.';
    }
    if (config.padding < 3 || config.padding > 8) {
      return 'Basamak sayısı 3 ile 8 arasında olmalıdır.';
    }
    if (config.nextNumber < 1) {
      return 'Sonraki numara 1 veya daha büyük olmalıdır.';
    }
    return null;
  }
}

class _NumberingSectionCard extends StatelessWidget {
  const _NumberingSectionCard({
    required this.title,
    required this.config,
    required this.onChanged,
    required this.onSave,
    required this.saving,
    required this.errorText,
  });

  final String title;
  final AdminNumberingConfig config;
  final ValueChanged<AdminNumberingConfig> onChanged;
  final Future<void> Function() onSave;
  final bool saving;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOrder = config.key == 'order';
    final preview = _buildPreview(config);

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
              title,
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
                      child: TextFormField(
                        initialValue: config.prefix,
                        decoration: const InputDecoration(
                          labelText: 'Önek (prefix)',
                        ),
                        onChanged: (value) => onChanged(
                          config.copyWith(prefix: value.trim()),
                        ),
                      ),
                    ),
                    field(
                      child: DropdownButtonFormField<int>(
                        initialValue: config.padding,
                        decoration: const InputDecoration(
                          labelText: 'Basamak',
                        ),
                        items: [3, 4, 5, 6, 7, 8]
                            .map(
                              (v) => DropdownMenuItem<int>(
                                value: v,
                                child: Text(v.toString()),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          onChanged(config.copyWith(padding: value));
                        },
                      ),
                    ),
                    field(
                      child: TextFormField(
                        initialValue: config.nextNumber.toString(),
                        decoration: const InputDecoration(
                          labelText: 'Sonraki numara',
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (value) {
                          final parsed = int.tryParse(value);
                          if (parsed == null) return;
                          onChanged(config.copyWith(nextNumber: parsed));
                        },
                      ),
                    ),
                    field(
                      child: Row(
                        children: [
                          Switch(
                            value: config.includeYear,
                            onChanged: (value) {
                              onChanged(
                                config.copyWith(includeYear: value),
                              );
                            },
                          ),
                          const SizedBox(width: AppSpacing.s4),
                          const Expanded(
                            child: Text(
                              'Yıl ekle',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    field(
                      child: DropdownButtonFormField<String>(
                        initialValue: config.separator,
                        decoration: const InputDecoration(
                          labelText: 'Ayırıcı',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: '-',
                            child: Text('-'),
                          ),
                          DropdownMenuItem(
                            value: '/',
                            child: Text('/'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          onChanged(config.copyWith(separator: value));
                        },
                      ),
                    ),
                    field(
                      child: DropdownButtonFormField<AdminNumberingResetPolicy>(
                        initialValue: config.resetPolicy,
                        decoration: const InputDecoration(
                          labelText: 'Sıfırlama',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: AdminNumberingResetPolicy.never,
                            child: Text('Asla'),
                          ),
                          DropdownMenuItem(
                            value: AdminNumberingResetPolicy.yearly,
                            child: Text('Yıllık'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          onChanged(config.copyWith(resetPolicy: value));
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.s16),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.s12,
              runSpacing: AppSpacing.s8,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s12,
                    vertical: AppSpacing.s8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    preview,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  isOrder
                      ? 'Örnek sipariş numarası'
                      : 'Örnek fatura numarası',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            if (errorText != null) ...[
              const SizedBox(height: AppSpacing.s12),
              Text(
                errorText!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.s16),
            Align(
              alignment: Alignment.centerRight,
              child: PrimaryButton(
                label: saving ? 'Kaydediliyor...' : 'Kaydet',
                onPressed: saving ? null : onSave,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _buildPreview(AdminNumberingConfig config) {
  final now = DateTime.now();
  final parts = <String>[];
  if (config.includeYear) {
    parts.add(now.year.toString());
  }
  if (config.prefix.isNotEmpty) {
    parts.add(config.prefix);
  }
  final padded = config.nextNumber
      .toString()
      .padLeft(config.padding, '0');
  parts.add(padded);
  return parts.join(config.separator);
}
