import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../utils/formatters_tr.dart';
import '../stocks/stock_import_export_download_stub.dart'
  if (dart.library.html) '../stocks/stock_import_export_download_web.dart'
  as download_helper;

import 'audit_logs_provider.dart';

class AuditLogsPage extends ConsumerStatefulWidget {
  const AuditLogsPage({super.key});

  @override
  ConsumerState<AuditLogsPage> createState() => _AuditLogsPageState();
}

class _AuditLogsPageState extends ConsumerState<AuditLogsPage> {
  static const List<String> _entities = <String>[
    'customers',
    'orders',
    'invoices',
    'payments',
    'limits',
  ];

  static const List<String> _actions = <String>[
    'create',
    'update',
    'delete',
    'convert',
  ];

  String? _entity;
  String? _action;
  DateTime? _from;
  DateTime? _to;
  final TextEditingController _createdByCtrl = TextEditingController();

  AsyncValue<void> _exportState = const AsyncData(null);

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _createdByCtrl.dispose();
    super.dispose();
  }

  Future<void> _applyFilters() async {
    final createdBy = _createdByCtrl.text.trim();

    await ref.read(auditLogsProvider.notifier).reloadWithFilters(
          AuditLogFilters(
            entity: _entity,
            action: _action,
            from: _from,
            to: _to,
            createdBy: createdBy.isEmpty ? null : createdBy,
          ),
        );
  }

  Future<void> _clearFilters() async {
    setState(() {
      _entity = null;
      _action = null;
      _from = null;
      _to = null;
    });
    _createdByCtrl.clear();
    await ref.read(auditLogsProvider.notifier).clearFilters();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();

    final initial = (_from != null && _to != null)
        ? DateTimeRange(start: _from!, end: _to!)
        : null;

    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: initial,
    );

    if (range == null) return;

    // Gün bazında seçildiği için inclusive hale getir.
    final from = DateTime(range.start.year, range.start.month, range.start.day);
    final to = DateTime(
      range.end.year,
      range.end.month,
      range.end.day,
      23,
      59,
      59,
      999,
    );

    setState(() {
      _from = from;
      _to = to;
    });

    await _applyFilters();
  }

  Future<void> _exportCsv() async {
    if (_exportState.isLoading) return;

    FocusScope.of(context).unfocus();

    setState(() => _exportState = const AsyncLoading());

    final filters = ref.read(auditLogsProvider.notifier).currentFilters;
    final service = AuditExportService(auditRepository: auditRepository);

    final result = await AsyncValue.guard(() async {
      return service.buildCsv(
        entity: filters.entity,
        action: filters.action,
        from: filters.from,
        to: filters.to,
        createdBy: filters.createdBy,
      );
    });

    if (!mounted) return;
    setState(() => _exportState = result);

    if (result.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'CSV dışa aktarma başarısız: ${AppException.messageOf(result.error!)}',
          ),
        ),
      );
      return;
    }

    final file = result.value as AuditExportFile;
    final ok = await download_helper.saveBytesFile(
      file.fileName,
      file.bytes,
      mimeType: file.mimeType,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'CSV hazırlandı.' : 'CSV kaydedilemedi/açılamadı.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(auditLogsProvider);

    return AdminPageScaffold(
      title: 'Audit Logs',
      icon: Icons.fact_check_outlined,
      subtitle: 'Kritik veri değişikliklerinin kayıtları',
      actions: [
        if (_exportState.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          IconButton(
            tooltip: 'CSV Dışa Aktar',
            onPressed: _exportCsv,
            icon: const Icon(Icons.table_view_outlined),
          ),
      ],
      child: _buildBody(context, async),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AsyncValue<AuditLogsViewState> async,
  ) {
    final data = async.valueOrNull;
    final items = data?.items ?? const <AuditLogEntry>[];

    return Column(
      children: [
        Padding(
          padding: AppSpacing.screenPadding,
          child: _buildFilterBar(context),
        ),
        Expanded(
          child: _buildListArea(context, async, items),
        ),
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.s16,
            right: AppSpacing.s16,
            bottom: AppSpacing.s16,
          ),
          child: _buildPaginationBar(context, async),
        ),
      ],
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    String dateLabel;
    if (_from != null && _to != null) {
      dateLabel = '${formatDateTime(_from!)} – ${formatDateTime(_to!)}';
    } else {
      dateLabel = 'Tarih aralığı';
    }

    return Card(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Wrap(
          spacing: AppSpacing.s12,
          runSpacing: AppSpacing.s8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String?>(
                key: ValueKey<String?>(_entity),
                initialValue: _entity,
                decoration: const InputDecoration(
                  labelText: 'Entity',
                ),
                items: <DropdownMenuItem<String?>>[
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Hepsi'),
                  ),
                  ..._entities.map(
                    (e) => DropdownMenuItem<String?>(
                      value: e,
                      child: Text(e),
                    ),
                  ),
                ],
                onChanged: (v) async {
                  setState(() => _entity = v);
                  await _applyFilters();
                },
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String?>(
                key: ValueKey<String?>(_action),
                initialValue: _action,
                decoration: const InputDecoration(
                  labelText: 'Action',
                ),
                items: <DropdownMenuItem<String?>>[
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Hepsi'),
                  ),
                  ..._actions.map(
                    (a) => DropdownMenuItem<String?>(
                      value: a,
                      child: Text(a),
                    ),
                  ),
                ],
                onChanged: (v) async {
                  setState(() => _action = v);
                  await _applyFilters();
                },
              ),
            ),
            SizedBox(
              width: 260,
              child: TextField(
                controller: _createdByCtrl,
                decoration: const InputDecoration(
                  labelText: 'CreatedBy',
                  hintText: 'UUID',
                ),
                onSubmitted: (_) => _applyFilters(),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _pickDateRange,
              icon: const Icon(Icons.date_range_outlined),
              label: Text(dateLabel),
            ),
            FilledButton.icon(
              onPressed: _applyFilters,
              icon: const Icon(Icons.filter_alt_outlined),
              label: const Text('Filtrele'),
            ),
            TextButton.icon(
              onPressed: _clearFilters,
              icon: const Icon(Icons.clear),
              label: const Text('Temizle'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListArea(
    BuildContext context,
    AsyncValue<AuditLogsViewState> async,
    List<AuditLogEntry> items,
  ) {
    if (async.isLoading && items.isEmpty) {
      return const AppLoadingState(message: 'Yükleniyor...');
    }

    if (async.hasError && items.isEmpty) {
      return AppErrorState(
        message: AppException.messageOf(async.error!),
        onRetry: () {
          final filters = ref.read(auditLogsProvider.notifier).currentFilters;
          ref.read(auditLogsProvider.notifier).reloadWithFilters(filters);
        },
      );
    }

    if (items.isEmpty) {
      return AppEmptyState(
        title: 'Kayıt yok',
        subtitle: 'Audit kaydı bulunamadı.',
        action: TextButton.icon(
          onPressed: () {
            final filters = ref.read(auditLogsProvider.notifier).currentFilters;
            ref.read(auditLogsProvider.notifier).reloadWithFilters(filters);
          },
          icon: const Icon(Icons.refresh),
          label: const Text('Yenile'),
        ),
      );
    }

    return SingleChildScrollView(
      padding: AppSpacing.screenPadding,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Tarih')),
            DataColumn(label: Text('User')),
            DataColumn(label: Text('Entity')),
            DataColumn(label: Text('Action')),
            DataColumn(label: Text('Entity ID')),
            DataColumn(label: Text('')),
          ],
          rows: items
              .map(
                (e) => DataRow(
                  cells: [
                    DataCell(Text(formatDateTime(e.createdAt))),
                    DataCell(Text(e.createdBy)),
                    DataCell(Text(e.entity)),
                    DataCell(Text(e.action)),
                    DataCell(_buildEntityIdCell(context, e)),
                    DataCell(
                      IconButton(
                        tooltip: 'Detay',
                        icon: const Icon(Icons.visibility_outlined),
                        onPressed: () => _openDetailDialog(context, e),
                      ),
                    ),
                  ],
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }

  Widget _buildEntityIdCell(BuildContext context, AuditLogEntry entry) {
    final entity = entry.entity.trim().toLowerCase();
    final id = entry.entityId;

    String? path;

    switch (entity) {
      case 'customers':
        path = '/admin/customers/$id';
        break;
      case 'orders':
        path = '/admin/orders/$id';
        break;
      case 'invoices':
        path = '/admin/invoices/$id';
        break;
    }

    if (path == null) {
      return Text(id);
    }

    final theme = Theme.of(context);
    return InkWell(
      onTap: () => context.go(path!),
      child: Text(
        id,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  Widget _buildPaginationBar(
    BuildContext context,
    AsyncValue<AuditLogsViewState> async,
  ) {
    final data = async.valueOrNull;
    final isLoadingMore = data?.isLoadingMore ?? false;
    final hasMore = data?.hasMore ?? false;

    return Row(
      children: [
        if (isLoadingMore) ...[
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          const Text('Yükleniyor...'),
        ],
        const Spacer(),
        TextButton.icon(
          onPressed: () {
            final filters = ref.read(auditLogsProvider.notifier).currentFilters;
            ref.read(auditLogsProvider.notifier).reloadWithFilters(filters);
          },
          icon: const Icon(Icons.refresh),
          label: const Text('Yenile'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: (hasMore && !isLoadingMore)
              ? () async {
                  final err = await ref
                      .read(auditLogsProvider.notifier)
                      .loadMore();
                  if (!mounted) return;
                  if (err == null) return;
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Yükleme hatası: ${AppException.messageOf(err)}',
                      ),
                    ),
                  );
                }
              : null,
          icon: const Icon(Icons.expand_more),
          label: Text(hasMore ? 'Daha fazla yükle' : 'Bitti'),
        ),
      ],
    );
  }

  Future<void> _openDetailDialog(BuildContext context, AuditLogEntry entry) async {
    final oldText = _prettyJson(entry.oldValue);
    final newText = _prettyJson(entry.newValue);

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Audit Detayı'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tarih: ${formatDateTime(entry.createdAt)}'),
                  const SizedBox(height: 8),
                  Text('User: ${entry.createdBy}'),
                  Text('Entity: ${entry.entity}'),
                  Text('Action: ${entry.action}'),
                  Text('Entity ID: ${entry.entityId}'),
                  const SizedBox(height: 16),
                  const Text(
                    'Old Value',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 220,
                    child: SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SelectableText(oldText),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'New Value',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 220,
                    child: SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SelectableText(newText),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Kapat'),
            ),
          ],
        );
      },
    );
  }

  String _prettyJson(Object? value) {
    if (value == null) return '-';
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(value);
    } catch (_) {
      return value.toString();
    }
  }
}
