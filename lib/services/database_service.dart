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
          } catch (_) {}
        }
      },
    );
  }

  Future<void> _insertSamplePoints(Database db) async {
    final samples = [
      // Ankara Örnekleri
      {
        'id': _uuid.v4(),
        'title': 'Atatürk Orman Çiftliği',
        'description': 'Yeşil alanlar ve tarihi çiftlik binalarıyla harika bir yürüyüş rotası.',
        'latitude': 39.9334,
        'longitude': 32.8120,
        'category': 0, // nature
        'likes': 142,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'isUserAdded': 0,
        'addedByNickname': 'gezgin_can',
        'isPetFriendly': 1,
      },
      {
        'id': _uuid.v4(),
        'title': 'Botanik Kafe',
        'description': 'Yemyeşil bir ortamda enfes kahveler sunan gizli kafe.',
        'latitude': 39.9250,
        'longitude': 32.8300,
        'category': 1, // cafe
        'likes': 89,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'isUserAdded': 0,
        'addedByNickname': 'kahvesever',
        'isPetFriendly': 1,
      },
      {
        'id': _uuid.v4(),
        'title': 'Gizli Kule',
        'description': 'Şehrin panoramik görüntüsünü veren eski bir kule. Az kişi bilir!',
        'latitude': 39.9450,
        'longitude': 32.8200,
        'category': 3, // mystery
        'likes': 234,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'isUserAdded': 0,
        'addedByNickname': 'kesif_ustasi',
        'isPetFriendly': 0,
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

  Future<void> insertPoint(DiscoveryPoint point) async {
    try {
      final db = await database;
      await db.insert('discovery_points', point.toMap());
    } catch (e) {
      print('Yerel SQLite ekleme hatası: $e');
      rethrow;
    }

    // Supabase eşitlemesini arka planda başlat (UI'ı kilitlememek için await etmiyoruz)
    _syncToSupabase(point);
  }

  void _syncToSupabase(DiscoveryPoint point) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
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
            })
            .timeout(const Duration(seconds: 10));
      }
    } catch (e) {
      print('Supabase arka plan eşitleme hatası: $e');
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
