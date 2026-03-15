class Stock {
  const Stock({
    this.id,
    required this.name,
    required this.code,
    this.barcode,
    this.packBarcode,
    this.boxBarcode,
    this.groupName,
    this.subgroupName,
    this.subsubgroupName,
    this.specialCode1,
    this.taxRate = 0,
    this.brand,
    this.isActive = true,
    this.imagePath,
    this.purchasePrice,
    this.quantity,
    this.salePrice1,
    this.salePrice2,
    this.salePrice3,
    this.salePrice4,
  });

  final String? id;
  final String name;
  final String code;
  final String? barcode;
  final String? packBarcode;
  final String? boxBarcode;
  final String? groupName;
  final String? subgroupName;
  final String? subsubgroupName;
  final String? specialCode1;
  final double taxRate;
  final String? brand;
  final bool isActive;
  final String? imagePath;
  final double? purchasePrice;
  final double? quantity;
  final double? salePrice1;
  final double? salePrice2;
  final double? salePrice3;
  final double? salePrice4;

  Stock copyWith({
    String? id,
    String? name,
    String? code,
    String? barcode,
    String? packBarcode,
    String? boxBarcode,
    String? groupName,
    String? subgroupName,
    String? subsubgroupName,
    String? specialCode1,
    double? taxRate,
    String? brand,
    bool? isActive,
    String? imagePath,
    double? purchasePrice,
    double? quantity,
    double? salePrice1,
    double? salePrice2,
    double? salePrice3,
    double? salePrice4,
  }) {
    return Stock(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      barcode: barcode ?? this.barcode,
      packBarcode: packBarcode ?? this.packBarcode,
      boxBarcode: boxBarcode ?? this.boxBarcode,
      groupName: groupName ?? this.groupName,
      subgroupName: subgroupName ?? this.subgroupName,
      subsubgroupName: subsubgroupName ?? this.subsubgroupName,
      specialCode1: specialCode1 ?? this.specialCode1,
      taxRate: taxRate ?? this.taxRate,
      brand: brand ?? this.brand,
      isActive: isActive ?? this.isActive,
      imagePath: imagePath ?? this.imagePath,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      quantity: quantity ?? this.quantity,
      salePrice1: salePrice1 ?? this.salePrice1,
      salePrice2: salePrice2 ?? this.salePrice2,
      salePrice3: salePrice3 ?? this.salePrice3,
      salePrice4: salePrice4 ?? this.salePrice4,
    );
  }

  factory Stock.fromMap(Map<String, dynamic> map) {
    return Stock(
      id: map['id'] as String?,
      name: map['name'] as String,
      code: map['code'] as String,
      barcode: map['barcode'] as String?,
      packBarcode: map['pack_barcode'] as String?,
      boxBarcode: map['box_barcode'] as String?,
      groupName: map['group_name'] as String?,
      subgroupName: map['subgroup_name'] as String?,
      subsubgroupName: map['subsubgroup_name'] as String?,
      specialCode1: map['special_code_1'] as String?,
      taxRate: (map['tax_rate'] as num?)?.toDouble() ?? 0,
      brand: map['brand'] as String?,
      isActive: (map['is_active'] as bool?) ?? true,
      imagePath: map['image_path'] as String?,
      purchasePrice: (map['purchase_price'] as num?)?.toDouble(),
      quantity: (map['quantity'] as num?)?.toDouble(),
      salePrice1: (map['sale_price_1'] as num?)?.toDouble(),
      salePrice2: (map['sale_price_2'] as num?)?.toDouble(),
      salePrice3: (map['sale_price_3'] as num?)?.toDouble(),
      salePrice4: (map['sale_price_4'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'name': name,
      'code': code,
      'barcode': barcode,
      'pack_barcode': packBarcode,
      'box_barcode': boxBarcode,
      'group_name': groupName,
      'subgroup_name': subgroupName,
      'subsubgroup_name': subsubgroupName,
      'special_code_1': specialCode1,
      'tax_rate': taxRate,
      'brand': brand,
      'is_active': isActive,
      'image_path': imagePath,
      'purchase_price': purchasePrice,
      'quantity': quantity,
      'sale_price_1': salePrice1,
      'sale_price_2': salePrice2,
      'sale_price_3': salePrice3,
      'sale_price_4': salePrice4,
    };
  }

  Map<String, dynamic> toUpdateMap() {
    final map = toInsertMap();
    map.removeWhere((key, value) => value == null);
    return map;
  }
}
