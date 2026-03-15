import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final _adminSystemSettingsProvider =
    FutureProvider<AdminSystemSettings>((ref) async {
  return adminSettingsRepository.fetchSystemSettings();
});

class SettingsSystemPage extends ConsumerStatefulWidget {
  const SettingsSystemPage({super.key});

  @override
  ConsumerState<SettingsSystemPage> createState() =>
      _SettingsSystemPageState();
}

class _SettingsSystemPageState
    extends ConsumerState<SettingsSystemPage> {
  AdminSystemSettings? _settings;
  bool _initialized = false;
  bool _saving = false;
  bool _dirty = false;
  String? _errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsAsync = ref.watch(_adminSystemSettingsProvider);

    return AppScaffold(
      title: 'Sistem',
      body: settingsAsync.when(
        loading: () => const AppLoadingState(),
        error: (e, _) => AppErrorState(
          message: 'Sistem ayarları yüklenemedi: $e',
          onRetry: () =>
              ref.refresh(_adminSystemSettingsProvider.future),
        ),
        data: (settings) {
            if (!_initialized) {
              _settings = settings;
              _initialized = true;
            }

            final current = _settings!;

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Uygulama bilgisi, tanılama araçları ve bakım modu.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color
                          ?.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  const _SystemInfoCard(),
                  const SizedBox(height: AppSpacing.s16),
                  const _SystemDiagnosticsCard(),
                  const SizedBox(height: AppSpacing.s16),
                  _SystemMaintenanceCard(
                    settings: current,
                    onChanged: _updateSettings,
                    saving: _saving,
                    dirty: _dirty,
                    errorText: _errorText,
                    onSave: _saveSettings,
                  ),
                  const SizedBox(height: AppSpacing.s32),
                ],
              ),
            );
        },
      ),
    );
  }

  void _updateSettings(AdminSystemSettings updated) {
    setState(() {
      _settings = updated;
      _dirty = true;
    });
  }

  Future<void> _saveSettings() async {
    final current = _settings!;

    setState(() {
      _saving = true;
      _errorText = null;
    });

    try {
      await adminSettingsRepository.updateSystemSettings(current);
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

class _SystemInfoCard extends StatelessWidget {
  const _SystemInfoCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Şimdilik sabit placeholder bilgiler.
    const version = 'Sürüm: -';
    const buildType = 'Mod: Production';
    const backend = 'Sunucu: Supabase';

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
              'Uygulama Bilgisi',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(version, style: theme.textTheme.bodySmall),
            const SizedBox(height: AppSpacing.s4),
            Text(buildType, style: theme.textTheme.bodySmall),
            const SizedBox(height: AppSpacing.s4),
            Text(backend, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _SystemDiagnosticsCard extends StatelessWidget {
  const _SystemDiagnosticsCard();

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
              'Tanılama',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            Wrap(
              spacing: AppSpacing.s12,
              runSpacing: AppSpacing.s8,
              children: [
                OutlinedButton(
                  onPressed: () {
                    // Placeholder
                  },
                  child: const Text('Cache temizle'),
                ),
                OutlinedButton(
                  onPressed: () {
                    // Placeholder
                  },
                  child: const Text('Logları kopyala'),
                ),
                OutlinedButton(
                  onPressed: () {
                    // Placeholder
                  },
                  child: const Text('Bağlantıyı test et'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemMaintenanceCard extends StatelessWidget {
  const _SystemMaintenanceCard({
    required this.settings,
    required this.onChanged,
    required this.saving,
    required this.dirty,
    required this.errorText,
    required this.onSave,
  });

  final AdminSystemSettings settings;
  final ValueChanged<AdminSystemSettings> onChanged;
  final bool saving;
  final bool dirty;
  final String? errorText;
  final Future<void> Function() onSave;

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
              'Bakım Modu',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: settings.maintenanceMode,
                  onChanged: (value) => onChanged(
                    settings.copyWith(maintenanceMode: value),
                  ),
                ),
                const SizedBox(width: AppSpacing.s4),
                const Text('Bakım modunu aktif et'),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              'Bakım modu aktif olduğunda müşteri uygulaması geçici olarak kapalı mesajı gösterebilir.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color
                    ?.withValues(alpha: 0.8),
              ),
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
                onPressed:
                    (!dirty || saving) ? null : onSave,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
