/// 收藏分类模型
class FavoriteCategory {
  final String id;
  final String name;
  final DateTime? createdAt;

  const FavoriteCategory({
    required this.id,
    required this.name,
    this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  factory FavoriteCategory.fromJson(Map<String, dynamic> json) {
    return FavoriteCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
  }

  FavoriteCategory copyWith({String? id, String? name, DateTime? createdAt}) {
    return FavoriteCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
