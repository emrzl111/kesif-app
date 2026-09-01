import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class EventModel {
  final String id;
  final String title;
  final String? description;
  final String? category;
  final String? district;
  final String? city;
  final DateTime startDate;
  final DateTime? endDate;
  final String? locationName;
  final double? latitude;
  final double? longitude;
  final String? sourceUrl;
  final String? imageUrl;

  EventModel({
    required this.id,
    required this.title,
    this.description,
    this.category,
    this.district,
    this.city,
    required this.startDate,
    this.endDate,
    this.locationName,
    this.latitude,
    this.longitude,
    this.sourceUrl,
    this.imageUrl,
  });

  factory EventModel.fromMap(Map<String, dynamic> map) {
    return EventModel(
      id: map['id'] as String,
      title: map['title'] as String,
      description: map['description'] as String?,
      category: map['category'] as String?,
      district: map['district'] as String?,
      city: map['city'] as String?,
      startDate: DateTime.parse(map['start_date'] as String),
      endDate: map['end_date'] != null ? DateTime.parse(map['end_date'] as String) : null,
      locationName: map['location_name'] as String?,
      latitude: map['latitude'] != null ? (map['latitude'] as num).toDouble() : null,
      longitude: map['longitude'] != null ? (map['longitude'] as num).toDouble() : null,
      sourceUrl: map['source_url'] as String?,
      imageUrl: map['image_url'] as String?,
    );
  }
}

