import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import '../shared/models/models.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Future<Database>? _dbFuture;
  final _uuid = const Uuid();

  Future<Database> get database async {
    _dbFuture ??= _initDb();
    return _dbFuture!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'kesif.db');
    return openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE discovery_points (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            description TEXT,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            category INTEGER NOT NULL,
            imagePath TEXT,
            likes INTEGER DEFAULT 0,
            createdAt INTEGER NOT NULL,
            isUserAdded INTEGER DEFAULT 0,
            addedByNickname TEXT,
            isPetFriendly INTEGER DEFAULT 0,
            isSponsored INTEGER DEFAULT 0,
            discountCode TEXT,
            discountNote TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE saved_routes (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            pointsJson TEXT NOT NULL,
            distanceMeters REAL NOT NULL,
            durationSeconds INTEGER NOT NULL,
            recordedAt INTEGER NOT NULL
          )
        ''');
        // Örnek keşif noktaları ekle
        await _insertSamplePoints(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute('ALTER TABLE discovery_points ADD COLUMN isPetFriendly INTEGER DEFAULT 0');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE discovery_points ADD COLUMN addedByNickname TEXT');
          } catch (_) {}
        }
        if (oldVersion < 3) {
          try {
            await db.execute('ALTER TABLE discovery_points ADD COLUMN isSponsored INTEGER DEFAULT 0');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE discovery_points ADD COLUMN discountCode TEXT');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE discovery_points ADD COLUMN discountNote TEXT');
          } catch (_) {}
        }
      },
      onOpen: (db) async {
        // Mevcut sütunları PRAGMA ile kontrol et, eksik olanları ekle
        final tableInfo = await db.rawQuery('PRAGMA table_info(discovery_points)');
        final existingColumns = tableInfo.map((r) => r['name'] as String).toSet();

        final missingColumns = <String, String>{
          'isPetFriendly': 'INTEGER DEFAULT 0',
          'addedByNickname': 'TEXT',
          'isSponsored': 'INTEGER DEFAULT 0',
          'discountCode': 'TEXT',
          'discountNote': 'TEXT',
        };

        for (final entry in missingColumns.entries) {
          if (!existingColumns.contains(entry.key)) {
            try {
              await db.execute(
                'ALTER TABLE discovery_points ADD COLUMN ${entry.key} ${entry.value}',
              );
            } catch (e) {
              print('Sütun eklenemedi (${entry.key}): $e');
            }
          }
        }
      },
    );
  }

  Future<void> _insertSamplePoints(Database db) async {
    final samples = [
      // ─── İstanbul ───
      {
        'id': _uuid.v4(),
        'title': 'Galata Kulesi Manzara Noktası',
        'description': 'Galata Kulesi etrafındaki dar sokaklar ve İstanbul silüetiyle muhteşem fotoğraf açıları.',
        'latitude': 41.0255,
        'longitude': 28.9741,
        'category': 2, // photo
        'likes': 312,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'isUserAdded': 0,
        'addedByNickname': 'istanbul_gezgini',
        'isPetFriendly': 1,
      },
      {
        'id': _uuid.v4(),
        'title': 'Karaköy Gizli Kafe',
        'description': 'Boğaz manzaralı teras. Sabah kahvesi için ideal.',
        'latitude': 41.0232,
        'longitude': 28.9766,
        'category': 0, // cafe
        'likes': 189,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'isUserAdded': 0,
        'addedByNickname': 'kahvesever_ist',
        'isPetFriendly': 1,
      },
      {
        'id': _uuid.v4(),
        'title': 'Emirgan Korusu',
        'description': 'Her mevsim farklı güzellik sunan dev bir park. Lale zamanı muhteşem!',
        'latitude': 41.1014,
        'longitude': 29.0521,
        'category': 4, // park
        'likes': 421,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'isUserAdded': 0,
        'addedByNickname': 'parkci',
        'isPetFriendly': 1,
      },
      {
        'id': _uuid.v4(),
        'title': 'Balat Tarihi Sokakları',
        'description': 'Renkli evleri ve tarihi dokusuyla fotoğraf meraklılarının gözdesi.',
        'latitude': 41.0313,
        'longitude': 28.9497,
        'category': 5, // historical
        'likes': 567,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'isUserAdded': 0,
        'addedByNickname': 'tarih_tutkunu',
        'isPetFriendly': 0,
      },
      // ─── Ankara ───
      {
        'id': _uuid.v4(),
        'title': 'Atatürk Orman Çiftliği',
        'description': 'Yeşil alanlar ve tarihi çiftlik binalarıyla harika bir yürüyüş rotası.',
        'latitude': 39.9334,
        'longitude': 32.8120,
        'category': 4, // park
        'likes': 142,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'isUserAdded': 0,
        'addedByNickname': 'gezgin_can',
        'isPetFriendly': 1,
      },
      {
        'id': _uuid.v4(),
        'title': 'Anıtkabir Manzara Noktası',
        'description': 'Anıtkabir\'den şehrin muhteşem panoramik görüntüsü.',
        'latitude': 39.9255,
        'longitude': 32.8369,
        'category': 5, // historical
        'likes': 634,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'isUserAdded': 0,
        'addedByNickname': 'ankara_kesi',
        'isPetFriendly': 0,
      },
      // ─── İzmir ───
      {
        'id': _uuid.v4(),
        'title': 'Kordon Sahil Yürüyüş Yolu',
        'description': 'Günbatımı manzarasıyla İzmir\'in en güzel yürüyüş parkuru. Evcil hayvanlarla da ideal.',
        'latitude': 38.4192,
        'longitude': 27.1287,
        'category': 4, // park
        'likes': 389,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'isUserAdded': 0,
        'addedByNickname': 'izmir_sevda',
        'isPetFriendly': 1,
      },
      {
        'id': _uuid.v4(),
        'title': 'Saat Kulesi Meydanı',
        'description': 'İzmir\'in simgesi, tarihi çarşıya yakın fotoğraf noktası.',
        'latitude': 38.4122,
        'longitude': 27.1386,
        'category': 5, // historical
        'likes': 201,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'isUserAdded': 0,
        'addedByNickname': 'tarih_tutkunu',
        'isPetFriendly': 0,
      },
      // ─── Bursa ───
      {
        'id': _uuid.v4(),
        'title': 'Uludağ Manzara Tepesi',
        'description': 'Bursa ovasını tepeden gören nefes kesen manzara noktası.',
        'latitude': 40.1126,
        'longitude': 29.0607,
        'category': 3, // viewpoint
        'likes': 278,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'isUserAdded': 0,
        'addedByNickname': 'dag_sevdalisi',
        'isPetFriendly': 0,
      },
      // ─── Antalya ───
      {
        'id': _uuid.v4(),
        'title': 'Kaleiçi Tarihi Liman',
        'description': 'Roma döneminden kalma antik liman ve renkli tarihi evler.',
        'latitude': 36.8841,
        'longitude': 30.7056,
        'category': 5, // historical
        'likes': 445,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'isUserAdded': 0,
        'addedByNickname': 'akdeniz_gezgini',
        'isPetFriendly': 1,
      },
    ];

    for (final s in samples) {
      await db.insert('discovery_points', s);
    }
  }

  // Keşif Noktaları
  Future<List<DiscoveryPoint>> getAllPoints() async {
    final db = await database;
    final maps = await db.query('discovery_points', orderBy: 'createdAt DESC');
    return maps.map((m) => DiscoveryPoint.fromMap(m)).toList();
  }

  Future<List<DiscoveryPoint>> getPointsByCategory(PointCategory category) async {
    final db = await database;
    final maps = await db.query(
      'discovery_points',
      where: 'category = ?',
      whereArgs: [category.index],
    );
    return maps.map((m) => DiscoveryPoint.fromMap(m)).toList();
  }

  /// Sütunların var olduğunu garantiler — eski şemalarda yeniden eklemeye çalışır.
  /// Sütun zaten varsa SQLite hata fırlatır, catch ile sessizce geçilir.
  Future<void> _ensureColumns(Database db) async {
    final alterQueries = [
      'ALTER TABLE discovery_points ADD COLUMN isPetFriendly INTEGER DEFAULT 0',
      'ALTER TABLE discovery_points ADD COLUMN addedByNickname TEXT',
      'ALTER TABLE discovery_points ADD COLUMN isSponsored INTEGER DEFAULT 0',
      'ALTER TABLE discovery_points ADD COLUMN discountCode TEXT',
      'ALTER TABLE discovery_points ADD COLUMN discountNote TEXT',
    ];
    for (final query in alterQueries) {
      try {
        await db.execute(query);
      } catch (_) {
        // Sütun zaten var — normal, devam et
      }
    }
  }

  Future<void> insertPoint(DiscoveryPoint point, {String? remoteImageUrl}) async {
    try {
      final db = await database;
      // Savunma şema kontrolü: eski DB versiyonlarında eksik sütun olabilir
      await _ensureColumns(db);
      await db.insert(
        'discovery_points',
        point.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      // İlk denemede başarısız olduysa sütun sorununu temizleyip tekrar dene
      try {
        final db = await database;
        await _ensureColumns(db);
        // Sadece temel sütunlarla yeniden dene (yeni alanlar olmadan)
        await db.insert('discovery_points', {
          'id': point.id,
          'title': point.title,
          'description': point.description,
          'latitude': point.latitude,
          'longitude': point.longitude,
          'category': point.category.index,
          'imagePath': point.imagePath,
          'likes': point.likes,
          'createdAt': point.createdAt.millisecondsSinceEpoch,
          'isUserAdded': point.isUserAdded ? 1 : 0,
          if (point.addedByNickname != null) 'addedByNickname': point.addedByNickname,
          'isPetFriendly': point.isPetFriendly ? 1 : 0,
          'isSponsored': point.isSponsored ? 1 : 0,
          if (point.discountCode != null) 'discountCode': point.discountCode,
          if (point.discountNote != null) 'discountNote': point.discountNote,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      } catch (retryError) {
        print('SQLite yeniden deneme hatası: $retryError');
        rethrow;
      }
    }

    // Supabase eşitlemesini arka planda başlat (UI'ı kilitlememek için await etmiyoruz)
    _syncToSupabase(point, remoteImageUrl: remoteImageUrl);
  }

  void _syncToSupabase(DiscoveryPoint point, {String? remoteImageUrl}) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final nickname = await _getNicknameForUser(user.id);
        await Supabase.instance.client
            .from('discovery_points')
            .insert({
              'id': point.id,
              'user_id': user.id,
              'title': point.title,
              'description': point.description,
              'latitude': point.latitude,
              'longitude': point.longitude,
              'category': point.category.index,
              'is_pet_friendly': point.isPetFriendly,
              // Supabase Storage'dan gelen public URL (varsa)
              if (remoteImageUrl != null) 'image_url': remoteImageUrl,
              if (nickname != null) 'added_by_nickname': nickname,
            })
            .timeout(const Duration(seconds: 15));
      }
    } catch (e) {
      print('Supabase arka plan eşitleme hatası: $e');
    }
  }

  /// Kullanıcının profilinden nickname'ini çeker
  Future<String?> _getNicknameForUser(String userId) async {
    try {
      final res = await Supabase.instance.client
          .from('profiles')
          .select('nickname')
          .eq('id', userId)
          .maybeSingle();
      return res?['nickname'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> likePoint(String id) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE discovery_points SET likes = likes + 1 WHERE id = ?',
      [id],
    );
  }

  Future<void> deletePoint(String id) async {
    final db = await database;
    await db.delete('discovery_points', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<DiscoveryPoint>> getUserPoints() async {
    final db = await database;
    final maps = await db.query(
      'discovery_points',
      where: 'isUserAdded = 1',
      orderBy: 'createdAt DESC',
    );
    return maps.map((m) => DiscoveryPoint.fromMap(m)).toList();
  }

  // Rotalar
  Future<List<SavedRoute>> getAllRoutes() async {
    final db = await database;
    final maps = await db.query('saved_routes', orderBy: 'recordedAt DESC');
    return maps.map((m) {
      final pointsList = (jsonDecode(m['pointsJson'] as String) as List)
          .map((p) => RoutePoint.fromJson(p))
          .toList();
      return SavedRoute(
        id: m['id'] as String,
        name: m['name'] as String,
        points: pointsList,
        distanceMeters: m['distanceMeters'] as double,
        durationSeconds: m['durationSeconds'] as int,
        recordedAt: DateTime.fromMillisecondsSinceEpoch(m['recordedAt'] as int),
      );
    }).toList();
  }

  Future<void> saveRoute(SavedRoute route) async {
    final db = await database;
    await db.insert('saved_routes', {
      'id': route.id,
      'name': route.name,
      'pointsJson': jsonEncode(route.points.map((p) => p.toJson()).toList()),
      'distanceMeters': route.distanceMeters,
      'durationSeconds': route.durationSeconds,
      'recordedAt': route.recordedAt.millisecondsSinceEpoch,
    });
  }

  Future<void> deleteRoute(String id) async {
    final db = await database;
    await db.delete('saved_routes', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, dynamic>> getStats() async {
    final db = await database;
    final routeResult = await db.rawQuery(
      'SELECT COUNT(*) as count, SUM(distanceMeters) as totalDist FROM saved_routes'
    );
    final pointResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM discovery_points WHERE isUserAdded = 1'
    );
    return {
      'routeCount': routeResult.first['count'] ?? 0,
      'totalDistance': routeResult.first['totalDist'] ?? 0.0,
      'pointCount': pointResult.first['count'] ?? 0,
    };
  }
}
