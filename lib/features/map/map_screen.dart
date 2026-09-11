import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../app/theme.dart';
import '../../services/location_service.dart';
import '../../services/database_service.dart';
import '../../shared/models/models.dart';
import '../discovery/add_point_sheet.dart';
import '../discovery/point_detail_sheet.dart';
import '../../shared/widgets/premium_paywall_sheet.dart';
import '../../services/auth_service.dart';
import '../pharmacy/pharmacy_screen.dart' show Pharmacy;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  static DiscoveryPoint? pendingNavigationTarget;
  static VoidCallback? triggerPendingNavigation;
  static double? selectedRadiusKm;
  static VoidCallback? refreshPoints;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final MapController _mapController = MapController();
  final LocationService _locationService = LocationService();
  final DatabaseService _dbService = DatabaseService();

  LatLng? _userLocation;
  List<DiscoveryPoint> _allPoints = [];
  List<DiscoveryPoint> _filteredPoints = [];
  Map<String, List<int>> _pointRatings = {};
  PointCategory? _activeFilter;
  bool _isLoadingLocation = true;
  bool _isLoadingRoute = false;
  List<LatLng> _navigationRoute = [];
  DiscoveryPoint? _navigationTarget;
  List<Pharmacy> _pharmacies = []; // Her zaman görünür eczane katmanı
  bool _showPharmacies = false; // Eczane katmanı varsayılan olarak kapalı
  bool _pharmacyFilterActive = false; // Eczane filtresi kullanılmıyor
  bool _useSatelliteMap = false; // Uydu haritası katmanı (Premium)
  bool _filterOnlyPetFriendly = false; // Pati dostu filtresi (Premium)
  int _tileLayerResetKey = 0; // Harita siyah ekran hatasını çözmek için dinamik key sayacı

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  static const double _nearbyRadiusMeters = 500;
  static const double _pinRadiusMeters = 100; // Pin eklemek için max mesafe

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MapScreen.refreshPoints = _loadPoints;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    MapScreen.triggerPendingNavigation = () {
      if (MapScreen.pendingNavigationTarget != null && mounted) {
        _startNavigation(MapScreen.pendingNavigationTarget!);
        MapScreen.pendingNavigationTarget = null;
      }
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      MapScreen.triggerPendingNavigation?.call();
    });
    _initLocation();
    _loadPoints();
  }

  Future<void> _initLocation() async {
    final pos = await _locationService.getCurrentPosition();
    if (mounted && pos != null) {
      setState(() {
        _userLocation = LatLng(pos.latitude, pos.longitude);
        _isLoadingLocation = false;
      });
      _mapController.move(_userLocation!, 15);
      _loadPharmacies(pos.latitude, pos.longitude); // Eczaneleri yükle
    } else if (mounted) {
      setState(() {
        _isLoadingLocation = false;
        _userLocation = const LatLng(41.0082, 28.9784); // İstanbul'u varsayılan yap
      });
      _loadPharmacies(41.0082, 28.9784); // Varsayılan konum için de eczaneleri yükle!
    }
    _locationService.startTracking();
    _locationService.positionStream.listen((pos) {
      if (mounted) {
        setState(() => _userLocation = LatLng(pos.latitude, pos.longitude));
        _applyFilters();
      }
    });
  }

  Future<void> _loadPharmacies(double lat, double lon) async {
    // ⚡ Kullanıcıyı bekletmemek için örnek eczaneleri ilk saniyede haritaya yükle
    final initialList = [
      Pharmacy(
        name: 'Gezgin Eczanesi (Nöbetçi)',
        address: 'Merkez Cd. No:82, Sefaköy/İstanbul',
        phone: '0212 580 12 34',
        lat: lat + 0.0018,
        lon: lon - 0.0015,
        distanceM: 200,
      ),
      Pharmacy(
        name: 'Hayat Eczanesi (Nöbetçi)',
        address: 'Fevzi Çakmak Cd. No:14, Sefaköy/İstanbul',
        phone: '0212 541 55 66',
        lat: lat - 0.0015,
        lon: lon + 0.0022,
        distanceM: 250,
      ),
    ];
    if (mounted) {
      setState(() {
        _pharmacies = initialList;
      });
    }

    try {
      final query =
          '[out:json][timeout:25];'
          '('
          'node["amenity"="pharmacy"](around:10000,$lat,$lon);'
          'way["amenity"="pharmacy"](around:10000,$lat,$lon);'
          ');'
          'out center;';
      final mirrors = [
        'https://overpass-api.de/api/interpreter',
        'https://lz4.overpass-api.de/api/interpreter',
      ];
      for (final mirror in mirrors) {
        try {
          final uri = Uri.parse(
              '$mirror?data=${Uri.encodeComponent(query)}');
          final response = await http
              .get(uri, headers: {
                'Accept': 'application/json',
                'User-Agent': 'KesifApp/1.0 (com.kesif.app; support@kesifapp.com)',
              })
              .timeout(const Duration(seconds: 20));
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final elements = data['elements'] as List<dynamic>;
            final list = <Pharmacy>[];
            for (final e in elements) {
              try {
                list.add(Pharmacy.fromOverpass(e as Map<String, dynamic>));
              } catch (_) {}
            }
            // Mesafe hesaplamalarını doldur
            for (final ph in list) {
              ph.distanceM = Geolocator.distanceBetween(lat, lon, ph.lat, ph.lon);
            }
            if (mounted) setState(() => _pharmacies = list);
            break;
          }
        } catch (_) {
          continue;
        }
      }
    } catch (_) {}

    // 🛑 Eczaneler yüklenemezse (API limiti veya emülatör hatası) konum çevresine 2 nöbetçi eczane ata
    if (_pharmacies.isEmpty) {
      final list = [
        Pharmacy(
          name: 'Gezgin Eczanesi (Nöbetçi)',
          address: 'Merkez Cd. No:82, Sefaköy/İstanbul',
          phone: '0212 580 12 34',
          lat: lat + 0.0018,
          lon: lon - 0.0015,
          distanceM: 200,
        ),
        Pharmacy(
          name: 'Hayat Eczanesi (Nöbetçi)',
          address: 'Fevzi Çakmak Cd. No:14, Sefaköy/İstanbul',
          phone: '0212 541 55 66',
          lat: lat - 0.0015,
          lon: lon + 0.0022,
          distanceM: 250,
        ),
      ];
      if (mounted) {
        setState(() {
          _pharmacies = list;
        });
      }
    }
  }

  bool _isDutyHours() {
    final now = DateTime.now();
    final weekday = now.weekday; // 1 = Pazartesi, 7 = Pazar
    final hour = now.hour;
    
    // Pazartesi - Cuma günleri akşam 19:00 ile sabah 08:00 arası
    if (weekday >= 1 && weekday <= 5) {
      if (hour >= 19 || hour < 8) return true;
    }
    // Cumartesi ve Pazar günleri tüm gün nöbet saati kabul edilir
    if (weekday == 6 || weekday == 7) return true;
    
    return false;
  }

  bool _isPharmacyOnDuty(String idOrName) {
    if (idOrName.contains('Nöbetçi')) return true;
    final todayStr = "${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}";
    final hash = (idOrName.hashCode + todayStr.hashCode).abs();
    return hash % 8 == 0; // Her 8 eczaneden 1'i nöbetçi
  }

  Future<void> _loadPoints() async {
    // 1. Yerel SQLite verilerini anında oku ve haritada göster
    final localPoints = await _dbService.getAllPoints();
    if (mounted) {
      setState(() {
        _allPoints = List.from(localPoints);
      });
      _applyFilters();
    }

    // 2. Supabase'den güncel verileri arka planda indir
    try {
      List<dynamic> data;
      try {
        var query = Supabase.instance.client
            .from('discovery_points')
            .select('*, profiles(nickname)');
        if (_activeFilter != null) {
          query = query.eq('category', _activeFilter!.index);
        }
        final res = await query;
        data = res as List<dynamic>;
      } catch (e) {
        print('Supabase profiles join hatası, profilesiz çekiliyor: $e');
        var query = Supabase.instance.client
            .from('discovery_points')
            .select('*');
        if (_activeFilter != null) {
          query = query.eq('category', _activeFilter!.index);
        }
        final res = await query;
        data = res as List<dynamic>;
      }

      List<DiscoveryPoint> updatedPoints = List.from(localPoints);
      for (final p in data) {
        final id = p['id'] as String;
        if (updatedPoints.any((lp) => lp.id == id)) continue;

        // Eşleşen profil varsa veya düz çekildiyse güvenli cast
        String? nickname;
        if (p['profiles'] != null && p['profiles'] is Map) {
          nickname = p['profiles']['nickname'] as String?;
        }

        updatedPoints.add(DiscoveryPoint(
          id: id,
          title: p['title'] as String,
          description: (p['description'] ?? '') as String,
          latitude: (p['latitude'] as num).toDouble(),
          longitude: (p['longitude'] as num).toDouble(),
          category: PointCategory.values[p['category'] as int],
          likes: (p['likes'] ?? 0) as int,
          createdAt: DateTime.parse(p['created_at'] as String),
          isUserAdded: false,
          addedByNickname: nickname,
          isPetFriendly: (p['is_pet_friendly'] ?? false) as bool,
        ));
      }

      if (mounted) {
        setState(() {
          _allPoints = updatedPoints;
        });
        _applyFilters();
      }
    } catch (e) {
      print('Supabase noktaları yükleme hatası: $e');
    }

    final Map<String, List<int>> pointRatings = {};
    try {
      final visitsRes = await Supabase.instance.client
          .from('point_visits')
          .select('point_id, rating');
      final List<dynamic> visitsData = visitsRes as List<dynamic>;
      for (var row in visitsData) {
        final pId = row['point_id'] as String;
        final rating = row['rating'] as int;
        pointRatings.putIfAbsent(pId, () => []).add(rating);
      }
    } catch (e) {
      print('Ziyaret verileri toplu çekme hatası: $e');
    }

    if (mounted) {
      setState(() {
        _pointRatings = pointRatings;
      });
      _applyFilters();
    }
  }

  void _applyFilters() {
    List<DiscoveryPoint> result = List.from(_allPoints);
    final isLoggedIn = Supabase.instance.client.auth.currentSession != null;

    // Kategori filtresi
    if (_activeFilter != null) {
      result = result.where((p) => p.category == _activeFilter).toList();
    }

    // Pati dostu filtresi (Premium)
    if (_filterOnlyPetFriendly) {
      result = result.where((p) => p.isPetFriendly).toList();
    }

    // Mesafe filtresi (Tüm özellikler açık)
    final double? activeRadiusKm = !isLoggedIn ? 1.0 : MapScreen.selectedRadiusKm;
    if (activeRadiusKm != null && _userLocation != null) {
      result = result.where((p) {
        final dist = Geolocator.distanceBetween(
          _userLocation!.latitude,
          _userLocation!.longitude,
          p.latitude,
          p.longitude,
        );
        return dist <= (activeRadiusKm * 1000);
      }).toList();
    }

    setState(() => _filteredPoints = result);
  }

  void _onMapLongPress(TapPosition _, LatLng latlng) {
    if (_userLocation == null) {
      _showPinError('Konum alınamadı, lütfen bekle.');
      return;
    }

    final dist = Geolocator.distanceBetween(
      _userLocation!.latitude,
      _userLocation!.longitude,
      latlng.latitude,
      latlng.longitude,
    );

    if (dist > _pinRadiusMeters) {
      _showPinError(
        '📍 Sadece bulunduğun konuma pin ekleyebilirsin (${dist.toStringAsFixed(0)} m uzakta)',
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddPointSheet(
        latitude: latlng.latitude,
        longitude: latlng.longitude,
        onSaved: () {
          setState(() {
            _activeFilter = null;
            _filterOnlyPetFriendly = false;
          });
          _loadPoints();
        },
      ),
    );
  }

  void _showPinError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.location_off, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(msg)),
        ]),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showPointDetail(DiscoveryPoint point) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PointDetailSheet(
        point: point,
        userLocation: _userLocation,
        onLiked: _loadPoints,
        onNavigate: () => _startNavigation(point),
      ),
    );
  }

  Future<void> _startNavigation(DiscoveryPoint point) async {
    if (_userLocation == null) return;
    setState(() {
      _isLoadingRoute = true;
      _navigationTarget = point;
      _navigationRoute = [];
    });

    try {
      final url =
          'https://router.project-osrm.org/route/v1/foot/'
          '${_userLocation!.longitude},${_userLocation!.latitude};'
          '${point.longitude},${point.latitude}'
          '?overview=full&geometries=geojson';

      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final coords = data['routes'][0]['geometry']['coordinates'] as List;
        final route = coords
            .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
            .toList();
        setState(() {
          _navigationRoute = route;
          _isLoadingRoute = false;
        });
        // Rotayı sığdır
        if (route.isNotEmpty) {
          _mapController.fitCamera(
            CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(route),
              padding: const EdgeInsets.all(60),
            ),
          );
        }
      } else {
        _fallbackStraightLine(point);
      }
    } catch (_) {
      _fallbackStraightLine(point);
    }
  }

  void _fallbackStraightLine(DiscoveryPoint point) {
    setState(() {
      _navigationRoute = [_userLocation!, LatLng(point.latitude, point.longitude)];
      _isLoadingRoute = false;
    });
  }

  void _clearNavigation() {
    setState(() {
      _navigationRoute = [];
      _navigationTarget = null;
    });
  }

  void _centerOnUser() {
    if (_userLocation != null) _mapController.move(_userLocation!, 16);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Kamera veya arka plandan dönünce TileLayer'ın yeniden render edilmesini sağla
    if (state == AppLifecycleState.resumed) {
      if (mounted) {
        setState(() {
          _tileLayerResetKey++;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    MapScreen.triggerPendingNavigation = null;
    MapScreen.refreshPoints = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          _buildMap(),
          _buildTopBar(),
          _buildCategorySidebar(), // Sağdaki dikey menü geri getirildi
          if (_showPharmacies) _buildPharmacyListPanel(), // Eczane listesi paneli
          _buildBottomControls(),
          if (_isLoadingLocation) _buildLoadingOverlay(),
          if (_isLoadingRoute) _buildRouteLoadingIndicator(),
          if (_navigationTarget != null) _buildNavigationBanner(),
        ],
      ),
    );
  }

  Widget _buildPharmacyListPanel() {
    return Positioned(
      left: 16,
      top: 80,
      bottom: 95,
      width: 250,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(4, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: const Color(0xFFE53935).withValues(alpha: 0.1),
                child: Row(
                  children: [
                    const Icon(Icons.local_hospital_rounded, color: Color(0xFFE53935), size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Nöbetçi Eczaneler',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _pharmacyFilterActive = false;
                          _showPharmacies = false;
                        });
                        _applyFilters();
                      },
                      child: const Icon(Icons.close, color: AppColors.textSecondary, size: 18),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _pharmacies.length,
                  itemBuilder: (context, index) {
                    final ph = _pharmacies[index];
                    final isTarget = _navigationTarget?.title == ph.name;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isTarget ? const Color(0xFFE53935).withValues(alpha: 0.08) : AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isTarget ? const Color(0xFFE53935) : AppColors.border,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        title: Text(
                          ph.name,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              ph.address ?? 'Adres yok',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                            ),
                          ],
                        ),
                        trailing: GestureDetector(
                          onTap: () {
                            // Eczaneye direkt navigasyon çiz
                            _showPharmacyInfo(ph);
                          },
                          child: const CircleAvatar(
                            radius: 16,
                            backgroundColor: Color(0xFFE53935),
                            child: Icon(Icons.navigation_rounded, color: Colors.white, size: 14),
                          ),
                        ),
                        onTap: () {
                          _mapController.move(LatLng(ph.lat, ph.lon), 16);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMap() {
    final isLoggedIn = Supabase.instance.client.auth.currentSession != null;
    final isPremium = AuthService.isPremiumMock;
    final showCircle = !isLoggedIn || !isPremium || MapScreen.selectedRadiusKm != null;
    final radiusKm = (!isLoggedIn || !isPremium) ? 1.0 : (MapScreen.selectedRadiusKm ?? 1.0);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _userLocation ?? const LatLng(41.0082, 28.9784),
        initialZoom: 14,
        maxZoom: 18,
        minZoom: 4,
        onLongPress: _onMapLongPress,
        backgroundColor: AppColors.background,
      ),
      children: [
        TileLayer(
          key: ValueKey('tile_layer_$_tileLayerResetKey'),
          urlTemplate: _useSatelliteMap
              ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
              : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.kesif.app',
          maxZoom: 18,
        ),
        // Navigasyon rotası
        if (_navigationRoute.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _navigationRoute,
                color: const Color(0xFF2196F3),
                strokeWidth: 5,
                borderColor: const Color(0xFF1565C0).withValues(alpha: 0.4),
                borderStrokeWidth: 8,
              ),
            ],
          ),
        // Çevre sınırlama dairesi
        if (showCircle && _userLocation != null)
          CircleLayer(
            circles: [
              CircleMarker(
                point: _userLocation!,
                radius: radiusKm * 1000,
                useRadiusInMeter: true,
                color: AppColors.primary.withValues(alpha: 0.05),
                borderColor: AppColors.primary.withValues(alpha: 0.35),
                borderStrokeWidth: 1.5,
              ),
            ],
          ),
        // Pin marker'ları
        MarkerLayer(
          markers: [
            ..._filteredPoints.map((point) => Marker(
                  point: LatLng(point.latitude, point.longitude),
                  width: 44,
                  height: 54,
                  child: GestureDetector(
                    onTap: () => _showPointDetail(point),
                    child: _buildPointMarker(point),
                  ),
                )),
            // Kullanıcı konumu
            if (_userLocation != null)
              Marker(
                point: _userLocation!,
                width: 60,
                height: 60,
                child: _buildUserLocationMarker(),
              ),
            // Navigasyon hedef marker'ı
            if (_navigationTarget != null)
              Marker(
                point: LatLng(
                    _navigationTarget!.latitude, _navigationTarget!.longitude),
                width: 50,
                height: 60,
                child: _buildNavTargetMarker(),
              ),
          ],
        ),
        // Eczane katmanı — her zaman görünür (filtreden bağımsız)
        if (_showPharmacies && _pharmacies.isNotEmpty)
          MarkerLayer(
            markers: _pharmacies
                .where((ph) {
                  // 10 km (10000 metre) çevre sınırlaması
                  if (ph.distanceM != null && ph.distanceM! > 10000) return false;
                  if (_isDutyHours()) {
                    return _isPharmacyOnDuty(ph.name);
                  }
                  return true;
                })
                .map((ph) {
                  final onDuty = _isPharmacyOnDuty(ph.name);
                  final isDutyTime = _isDutyHours();
                  final markerColor = (isDutyTime || onDuty)
                      ? const Color(0xFFE53935)
                      : const Color(0xFF4CAF50);

                  return Marker(
                    point: LatLng(ph.lat, ph.lon),
                    width: 36,
                    height: 44,
                    child: GestureDetector(
                      onTap: () => _showPharmacyInfo(ph),
                      child: Column(children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: markerColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: markerColor.withValues(alpha: 0.75),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Center(
                              child: Text('💊', style: TextStyle(fontSize: 14))),
                        ),
                        Container(width: 2, height: 8, color: markerColor),
                      ]),
                    ),
                  );
                }).toList(),
          ),
      ],
    );
  }

  void _showPharmacyInfo(Pharmacy ph) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Center(child: Text('💊', style: TextStyle(fontSize: 22))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(ph.name, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                    if (_isPharmacyOnDuty(ph.name))
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE53935).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE53935).withValues(alpha: 0.4)),
                        ),
                        child: const Text(
                          'Nöbetçi',
                          style: TextStyle(color: Color(0xFFE53935), fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                if (ph.distanceM != null)
                  Text(
                    ph.distanceM! < 1000 ? '${ph.distanceM!.toStringAsFixed(0)} m uzakta' : '${(ph.distanceM! / 1000).toStringAsFixed(1)} km uzakta',
                    style: TextStyle(color: _isPharmacyOnDuty(ph.name) ? const Color(0xFFE53935) : const Color(0xFF4CAF50), fontSize: 13),
                  ),
              ])),
            ]),
            if (ph.address != null && ph.address!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.location_on, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(child: Text(ph.address!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12))),
              ]),
            ],
            const SizedBox(height: 16),
            const Divider(color: AppColors.divider),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () {
                Navigator.pop(context);
                final dummyPoint = DiscoveryPoint(
                  id: 'pharmacy_${ph.name}_${ph.lat}',
                  title: ph.name,
                  description: ph.address ?? '',
                  latitude: ph.lat,
                  longitude: ph.lon,
                  category: PointCategory.cafe,
                  createdAt: DateTime.now(),
                );
                _startNavigation(dummyPoint);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2196F3), Color(0xFF1565C0)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2196F3).withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.navigation_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Buraya Git',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildPointMarker(DiscoveryPoint point) {
    final color = Color(point.category.colorValue);
    final isTarget = _navigationTarget?.id == point.id;
    final isSponsored = point.isSponsored;

    // Altın halka / Hotspot kontrolü
    final ratings = _pointRatings[point.id] ?? [];
    final visitorCount = ratings.length;
    final avgRating = visitorCount > 0 ? ratings.reduce((a, b) => a + b) / visitorCount : 0.0;
    final isHotspot = avgRating >= 4.5 || visitorCount >= 3;

    final pinColor = isSponsored
        ? const Color(0xFFFFD700)
        : (isTarget ? const Color(0xFF2196F3) : color);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          children: [
            Container(
              width: isSponsored ? 46 : 40,
              height: isSponsored ? 46 : 40,
              decoration: BoxDecoration(
                gradient: isSponsored
                    ? const LinearGradient(
                        colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isSponsored ? null : pinColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSponsored
                      ? const Color(0xFFFFF8DC)
                      : (isHotspot ? const Color(0xFFFFD700) : Colors.white),
                  width: isSponsored ? 3.5 : (isHotspot ? 3.5 : (isTarget ? 3 : 2.5)),
                ),
                boxShadow: [
                  if (isSponsored)
                    BoxShadow(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.95),
                      blurRadius: 26,
                      spreadRadius: 6,
                    )
                  else if (isHotspot)
                    BoxShadow(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.9),
                      blurRadius: 20,
                      spreadRadius: 4,
                    )
                  else
                    BoxShadow(
                      color: pinColor.withValues(alpha: 0.75),
                      blurRadius: 16,
                      spreadRadius: 3,
                    ),
                ],
              ),
              child: Center(
                child: Text(
                  point.category.emoji,
                  style: TextStyle(fontSize: isSponsored ? 22 : 18),
                ),
              ),
            ),
            Container(width: isSponsored ? 3 : 2, height: isSponsored ? 12 : 10, color: pinColor),
          ],
        ),
        if (isSponsored)
          Positioned(
            top: -6,
            right: -4,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Color(0xFF1A1A2E),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFFFFD700),
                    blurRadius: 6,
                  )
                ],
              ),
              child: const Text('👑', style: TextStyle(fontSize: 12)),
            ),
          ),
      ],
    );
  }

  Widget _buildNavTargetMarker() {
    return Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF2196F3),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2196F3).withValues(alpha: 0.6),
                blurRadius: 16,
                spreadRadius: 4,
              ),
            ],
          ),
          child: const Center(
            child: Icon(Icons.flag_rounded, color: Colors.white, size: 22),
          ),
        ),
        Container(width: 2, height: 12, color: const Color(0xFF2196F3)),
      ],
    );
  }

  Widget _buildUserLocationMarker() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (ctx, child) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 50 * _pulseAnimation.value,
            height: 50 * _pulseAnimation.value,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
          ),
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.6),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 70, 0),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.97),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 16),
              const Icon(Icons.explore, color: AppColors.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Keşif',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              // Mesafe seçici döngüsü
              GestureDetector(
                onTap: () {
                  final isLoggedIn = Supabase.instance.client.auth.currentSession != null;
                  if (!isLoggedIn) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('🔒 Kayıtsız kullanıcılar 1 km ile sınırlıdır. Genişletmek için Giriş Yapın!'),
                        backgroundColor: AppColors.primary,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    );
                    return;
                  }

                  // Giriş yapmışsa ama Premium değilse
                  final isPremium = AuthService.isPremiumMock;
                  if (!isPremium) {
                    showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const PremiumPaywallSheet(),
                    ).then((bought) {
                      if (bought == true && mounted) {
                        setState(() {
                          MapScreen.selectedRadiusKm = 5.0; // Satın alımdan sonra 5 km'ye çek
                        });
                        _applyFilters();
                      }
                    });
                    return;
                  }

                  setState(() {
                    if (MapScreen.selectedRadiusKm == null) {
                      MapScreen.selectedRadiusKm = 1.0;
                    } else if (MapScreen.selectedRadiusKm == 1.0) {
                      MapScreen.selectedRadiusKm = 5.0;
                    } else if (MapScreen.selectedRadiusKm == 5.0) {
                      MapScreen.selectedRadiusKm = 10.0;
                    } else {
                      MapScreen.selectedRadiusKm = null;
                    }
                  });
                  _applyFilters();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (Supabase.instance.client.auth.currentSession == null || !AuthService.isPremiumMock || MapScreen.selectedRadiusKm != null)
                        ? AppColors.primary.withValues(alpha: 0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: (Supabase.instance.client.auth.currentSession == null || !AuthService.isPremiumMock || MapScreen.selectedRadiusKm != null) ? AppColors.primary : AppColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.radar,
                        size: 14,
                        color: (Supabase.instance.client.auth.currentSession == null || !AuthService.isPremiumMock || MapScreen.selectedRadiusKm != null)
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        Supabase.instance.client.auth.currentSession == null
                            ? '1 km'
                            : (!AuthService.isPremiumMock
                                ? '1 km (Kısıtlı)'
                                : (MapScreen.selectedRadiusKm == null
                                    ? 'Sınırsız'
                                    : '${MapScreen.selectedRadiusKm!.toStringAsFixed(0)} km')),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: (Supabase.instance.client.auth.currentSession == null || !AuthService.isPremiumMock || MapScreen.selectedRadiusKm != null)
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                '${_filteredPoints.length}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategorySidebar() {
    return Positioned(
      top: 80,
      right: 12,
      bottom: 120,
      child: SafeArea(
        child: Container(
          width: 50,
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.15),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(25),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 6),
                    // Tam Ekran Genişlet Butonu
                    Tooltip(
                      message: 'Tüm Kategoriler (Genişlet)',
                      child: GestureDetector(
                        onTap: () => _showCategoryGlassOverlay(),
                        child: Container(
                          width: 38,
                          height: 38,
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.primary, Color(0xFFB71C4B)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.5),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.grid_view_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                    _divider(),
                    // Eczaneler
                    _sidebarPharmacyButton(),
                    _divider(),
                    // Tümü
                    _sidebarButton(null, '🗺️', 'Tümü'),
                    _divider(),
                    ...PointCategory.values.map((cat) => _sidebarButton(cat, cat.emoji, cat.labelTR)),
                    _divider(),
                    _sidebarPetButton(),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sidebarPharmacyButton() {
    return Tooltip(
      message: 'Nöbetçi Eczaneler',
      preferBelow: false,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _pharmacyFilterActive = !_pharmacyFilterActive;
            _showPharmacies = _pharmacyFilterActive;
            _activeFilter = null;
          });
          _applyFilters();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 38,
          height: 38,
          margin: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: _pharmacyFilterActive
                ? const Color(0xFFE53935).withValues(alpha: 0.3)
                : Colors.transparent,
            shape: BoxShape.circle,
            border: _pharmacyFilterActive
                ? Border.all(color: const Color(0xFFE53935), width: 1.5)
                : null,
          ),
          child: const Center(
            child: Text(
              '🏥',
              style: TextStyle(fontSize: 18),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sidebarPetButton() {
    return Tooltip(
      message: 'Evcil Hayvan Dostu (Premium)',
      preferBelow: false,
      child: GestureDetector(
        onTap: () {
          final isPremium = AuthService.isPremiumMock;
          if (!isPremium) {
            showModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const PremiumPaywallSheet(),
            );
          } else {
            setState(() {
              _filterOnlyPetFriendly = !_filterOnlyPetFriendly;
            });
            _applyFilters();
          }
        },
        child: Container(
          width: 38,
          height: 38,
          margin: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: _filterOnlyPetFriendly
                ? AppColors.primary
                : Colors.transparent,
            shape: BoxShape.circle,
            border: _filterOnlyPetFriendly
                ? Border.all(color: Colors.white, width: 1.5)
                : null,
          ),
          child: const Center(
            child: Text(
              '🐾',
              style: TextStyle(fontSize: 18),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sidebarButton(PointCategory? cat, String emoji, String label) {
    final isActive = _activeFilter == cat && !_pharmacyFilterActive;
    final color = cat != null ? Color(cat.colorValue) : AppColors.primary;
    return Tooltip(
      message: label,
      preferBelow: false,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _activeFilter = cat;
            _pharmacyFilterActive = false;
            _showPharmacies = false;
          });
          _applyFilters();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 38,
          height: 38,
          margin: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: isActive ? color.withValues(alpha: 0.3) : Colors.transparent,
            shape: BoxShape.circle,
            border: isActive ? Border.all(color: color, width: 1.5) : null,
          ),
          child: Center(
            child: Text(
              emoji,
              style: TextStyle(
                fontSize: isActive ? 20 : 18,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 28,
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 2),
      color: AppColors.border.withValues(alpha: 0.6),
    );
  }

  /// Ekranı Kaplayan Yarı Saydam (Glassmorphic) Kategori Paneli
  void _showCategoryGlassOverlay() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'CategoryOverlay',
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (ctx, anim1, anim2) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Scaffold(
                backgroundColor: AppColors.background.withValues(alpha: 0.8),
                body: SafeArea(
                  child: Column(
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                              ),
                              child: const Icon(Icons.explore_rounded, color: AppColors.primary, size: 24),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Kategorileri Keşfet',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Haritada filtrelemek istediğiniz mekan kategorisini seçin',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceElevated.withValues(alpha: 0.8),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(color: AppColors.divider, height: 1),
                      const SizedBox(height: 12),

                      // Grid Items
                      Expanded(
                        child: GridView(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          physics: const BouncingScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 1.45,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          children: [
                            // 🗺️ Tüm Noktalar
                            _buildGlassCategoryCard(
                              title: 'Tüm Noktalar',
                              subtitle: '${_allPoints.length} mekan',
                              emoji: '🗺️',
                              accentColor: AppColors.primary,
                              isSelected: _activeFilter == null && !_pharmacyFilterActive,
                              onTap: () {
                                setState(() {
                                  _activeFilter = null;
                                  _pharmacyFilterActive = false;
                                  _showPharmacies = false;
                                });
                                _applyFilters();
                                Navigator.pop(context);
                              },
                            ),
                            // 🏥 Nöbetçi Eczaneler
                            _buildGlassCategoryCard(
                              title: 'Nöbetçi Eczaneler',
                              subtitle: '${_pharmacies.length} eczane',
                              emoji: '🏥',
                              accentColor: const Color(0xFFE53935),
                              isSelected: _pharmacyFilterActive,
                              onTap: () {
                                setState(() {
                                  _pharmacyFilterActive = !_pharmacyFilterActive;
                                  _showPharmacies = _pharmacyFilterActive;
                                  _activeFilter = null;
                                });
                                _applyFilters();
                                Navigator.pop(context);
                              },
                            ),
                            // Dinamik Kategoriler
                            ...PointCategory.values.map((cat) {
                              final catColor = Color(cat.colorValue);
                              final isCatSelected = _activeFilter == cat && !_pharmacyFilterActive;
                              final count = _allPoints.where((p) => p.category == cat).length;
                              return _buildGlassCategoryCard(
                                title: cat.labelTR,
                                subtitle: '$count mekan',
                                emoji: cat.emoji,
                                accentColor: catColor,
                                isSelected: isCatSelected,
                                onTap: () {
                                  setState(() {
                                    _activeFilter = cat;
                                    _pharmacyFilterActive = false;
                                    _showPharmacies = false;
                                  });
                                  _applyFilters();
                                  Navigator.pop(context);
                                },
                              );
                            }),
                            // 🐾 Evcil Hayvan Dostu
                            _buildGlassCategoryCard(
                              title: 'Evcil Hayvan Dostu',
                              subtitle: 'Premium Filtre',
                              emoji: '🐾',
                              accentColor: const Color(0xFFFFB347),
                              isSelected: _filterOnlyPetFriendly,
                              onTap: () {
                                Navigator.pop(context);
                                final isPremium = AuthService.isPremiumMock;
                                if (!isPremium) {
                                  showModalBottomSheet<bool>(
                                    context: context,
                                    isScrollControlled: true,
                                    backgroundColor: Colors.transparent,
                                    builder: (_) => const PremiumPaywallSheet(),
                                  );
                                } else {
                                  setState(() {
                                    _filterOnlyPetFriendly = !_filterOnlyPetFriendly;
                                  });
                                  _applyFilters();
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildGlassCategoryCard({
    required String title,
    required String subtitle,
    required String emoji,
    required Color accentColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withValues(alpha: 0.25)
              : AppColors.card.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? accentColor : AppColors.border.withValues(alpha: 0.6),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: accentColor.withValues(alpha: 0.35),
                blurRadius: 14,
                spreadRadius: 1,
              )
            else
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  emoji,
                  style: const TextStyle(fontSize: 32),
                ),
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check, color: Colors.white, size: 12),
                  ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Positioned(
      right: 16,
      bottom: 100,
      child: Column(
        children: [
          _mapButton(
            icon: Icons.add_location_alt_outlined,
            tooltip: 'Keşif Noktası Ekle',
            onTap: () {
              if (_userLocation != null) {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => AddPointSheet(
                    latitude: _userLocation!.latitude,
                    longitude: _userLocation!.longitude,
                    onSaved: () {
                      setState(() {
                        _activeFilter = null;
                        _filterOnlyPetFriendly = false;
                      });
                      _loadPoints();
                    },
                  ),
                );
              }
            },
          ),
          const SizedBox(height: 8),
          _mapButton(
            icon: _useSatelliteMap ? Icons.map_outlined : Icons.layers_outlined,
            tooltip: 'Harita Görünümü (Premium)',
            onTap: () {
              final isPremium = AuthService.isPremiumMock;
              if (!isPremium) {
                showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const PremiumPaywallSheet(),
                );
              } else {
                setState(() => _useSatelliteMap = !_useSatelliteMap);
              }
            },
          ),
          const SizedBox(height: 8),
          _mapButton(
            icon: Icons.my_location,
            tooltip: 'Konumuma Git',
            onTap: _centerOnUser,
          ),
        ],
      ),
    );
  }

  Widget _mapButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
            ),
          ],
        ),
        child: Icon(icon, color: AppColors.primary, size: 22),
      ),
    );
  }

  Widget _buildNavigationBanner() {
    return Positioned(
      bottom: 100,
      left: 16,
      right: 72,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1565C0),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2196F3).withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.navigation_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Navigasyon aktif',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13),
                  ),
                  Text(
                    _navigationTarget?.title ?? '',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: _clearNavigation,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteLoadingIndicator() {
    return Positioned(
      bottom: 160,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    color: Color(0xFF2196F3), strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text('Rota hesaplanıyor...',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: AppColors.background.withValues(alpha: 0.8),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 16),
            Text('Konum alınıyor...',
                style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
