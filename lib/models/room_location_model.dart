class RoomLocation {
  final String id;
  final String buildingCode;
  final List<String> keywords;
  final String roomName;
  final String directions;

  RoomLocation({
    required this.id,
    required this.buildingCode,
    required this.keywords,
    required this.roomName,
    required this.directions,
  });

  factory RoomLocation.fromJson(Map<String, dynamic> json) {
    return RoomLocation(
      id: json['id'] as String,
      buildingCode: json['building_code'] as String,
      keywords: List<String>.from(json['keywords'] ?? []),
      roomName: json['room_name'] as String,
      directions: json['directions'] as String,
    );
  }
}