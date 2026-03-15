class Category {
  const Category({
    required this.id,
    required this.name,
    this.code,
    this.parentId,
    this.level,
    this.isActive,
    this.sort,
  });

  final String id;
  final String name;
  final String? code;
  final String? parentId;
  final int? level;
  final bool? isActive;
  final int? sort;

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'] as String,
      name: map['name'] as String,
      code: map['code'] as String?,
      parentId: map['parent_id'] as String?,
      level: map['level'] as int?,
      isActive: map['is_active'] as bool?,
      sort: map['sort'] as int?,
    );
  }
}
