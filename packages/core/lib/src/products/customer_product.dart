class CustomerProduct {
  const CustomerProduct({
    required this.stockId,
    required this.name,
    required this.code,
    this.brand,
    this.imagePath,
    this.taxRate,
    this.effectivePrice,
    this.baseUnitPrice = 0,
    this.baseUnitName = 'Adet',
    this.packUnitName,
    this.packMultiplier,
    this.packPrice,
    this.boxUnitName,
    this.boxMultiplier,
    this.boxPrice,
    this.barcode,
    this.barcodeText,
    this.groupName,
    this.subgroupName,
    this.subsubgroupName,
  });

  final String stockId;
  final String name;
  final String code;
  final String? brand;
  final String? imagePath;
  final double? taxRate;
  final double? effectivePrice;
  final double baseUnitPrice;
  final String baseUnitName;
  final String? packUnitName;
  final double? packMultiplier;
    final double? packPrice;
    final String? boxUnitName;
    final double? boxMultiplier;
    final double? boxPrice;
  final String? barcode;
  final String? barcodeText;
  final String? groupName;
  final String? subgroupName;
  final String? subsubgroupName;

  factory CustomerProduct.fromMap(Map<String, dynamic> map) {
    // View tarafında price_tier mantığı uygulanmış tekil bir fiyat alanı
    // bulunur. Eski sürümlerde bu alan `unit_price` olarak, yeni
    // sürümlerde ise `price` olarak adlandırılabilir. Burada her iki
    // olasılığı da destekleyip tek bir "etkin fiyat"e indiriyoruz.
    final num? rawPrice =
      (map['price'] as num?) ?? (map['unit_price'] as num?);

    // Baz birim fiyatı için de önce explicit base_unit_price, ardından
    // price/unit_price değerlerini tercih ediyoruz.
    final num? rawBaseUnitPrice =
      (map['base_unit_price'] as num?) ?? rawPrice;

    final rawBaseUnitName = map['base_unit_name'] as String?;
    final normalizedBaseUnitName =
        (rawBaseUnitName == null || rawBaseUnitName.trim().isEmpty)
            ? 'Adet'
            : rawBaseUnitName.trim();

    final rawPackUnitName = map['pack_unit_name'] as String?;
    final normalizedPackUnitName =
        (rawPackUnitName == null || rawPackUnitName.trim().isEmpty)
            ? null
            : rawPackUnitName.trim();

    final rawBoxUnitName = map['box_unit_name'] as String?;
    final normalizedBoxUnitName =
      (rawBoxUnitName == null || rawBoxUnitName.trim().isEmpty)
        ? null
        : rawBoxUnitName.trim();

    return CustomerProduct(
      stockId: map['stock_id'] as String,
      name: map['name'] as String,
      code: map['code'] as String,
      brand: map['brand'] as String?,
      imagePath: map['image_path'] as String?,
      taxRate: (map['tax_rate'] as num?)?.toDouble(),
      // price_tier mantığı view içinde uygulandığı için burada üretilen
      // effectivePrice, müşteriye gösterilecek "tekil fiyat"tir.
      effectivePrice: rawPrice?.toDouble(),
      baseUnitPrice: rawBaseUnitPrice?.toDouble() ?? 0,
      baseUnitName: normalizedBaseUnitName,
      packUnitName: normalizedPackUnitName,
      packMultiplier: (map['pack_multiplier'] as num?)?.toDouble(),
      packPrice: (map['pack_price'] as num?)?.toDouble(),
      boxUnitName: normalizedBoxUnitName,
      boxMultiplier: (map['box_multiplier'] as num?)?.toDouble(),
      boxPrice: (map['box_price'] as num?)?.toDouble(),
      barcode: map['barcode'] as String?,
      barcodeText: map['barcode_text'] as String?,
      groupName: map['group_name'] as String?,
      subgroupName: map['subgroup_name'] as String?,
      subsubgroupName: map['subsubgroup_name'] as String?,
    );
  }
}
