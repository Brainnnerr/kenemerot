class Building {
  final String id;
  final String name;
  final String code;
  final String category;
  final double latitude;
  final double longitude;

  const Building({
    required this.id,
    required this.name,
    required this.code,
    required this.category,
    required this.latitude,
    required this.longitude,
  });

  factory Building.fromJson(Map<String, dynamic> json) {
    return Building(
      id: json['id'] as String,
      name: json['name'] as String,
      code: json['code'] as String? ?? '',
      category: json['category'] as String? ?? 'Academic',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }
}