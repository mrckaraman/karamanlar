class StockUnit {
  const StockUnit({
    this.unitPieceBarcode,
    this.unitPackBarcode,
    this.unitCaseBarcode,
    this.packContainsPiece,
    this.caseContainsPiece,
  });

  final String? unitPieceBarcode;
  final String? unitPackBarcode;
  final String? unitCaseBarcode;
  final int? packContainsPiece;
  final int? caseContainsPiece;

  factory StockUnit.fromMap(Map<String, dynamic> map) {
    return StockUnit(
      // DB tarafında artık sadece pack_qty / box_qty / carton_qty kolonları var.
      // unit_*_barcode alanları stock_units tablosunda bulunmadığı için
      // harici kaynaklardan doldurulmadıkça her zaman null kalır.
      unitPieceBarcode: null,
      unitPackBarcode: null,
      unitCaseBarcode: null,
      packContainsPiece: map['pack_qty'] as int?,
      caseContainsPiece: map['box_qty'] as int?,
    );
  }

  Map<String, dynamic> toUpsertMap({required String stockId}) {
    return {
      'stock_id': stockId,
      // Eski unit_* ve *_contains_piece kolonları artık yok; yeni şema sadece
      // adet kolonlarını içerir.
      'pack_qty': packContainsPiece,
      'box_qty': caseContainsPiece,
      'carton_qty': null,
    };
  }
}
