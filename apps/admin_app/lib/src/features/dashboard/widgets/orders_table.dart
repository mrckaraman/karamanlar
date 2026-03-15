// ignore_for_file: prefer_const_constructors

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../utils/formatters_tr.dart';

class OrdersTable extends StatelessWidget {
  const OrdersTable({
    super.key,
    required this.orders,
    required this.selectedOrderId,
    required this.onRowSelected,
  });

  final List<AdminOrderListEntry> orders;
  final String? selectedOrderId;
  final ValueChanged<String> onRowSelected;

  @override
  Widget build(BuildContext context) {
    const headerBg = Color(0xFFF9FAFB);
    const borderColor = Color(0xFFE5E7EB);
    const selectedBg = Color(0xFFE0F2F1);
    const primary = Color(0xFF22A38C);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 700;

        final table = Column(
          children: [
            Container(
              decoration: const BoxDecoration(
                color: headerBg,
                border: Border(
                  bottom: BorderSide(color: borderColor, width: 1),
                ),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              child: Row(
                children: const [
                  _HeaderCell(flex: 2, label: 'Sipariş No'),
                  _HeaderCell(flex: 3, label: 'Müşteri'),
                  _HeaderCell(flex: 2, label: 'Tarih'),
                  _HeaderCell(flex: 2, label: 'Tutar'),
                  _HeaderCell(flex: 2, label: 'Durum'),
                  SizedBox(width: 40),
                ],
              ),
            ),
            ...orders.map((order) {
              final selected = order.id == selectedOrderId;

              final orderNoText = _formatOrderNo(order.orderNo);
              final customerName = order.customerName;
              final dateText = formatDate(order.createdAt);
              final amountText = formatMoney(order.totalAmount);
              final statusLabel = _statusLabel(order.status);

              return InkWell(
                onTap: () {
                  onRowSelected(order.id);
                  context.go('/orders/${order.id}');
                },
                hoverColor: const Color(0xFFF9FAFB),
                child: Container(
                  decoration: BoxDecoration(
                    color: selected ? selectedBg : Colors.white,
                    border: const Border(
                      bottom: BorderSide(color: borderColor, width: 1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 56,
                        color: selected ? primary : Colors.transparent,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  orderNoText,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF111827),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  customerName,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF374151),
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  dateText,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  amountText,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF111827),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: _StatusBadge(status: statusLabel),
                                ),
                              ),
                              SizedBox(
                                width: 40,
                                child: TextButton(
                                  onPressed: () {
                                    context.go('/orders/${order.id}');
                                  },
                                  style: TextButton.styleFrom(
                                    foregroundColor:
                                        const Color(0xFF111827),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  child: const Text('Detay'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );

        Widget content = table;
        if (isNarrow) {
          content = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 700,
              child: table,
            ),
          );
        }

        return Card(child: content);
      },
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.flex, required this.label});

  final int flex;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
          color: Color(0xFF6B7280),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    late Color bg;
    late Color fg;

    if (status == 'Onay Bekliyor') {
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFF92400E);
    } else if (status == 'Hazırlanıyor') {
      bg = const Color(0xFFDBEAFE);
      fg = const Color(0xFF2563EB);
    } else {
      bg = const Color(0xFFDCFCE7);
      fg = const Color(0xFF166534);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: fg,
        ),
      ),
    );
  }
}

String _formatOrderNo(int? orderNo) {
  if (orderNo == null) return 'Sipariş';
  final padded = orderNo.toString().padLeft(6, '0');
  return 'SIP-$padded';
}

String _statusLabel(String rawStatus) {
  final value = rawStatus.trim().toLowerCase();
  switch (value) {
    case 'new':
      return 'Onay Bekliyor';
    case 'approved':
    case 'preparing':
    case 'shipped':
      return 'Hazırlanıyor';
    case 'completed':
      return 'Tamamlandı';
    case 'invoiced':
      return 'Fatura';
    case 'cancelled':
      return 'İptal';
    default:
      return rawStatus;
  }
}

