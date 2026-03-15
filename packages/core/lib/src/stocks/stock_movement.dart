class StockMovement {
  const StockMovement({
    required this.id,
    required this.stockId,
    required this.type,
    required this.qty,
    required this.createdAt,
    this.note,
    this.createdBy,
  });

  final String id;
  final String stockId;
  /// 'in', 'out' veya 'adjust'
  final String type;
  final num qty;
  final String? note;
  final DateTime createdAt;
  final String? createdBy;

  factory StockMovement.fromMap(Map<String, dynamic> map) {
    final dynamic qtyRaw = map['qty'];
    final num qty;
    if (qtyRaw is num) {
      qty = qtyRaw;
    } else {
      qty = num.parse(qtyRaw.toString());
    }

    final dynamic createdAtRaw = map['created_at'];
    late final DateTime createdAt;
    if (createdAtRaw is DateTime) {
      createdAt = createdAtRaw;
    } else if (createdAtRaw is String) {
      createdAt = DateTime.parse(createdAtRaw);
    } else {
      createdAt = DateTime.parse(createdAtRaw.toString());
    }

    return StockMovement(
      id: map['id'] as String,
      stockId: map['stock_id'] as String,
      type: map['movement_type'] as String,
      qty: qty,
      note: map['note'] as String?,
      createdAt: createdAt,
      createdBy: map['created_by'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'stock_id': stockId,
      'movement_type': type,
      'qty': qty,
      'note': note,
      'created_at': createdAt.toIso8601String(),
      'created_by': createdBy,
    };
  }
}
