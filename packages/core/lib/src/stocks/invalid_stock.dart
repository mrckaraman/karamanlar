class InvalidStock {
  const InvalidStock({
    required this.id,
    required this.code,
    required this.name,
    this.barcode,
    this.packBarcode,
    this.boxBarcode,
    this.packQty,
    this.boxQty,
    required this.invalidReason,
  });

  final String id;
  final String code;
  final String name;
  final String? barcode;
  final String? packBarcode;
  final String? boxBarcode;
  final int? packQty;
  final int? boxQty;
  final String invalidReason;

  factory InvalidStock.fromMap(Map<String, dynamic> map) {
    return InvalidStock(
      id: map['id'] as String,
      code: map['code'] as String,
      name: map['name'] as String,
      barcode: map['barcode'] as String?,
      packBarcode: map['pack_barcode'] as String?,
      boxBarcode: map['box_barcode'] as String?,
      packQty: map['pack_qty'] as int?,
      boxQty: map['box_qty'] as int?,
      invalidReason: map['invalid_reason'] as String,
    );
  }
}