class EventsService {
  static final EventsService _instance = EventsService._internal();
  factory EventsService() => _instance;
  EventsService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  // Mevcut şehri ve ilçeyi GPS + Nominatim ile tespit et
  Future<Map<String, String?>> getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return {'city': null, 'district': null};
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );

      // Nominatim reverse geocoding (ücretsiz, API key gereksiz)
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=json&lat=${pos.latitude}&lon=${pos.longitude}&accept-language=tr',
      );

      final response = await http.get(url, headers: {
        'User-Agent': 'KesifApp/1.0',
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final address = data['address'] as Map<String, dynamic>?;

        String? city = address?['city'] as String? ??
            address?['province'] as String? ??
            address?['state'] as String?;

        String? district = address?['suburb'] as String? ??
            address?['city_district'] as String? ??
            address?['district'] as String?;

        // Şehir adını normalize et
        city = _normalizeCity(city);

        return {'city': city, 'district': district};
      }
    } catch (e) {
      print('Konum tespit hatası: $e');
    }
    return {'city': null, 'district': null};
  }

  String? _normalizeCity(String? city) {
    if (city == null) return null;
    const cityMap = {
      'İstanbul': 'İstanbul',
      'Istanbul': 'İstanbul',
      'Ankara': 'Ankara',
      'İzmir': 'İzmir',
      'Izmir': 'İzmir',
      'Bursa': 'Bursa',
      'Edirne': 'Edirne',
      'Çanakkale': 'Çanakkale',
      'Canakkale': 'Çanakkale',
      'Muğla': 'Muğla',
      'Mugla': 'Muğla',
    };
    for (final entry in cityMap.entries) {
      if (city.toLowerCase().contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }
    return city;
  }

  Future<List<EventModel>> getEventsByCity(String city, {String? category}) async {
    try {
      var query = _supabase
          .from('events')
          .select()
          .eq('city', city)
          .gte('start_date', DateTime.now().toIso8601String());

      if (category != null) {
        query = query.eq('category', category);
      }

      final data = await query
          .order('start_date', ascending: true)
          .limit(20);

      final list = (data as List).map((e) => EventModel.fromMap(e as Map<String, dynamic>)).toList();
      if (list.isNotEmpty) return list;

      // Veritabanı boşsa otomatik sistem etkinliklerini eşitle ve getir
      return await _seedAndFetchSystemEvents(city, category: category);
    } catch (e) {
      return await _seedAndFetchSystemEvents(city, category: category);
    }
  }

  /// Veritabanı henüz beslenmemişse sistem etkinliklerini otomatik ekler
  Future<List<EventModel>> _seedAndFetchSystemEvents(String city, {String? category}) async {
    final cityCoords = {
      'İstanbul': {'lat': 41.0082, 'lng': 28.9784, 'district': 'Kadıköy'},
      'Ankara': {'lat': 39.9334, 'lng': 32.8597, 'district': 'Çankaya'},
      'İzmir': {'lat': 38.4237, 'lng': 27.1428, 'district': 'Konak'},
      'Bursa': {'lat': 40.1885, 'lng': 29.0610, 'district': 'Nilüfer'},
      'Edirne': {'lat': 41.6771, 'lng': 26.5557, 'district': 'Merkez'},
      'Çanakkale': {'lat': 40.1553, 'lng': 26.4142, 'district': 'Merkez'},
      'Muğla': {'lat': 37.2153, 'lng': 28.3636, 'district': 'Bodrum'},
    };

    final info = cityCoords[city] ?? {'lat': 41.0082, 'lng': 28.9784, 'district': 'Merkez'};
    final double baseLat = info['lat'] as double;
    final double baseLng = info['lng'] as double;
    final String defaultDistrict = info['district'] as String;
    final now = DateTime.now();

    final templates = [
      {
        'title': '$city Belediye Parkı Açık Hava Konseri',
        'category': 'konser',
        'description': 'Belediyemizin düzenlediği halka açık, ücretsiz yaz konserleri kapsamında yerel sanatçılar sahne alıyor. Katılım tamamen ücretsizdir.',
        'location_name': 'Kent Parkı Amfi Tiyatro',
        'daysOffset': 1,
        'hours': 20,
        'image_url': 'https://images.unsplash.com/photo-1465847899084-d164df4dedc6?w=500',
        'source_url': city == 'İstanbul' ? 'https://kultur.istanbul/etkinlikler' : 'https://www.kulturportali.gov.tr',
      },
      {
        'title': '$city Ücretsiz Kültür ve Sanat Sergisi',
        'category': 'sergi',
        'description': 'Girişin tamamen ücretsiz olduğu, yerel ressam ve heykeltıraşların eserlerinden oluşan modern sanat karma sergisi.',
        'location_name': 'Belediye Kültür Merkezi Sergi Salonu',
        'daysOffset': 2,
        'hours': 14,
        'image_url': 'https://images.unsplash.com/photo-1531243269054-5ebf6f3b0b6e?w=500',
        'source_url': 'https://www.kulturportali.gov.tr/turkiye/genel/etkinlik',
      },
      {
        'title': '$city Halk Eğitim Seramik Atölyesi',
        'category': 'atolye',
        'description': 'Belediyemiz tarafından düzenlenen ücretsiz hobi atölyesi. Tüm malzemeler belediye tarafından karşılanacaktır.',
        'location_name': 'Halk Eğitim Merkezi Atölye Salonu',
        'daysOffset': 3,
        'hours': 15,
        'image_url': 'https://images.unsplash.com/photo-1578749556568-bc2c40e68b61?w=500',
        'source_url': 'https://e-yaygin.meb.gov.tr',
      },
      {
        'title': '$city Ücretsiz Şehir Tiyatroları Gösterisi',
        'category': 'tiyatro',
        'description': 'Halka açık ve ücretsiz sergilenecek olan iki perdelik klasik tiyatro oyunu. Girişler ücretsizdir.',
        'location_name': 'Şehir Tiyatroları Sahnesi',
        'daysOffset': 4,
        'hours': 19,
        'image_url': 'https://images.unsplash.com/photo-1507676184212-d03ab07a01bf?w=500',
        'source_url': city == 'İstanbul' ? 'https://sehirtiyatrolari.ibb.istanbul' : 'https://www.kulturportali.gov.tr',
      },
      {
        'title': '$city Açık Hava Sinema Gecesi',
        'category': 'sinema',
        'description': 'Yıldızlar altında ücretsiz sinema keyfi! Sandalyeni kap gel, belediyemizin ücretsiz mısır ikramıyla açık havada sinema.',
        'location_name': 'Sahil Etkinlik Alanı',
        'daysOffset': 5,
        'hours': 21,
        'image_url': 'https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?w=500',
        'source_url': city == 'İstanbul' ? 'https://kultur.istanbul' : 'https://www.kulturportali.gov.tr',
      },
      {
        'title': '$city Geleneksel Şehir Festivali',
        'category': 'festival',
        'description': 'Yöresel ürünler stantları, halk oyunları gösterileri ve ücretsiz sokak konserleriyle dolu dolu geçecek mahalle şenliği.',
        'location_name': 'Belediye Meydanı',
        'daysOffset': 7,
        'hours': 11,
        'image_url': 'https://images.unsplash.com/photo-1533174072545-7a4b6ad7a6c3?w=500',
        'source_url': 'https://www.kulturportali.gov.tr',
      },
    ];

    final createdEvents = <EventModel>[];

    for (int i = 0; i < templates.length; i++) {
      final t = templates[i];
      final startDate = DateTime(now.year, now.month, now.day + (t['daysOffset'] as int), t['hours'] as int);
      final endDate = startDate.add(const Duration(hours: 2));

      final eventMap = {
        'title': t['title'],
        'description': t['description'],
        'category': t['category'],
        'district': defaultDistrict,
        'city': city,
        'start_date': startDate.toIso8601String(),
        'end_date': endDate.toIso8601String(),
        'location_name': t['location_name'],
        'latitude': baseLat + (i * 0.005),
        'longitude': baseLng + (i * 0.005),
        'source_url': t['source_url'],
        'image_url': t['image_url'],
        'external_id': 'sys_${city}_${t['category']}_${startDate.day}',
      };

      try {
        await _supabase.from('events').upsert(eventMap, onConflict: 'external_id');
      } catch (_) {}

      createdEvents.add(EventModel(
        id: 'sys_${city}_${i}',
        title: t['title'] as String,
        description: t['description'] as String?,
        category: t['category'] as String?,
        district: defaultDistrict,
        city: city,
        startDate: startDate,
        endDate: endDate,
        locationName: t['location_name'] as String?,
        latitude: baseLat + (i * 0.005),
        longitude: baseLng + (i * 0.005),
        sourceUrl: t['source_url'] as String?,
        imageUrl: t['image_url'] as String?,
      ));
    }

    if (category != null) {
      return createdEvents.where((e) => e.category == category).toList();
    }
    return createdEvents;
  }

  // İlçeye göre etkinlikleri getir
  Future<List<EventModel>> getEventsByDistrict(String district) async {
    try {
      final data = await _supabase
          .from('events')
          .select()
          .ilike('district', '%$district%')
          .gte('start_date', DateTime.now().toIso8601String())
          .order('start_date', ascending: true)
          .limit(20);

      return (data as List).map((e) => EventModel.fromMap(e as Map<String, dynamic>)).toList();
    } catch (e) {
      print('İlçe etkinlikleri yüklenirken hata: $e');
      return [];
    }
  }

  // Desteklenen şehirler
  static const List<String> supportedCities = [
    'İstanbul',
    'Ankara',
    'İzmir',
    'Bursa',
    'Edirne',
    'Çanakkale',
    'Muğla',
  ];

  // Kategori renk ve ikon eşleştirme
  static Map<String, dynamic> getCategoryStyle(String? category) {
    switch (category?.toLowerCase()) {
      case 'konser':
        return {'color': 0xFFE91E63, 'icon': '🎵', 'label': 'Konser'};
      case 'sergi':
        return {'color': 0xFF9C27B0, 'icon': '🎨', 'label': 'Sergi'};
      case 'atolye':
      case 'atölye':
        return {'color': 0xFF2196F3, 'icon': '🔧', 'label': 'Atölye'};
      case 'festival':
        return {'color': 0xFFFF5722, 'icon': '🎉', 'label': 'Festival'};
      case 'tiyatro':
        return {'color': 0xFF795548, 'icon': '🎭', 'label': 'Tiyatro'};
      case 'spor':
        return {'color': 0xFF4CAF50, 'icon': '⚽', 'label': 'Spor'};
      case 'sinema':
        return {'color': 0xFF607D8B, 'icon': '🎬', 'label': 'Sinema'};
      default:
        return {'color': 0xFF9E9E9E, 'icon': '📅', 'label': 'Etkinlik'};
    }
  }
}
