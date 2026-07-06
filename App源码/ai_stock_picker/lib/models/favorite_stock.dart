/// 收藏股票模型
class FavoriteStock {
  final String id;
  final String category;
  final String symbol;
  final String name;
  final String market;
  final double price;
  final double changePct;
  final DateTime addedAt;

  const FavoriteStock({
    required this.id,
    required this.category,
    required this.symbol,
    required this.name,
    required this.market,
    required this.price,
    required this.changePct,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category': category,
      'symbol': symbol,
      'name': name,
      'market': market,
      'price': price,
      'changePct': changePct,
      'addedAt': addedAt.toIso8601String(),
    };
  }

  factory FavoriteStock.fromJson(Map<String, dynamic> json) {
    return FavoriteStock(
      id: json['id'] as String,
      category: json['category'] as String,
      symbol: json['symbol'] as String,
      name: json['name'] as String,
      market: json['market'] as String,
      price: (json['price'] as num).toDouble(),
      changePct: (json['changePct'] as num).toDouble(),
      addedAt: DateTime.parse(json['addedAt'] as String),
    );
  }

  FavoriteStock copyWith({
    String? id,
    String? category,
    String? symbol,
    String? name,
    String? market,
    double? price,
    double? changePct,
    DateTime? addedAt,
  }) {
    return FavoriteStock(
      id: id ?? this.id,
      category: category ?? this.category,
      symbol: symbol ?? this.symbol,
      name: name ?? this.name,
      market: market ?? this.market,
      price: price ?? this.price,
      changePct: changePct ?? this.changePct,
      addedAt: addedAt ?? this.addedAt,
    );
  }
}
