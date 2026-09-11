// Keşif Noktası Modeli
class DiscoveryPoint {
  final String id;
  final String title;
  final String description;
  final double latitude;
  final double longitude;
  final PointCategory category;
  final String? imagePath;
  final int likes;
  final DateTime createdAt;
  final bool isUserAdded;
  final String? addedByNickname;
  final bool isPetFriendly;
  final bool isSponsored;
  final String? discountCode;
  final String? discountNote;

  DiscoveryPoint({
    required this.id,
    required this.title,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.category,
    this.imagePath,
    this.likes = 0,
    required this.createdAt,
    this.isUserAdded = false,
    this.addedByNickname,
    this.isPetFriendly = false,
    this.isSponsored = false,
    this.discountCode,
    this.discountNote,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'category': category.index,
      'imagePath': imagePath,
      'likes': likes,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'isUserAdded': isUserAdded ? 1 : 0,
      'addedByNickname': addedByNickname,
      'isPetFriendly': isPetFriendly ? 1 : 0,
      'isSponsored': isSponsored ? 1 : 0,
      'discountCode': discountCode,
      'discountNote': discountNote,
    };
  }

  factory DiscoveryPoint.fromMap(Map<String, dynamic> map) {
    return DiscoveryPoint(
      id: (map['id'] ?? '') as String,
      title: (map['title'] ?? '') as String,
      description: (map['description'] ?? '') as String,
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      category: PointCategory.values[(map['category'] as int?) ?? 0],
      imagePath: (map['imagePath'] ?? map['image_url']) as String?,
      likes: (map['likes'] ?? 0) as int,
      createdAt: map['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int)
          : (map['created_at'] != null
              ? DateTime.parse(map['created_at'] as String)
              : DateTime.now()),
      isUserAdded: map['isUserAdded'] == 1,
      addedByNickname: (map['addedByNickname'] ?? map['added_by_nickname']) as String?,
      isPetFriendly: map['isPetFriendly'] == 1 || map['is_pet_friendly'] == true,
      isSponsored: map['isSponsored'] == 1 || map['is_sponsored'] == true,
      discountCode: map['discountCode'] as String? ?? map['discount_code'] as String?,
      discountNote: map['discountNote'] as String? ?? map['discount_note'] as String?,
    );
  }
}

// Kayıtlı Rota Modeli
class SavedRoute {
  final String id;
  final String name;
  final List<RoutePoint> points;
  final double distanceMeters;
  final int durationSeconds;
  final DateTime recordedAt;

  SavedRoute({
    required this.id,
    required this.name,
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.recordedAt,
  });

  String get formattedDistance {
    if (distanceMeters < 1000) {
      return '${distanceMeters.toStringAsFixed(0)} m';
    }
    return '${(distanceMeters / 1000).toStringAsFixed(2)} km';
  }

  String get formattedDuration {
    final hours = durationSeconds ~/ 3600;
    final minutes = (durationSeconds % 3600) ~/ 60;
    final seconds = durationSeconds % 60;
    if (hours > 0) return '${hours}s ${minutes}d';
    if (minutes > 0) return '${minutes}d ${seconds}s';
    return '${seconds}s';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'points': points.map((p) => p.toJson()).toList(),
      'distanceMeters': distanceMeters,
      'durationSeconds': durationSeconds,
      'recordedAt': recordedAt.millisecondsSinceEpoch,
    };
  }
}

// Rota Noktası
class RoutePoint {
  final double latitude;
  final double longitude;
  final double? altitude;
  final DateTime timestamp;

  RoutePoint({
    required this.latitude,
    required this.longitude,
    this.altitude,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'lat': latitude,
    'lng': longitude,
    'alt': altitude,
    'ts': timestamp.millisecondsSinceEpoch,
  };

  factory RoutePoint.fromJson(Map<String, dynamic> j) => RoutePoint(
    latitude: j['lat'],
    longitude: j['lng'],
    altitude: j['alt'],
    timestamp: DateTime.fromMillisecondsSinceEpoch(j['ts']),
  );
}

// Kategori Enum
enum PointCategory {
  cafe,
  restaurant,
  photo,
  viewpoint,
  park,
  historical,
  liveMusic,
  workFriendly;

  String get labelTR {
    switch (this) {
      case PointCategory.cafe: return 'Kafe';
      case PointCategory.restaurant: return 'Restaurant';
      case PointCategory.photo: return 'Fotoğraf Noktası';
      case PointCategory.viewpoint: return 'Manzara';
      case PointCategory.park: return 'Park';
      case PointCategory.historical: return 'Tarihi Yer';
      case PointCategory.liveMusic: return 'Canlı Müzik';
      case PointCategory.workFriendly: return 'Çalışmaya Uygun';
    }
  }

  String get emoji {
    switch (this) {
      case PointCategory.cafe: return '☕';
      case PointCategory.restaurant: return '🍽️';
      case PointCategory.photo: return '📸';
      case PointCategory.viewpoint: return '🌅';
      case PointCategory.park: return '🌳';
      case PointCategory.historical: return '🏛️';
      case PointCategory.liveMusic: return '🎸';
      case PointCategory.workFriendly: return '💻';
    }
  }

  int get colorValue {
    switch (this) {
      case PointCategory.cafe: return 0xFF8D6E63;
      case PointCategory.restaurant: return 0xFFFF7043;
      case PointCategory.photo: return 0xFF00BCD4;
      case PointCategory.viewpoint: return 0xFFFF5722;
      case PointCategory.park: return 0xFF4CAF50;
      case PointCategory.historical: return 0xFF9C27B0;
      case PointCategory.liveMusic: return 0xFFE91E8C;
      case PointCategory.workFriendly: return 0xFF3F51B5;
    }
  }
}
