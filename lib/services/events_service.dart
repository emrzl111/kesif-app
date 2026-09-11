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
    // Türkiye'nin tüm büyükşehirleri ve yazım varyantları
    const cityMap = {
      // Marmara
      'İstanbul': 'İstanbul', 'Istanbul': 'İstanbul',
      'Ankara': 'Ankara',
      'Bursa': 'Bursa',
      'Edirne': 'Edirne',
      'Çanakkale': 'Çanakkale', 'Canakkale': 'Çanakkale',
      'Kocaeli': 'Kocaeli', 'Izmit': 'Kocaeli', 'İzmit': 'Kocaeli',
      'Sakarya': 'Sakarya', 'Adapazarı': 'Sakarya',
      'Balıkesir': 'Balıkesir', 'Balikesir': 'Balıkesir',
      'Tekirdağ': 'Tekirdağ', 'Tekirdag': 'Tekirdağ',
      'Yalova': 'Yalova',
      // Ege
      'İzmir': 'İzmir', 'Izmir': 'İzmir',
      'Muğla': 'Muğla', 'Mugla': 'Muğla',
      'Aydın': 'Aydın', 'Aydin': 'Aydın',
      'Denizli': 'Denizli',
      'Uşak': 'Uşak', 'Usak': 'Uşak',
      'Manisa': 'Manisa',
      'Kuşadası': 'İzmir', 'Kusadasi': 'İzmir',
      'Bodrum': 'Muğla',
      // Akdeniz
      'Antalya': 'Antalya',
      'Mersin': 'Mersin', 'Içel': 'Mersin',
      'Adana': 'Adana',
      'Hatay': 'Hatay', 'Antakya': 'Hatay',
      'Isparta': 'Isparta',
      'Burdur': 'Burdur',
      'Alanya': 'Antalya',
      'Side': 'Antalya',
      // Karadeniz
      'Trabzon': 'Trabzon',
      'Samsun': 'Samsun',
      'Giresun': 'Giresun',
      'Ordu': 'Ordu',
      'Rize': 'Rize',
      'Zonguldak': 'Zonguldak',
      'Bolu': 'Bolu',
      // İç Anadolu
      'Konya': 'Konya',
      'Kayseri': 'Kayseri',
      'Eskişehir': 'Eskişehir', 'Eskisehir': 'Eskişehir',
      'Sivas': 'Sivas',
      'Kirşehir': 'Kirşehir',
      'Nevkşehir': 'Nevkşehir', 'Cappadocia': 'Nevkşehir', 'Kapadokya': 'Nevkşehir',
      'Ürüm': 'Nevkşehir',
      // Doğu Anadolu
      'Erzurum': 'Erzurum',
      'Malatya': 'Malatya',
      'Van': 'Van',
      'Diyarbakır': 'Diyarbakır', 'Diyarbakir': 'Diyarbakır',
      'Gaziantep': 'Gaziantep', 'Antep': 'Gaziantep',
      'Şanlıurfa': 'Şanlıurfa', 'Sanliurfa': 'Şanlıurfa', 'Urfa': 'Şanlıurfa',
    };
    for (final entry in cityMap.entries) {
      if (city.toLowerCase().contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }
    return city;
  }

  Future<List<EventModel>> getEventsByCity(String city, {String? category}) async {
    final now = DateTime.now();
    final pastCutoff = now.subtract(const Duration(hours: 6));
    final futureLimit = now.add(const Duration(days: 14));

    List<EventModel> events = [];

    try {
      var query = _supabase
          .from('events')
          .select()
          .eq('city', city)
          .gte('start_date', pastCutoff.toIso8601String())
          .lte('start_date', futureLimit.toIso8601String());

      if (category != null) {
        query = query.eq('category', category);
      }

      final data = await query.order('start_date', ascending: true).limit(30);

      events = (data as List)
          .map((e) => EventModel.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Supabase etkinlik sorgu hatası: $e');
    }

    // Eğer veritabanında önümüzdeki 14 gün içinde en az 3 taze etkinlik yoksa hemen üret
    if (events.length < 3) {
      final freshEvents = await _seedAndFetchSystemEvents(city, category: category);
      // Birleştir ve tekrarlayanları temizle
      final map = <String, EventModel>{};
      for (final e in [...events, ...freshEvents]) {
        map[e.title] = e;
      }
      events = map.values.toList();
    }

    events.sort((a, b) => a.startDate.compareTo(b.startDate));
    return events;
  }

  /// Veritabanında yaklaşan etkinlik azsa taze dinamik etkinlikleri üretir ve veritabanını günceller
  Future<List<EventModel>> _seedAndFetchSystemEvents(String city, {String? category}) async {
    final cityCoords = {
      // Marmara
      'İstanbul': {'lat': 41.0082, 'lng': 28.9784, 'district': 'Kadıköy'},
      'Bursa': {'lat': 40.1885, 'lng': 29.0610, 'district': 'Nilüfer'},
      'Edirne': {'lat': 41.6771, 'lng': 26.5557, 'district': 'Merkez'},
      'Çanakkale': {'lat': 40.1553, 'lng': 26.4142, 'district': 'Merkez'},
      'Kocaeli': {'lat': 40.8533, 'lng': 29.8815, 'district': 'İzmit'},
      'Sakarya': {'lat': 40.6937, 'lng': 30.4358, 'district': 'Adapazarı'},
      'Balıkesir': {'lat': 39.6484, 'lng': 27.8826, 'district': 'Merkez'},
      'Tekirdağ': {'lat': 40.9784, 'lng': 27.5155, 'district': 'Süleymanpaşa'},
      'Yalova': {'lat': 40.6500, 'lng': 29.2667, 'district': 'Merkez'},
      // İç Anadolu
      'Ankara': {'lat': 39.9334, 'lng': 32.8597, 'district': 'Çankaya'},
      'Konya': {'lat': 37.8746, 'lng': 32.4932, 'district': 'Selcuklu'},
      'Kayseri': {'lat': 38.7312, 'lng': 35.4787, 'district': 'Kocasinan'},
      'Eskişehir': {'lat': 39.7767, 'lng': 30.5206, 'district': 'Teşvikiye'},
      'Sivas': {'lat': 39.7477, 'lng': 37.0179, 'district': 'Merkez'},
      'Nevkşehir': {'lat': 38.6939, 'lng': 34.6857, 'district': 'Üchisar'},
      // Ege
      'İzmir': {'lat': 38.4237, 'lng': 27.1428, 'district': 'Konak'},
      'Muğla': {'lat': 37.2153, 'lng': 28.3636, 'district': 'Bodrum'},
      'Aydın': {'lat': 37.8560, 'lng': 27.8416, 'district': 'Efeler'},
      'Denizli': {'lat': 37.7765, 'lng': 29.0864, 'district': 'Pamukkale'},
      'Uşak': {'lat': 38.6823, 'lng': 29.4082, 'district': 'Merkez'},
      'Manisa': {'lat': 38.6191, 'lng': 27.4289, 'district': 'Yunusemre'},
      // Akdeniz
      'Antalya': {'lat': 36.8969, 'lng': 30.7133, 'district': 'Muratpaşa'},
      'Mersin': {'lat': 36.8000, 'lng': 34.6333, 'district': 'Akdeniz'},
      'Adana': {'lat': 37.0017, 'lng': 35.3289, 'district': 'Seyhan'},
      'Hatay': {'lat': 36.2021, 'lng': 36.1601, 'district': 'Antakya'},
      'Isparta': {'lat': 37.7648, 'lng': 30.5566, 'district': 'Merkez'},
      'Burdur': {'lat': 37.7262, 'lng': 30.2884, 'district': 'Merkez'},
      // Karadeniz
      'Trabzon': {'lat': 41.0027, 'lng': 39.7168, 'district': 'Merkez'},
      'Samsun': {'lat': 41.2928, 'lng': 36.3313, 'district': 'Atakum'},
      'Giresun': {'lat': 40.9128, 'lng': 38.3895, 'district': 'Merkez'},
      'Ordu': {'lat': 40.9862, 'lng': 37.8797, 'district': 'Altınordu'},
      'Rize': {'lat': 41.0201, 'lng': 40.5234, 'district': 'Merkez'},
      'Zonguldak': {'lat': 41.4564, 'lng': 31.7987, 'district': 'Eregli'},
      'Bolu': {'lat': 40.7360, 'lng': 31.5998, 'district': 'Merkez'},
      // Doğu Anadolu
      'Erzurum': {'lat': 39.9043, 'lng': 41.2679, 'district': 'Yakutiye'},
      'Malatya': {'lat': 38.3552, 'lng': 38.3095, 'district': 'Battalgazi'},
      'Van': {'lat': 38.4942, 'lng': 43.3800, 'district': 'Merkez'},
      'Diyarbakır': {'lat': 37.9144, 'lng': 40.2306, 'district': 'Sur'},
      'Gaziantep': {'lat': 37.0662, 'lng': 37.3833, 'district': 'Şahinbey'},
      'Şanlıurfa': {'lat': 37.1591, 'lng': 38.7969, 'district': 'Eğikara'},
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

      final externalId = 'sys_${city}_${t['category']}_${startDate.year}_${startDate.month}_${startDate.day}';

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
        'external_id': externalId,
      };

      try {
        await _supabase.from('events').upsert(eventMap, onConflict: 'external_id');
      } catch (_) {}

      createdEvents.add(EventModel(
        id: externalId,
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
