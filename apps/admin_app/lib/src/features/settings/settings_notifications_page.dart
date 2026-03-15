import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum NotificationSummary { daily, weekly, off }

class SettingsNotificationsPage extends ConsumerStatefulWidget {
  const SettingsNotificationsPage({super.key});

  @override
  ConsumerState<SettingsNotificationsPage> createState() =>
      _SettingsNotificationsPageState();
}

class _SettingsNotificationsPageState
    extends ConsumerState<SettingsNotificationsPage> {
  bool _orderNew = true;
  bool _orderPending = true;
  bool _invoiceOverdue = true;
  bool _invoiceCollection = true;

  bool _quietHoursEnabled = false;
  TimeOfDay _quietStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _quietEnd = const TimeOfDay(hour: 8, minute: 0);

  NotificationSummary _summary = NotificationSummary.daily;

  bool _dirty = false;
  bool _saving = false;
  String? _errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Bildirim Ayarları',
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sipariş ve fatura ile ilgili bildirim tercihlerini yönetin.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color
                    ?.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
            _buildOrdersCard(theme),
            const SizedBox(height: AppSpacing.s16),
            _buildInvoicesCard(theme),
            const SizedBox(height: AppSpacing.s16),
            _buildQuietAndSummaryCard(theme),
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
                onPressed: (!_dirty || _saving) ? null : _saveSettings,
              ),
            ),
            const SizedBox(height: AppSpacing.s32),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersCard(ThemeData theme) {
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
              'Sipariş Bildirimleri',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            _buildSwitchRow(
              label: 'Yeni sipariş bildirimi',
              value: _orderNew,
              onChanged: (v) => _setState(() => _orderNew = v),
            ),
            _buildSwitchRow(
              label: 'Onay bekleyen sipariş bildirimi',
              value: _orderPending,
              onChanged: (v) => _setState(() => _orderPending = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoicesCard(ThemeData theme) {
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
              'Fatura Bildirimleri',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            _buildSwitchRow(
              label: 'Vadesi geçen fatura bildirimi',
              value: _invoiceOverdue,
              onChanged: (v) => _setState(() => _invoiceOverdue = v),
            ),
            _buildSwitchRow(
              label: 'Tahsilat bildirimi',
              value: _invoiceCollection,
              onChanged: (v) => _setState(() => _invoiceCollection = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuietAndSummaryCard(ThemeData theme) {
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
              'Sessiz Saatler & Özet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: _quietHoursEnabled,
                  onChanged: (value) => _setState(() => _quietHoursEnabled = value),
                ),
                const SizedBox(width: AppSpacing.s4),
                const Text('Sessiz saatleri kullan'),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            if (_quietHoursEnabled)
              Wrap(
                spacing: AppSpacing.s12,
                runSpacing: AppSpacing.s8,
                children: [
                  OutlinedButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _quietStart,
                      );
                      if (picked != null) {
                        _setState(() => _quietStart = picked);
                      }
                    },
                    child: Text('Başlangıç: ${_formatTime(_quietStart)}'),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _quietEnd,
                      );
                      if (picked != null) {
                        _setState(() => _quietEnd = picked);
                      }
                    },
                    child: Text('Bitiş: ${_formatTime(_quietEnd)}'),
                  ),
                ],
              ),
            const SizedBox(height: AppSpacing.s16),
            Text(
              'Özet bildirimler',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.s8),
            Wrap(
              spacing: AppSpacing.s8,
              children: [
                ChoiceChip(
                  label: const Text('Günlük'),
                  selected: _summary == NotificationSummary.daily,
                  onSelected: (_) => _setState(
                    () => _summary = NotificationSummary.daily,
                  ),
                ),
                ChoiceChip(
                  label: const Text('Haftalık'),
                  selected: _summary == NotificationSummary.weekly,
                  onSelected: (_) => _setState(
                    () => _summary = NotificationSummary.weekly,
                  ),
                ),
                ChoiceChip(
                  label: const Text('Kapalı'),
                  selected: _summary == NotificationSummary.off,
                  onSelected: (_) => _setState(
                    () => _summary = NotificationSummary.off,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Switch(
          value: value,
          onChanged: onChanged,
        ),
        const SizedBox(width: AppSpacing.s4),
        Expanded(child: Text(label)),
      ],
    );
  }

  void _setState(void Function() updater) {
    setState(() {
      updater();
      _dirty = true;
    });
  }

  String _formatTime(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _saveSettings() async {
    // Basit validasyon: sessiz saatler açıkken başlangıç ve bitiş aynı olmasın.
    if (_quietHoursEnabled &&
        _quietStart.hour == _quietEnd.hour &&
        _quietStart.minute == _quietEnd.minute) {
      setState(() {
        _errorText =
            'Sessiz saat başlangıç ve bitiş zamanı aynı olamaz.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _errorText = null;
    });

    await Future<void>.delayed(const Duration(milliseconds: 300));

    setState(() {
      _saving = false;
      _dirty = false;
    });
  }
}
