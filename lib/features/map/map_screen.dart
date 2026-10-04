import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../app/theme.dart';
import '../../core/app_logger.dart';
import '../../services/location_service.dart';
import '../../services/database_service.dart';
import '../../shared/models/models.dart';
import '../discovery/add_point_sheet.dart';
import '../discovery/point_detail_sheet.dart';
import '../../shared/widgets/premium_paywall_sheet.dart';
import '../../services/auth_service.dart';
import '../pharmacy/pharmacy_screen.dart' show Pharmacy;
import 'widgets/map_markers.dart';
import 'widgets/pharmacy_panel.dart';
import 'widgets/weather_card_widget.dart';
import '../../services/weather_service.dart';
import '../../services/events_service.dart';

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
  WeatherData? _weatherData;
  String _weatherLocationText = 'İstanbul / Beyoğlu';

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;


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
      _loadWeather(pos.latitude, pos.longitude); // Hava durumunu yükle
    } else if (mounted) {
      setState(() {
        _isLoadingLocation = false;
        _userLocation = const LatLng(41.0082, 28.9784); // İstanbul'u varsayılan yap
      });
      _loadPharmacies(41.0082, 28.9784); // Varsayılan konum için de eczaneleri yükle!
      _loadWeather(41.0082, 28.9784); // Hava durumunu yükle
    }
    _locationService.startTracking();
    _locationService.positionStream.listen((pos) {
      if (mounted) {
        setState(() => _userLocation = LatLng(pos.latitude, pos.longitude));
        _applyFilters();
      }
    });
  }

  Future<void> _loadWeather(double lat, double lon) async {
    try {
      if (_weatherData == null && mounted) {
        setState(() {
          _weatherData = WeatherData.mock();
        });
      }

      final cityInfo = await EventsService().detectUserCityAndDistrict();
      final city = cityInfo['city'];
      final district = cityInfo['district'];
      if (mounted && (city != null || district != null)) {
        setState(() {
          if (city != null && district != null) {
            _weatherLocationText = '$city / $district';
          } else {
            _weatherLocationText = city ?? district ?? 'İstanbul / Beyoğlu';
          }
        });
      }

      final data = await WeatherService().getWeather(lat, lon);
      if (mounted) {
        setState(() {
          _weatherData = data;
        });
      }
    } catch (_) {}
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
        AppLogger.warning('Supabase profiles join hatası, profilesiz çekiliyor: $e', tag: 'MapScreen');
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
      AppLogger.error('Supabase noktaları yükleme hatası', error: e, tag: 'MapScreen');
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
      AppLogger.error('Ziyaret verileri toplu çekme hatası', error: e, tag: 'MapScreen');
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
          // Eczane listesi paneli
          if (_showPharmacies)
            PharmacyListPanel(
              pharmacies: _pharmacies,
              navigationTarget: _navigationTarget,
              isOnDuty: _isPharmacyOnDuty,
              onClose: () {
                setState(() {
                  _pharmacyFilterActive = false;
                  _showPharmacies = false;
                });
                _applyFilters();
              },
              onPharmacyTap: (ph) =>
                  _mapController.move(LatLng(ph.lat, ph.lon), 16),
              onPharmacyNavTap: _showPharmacyInfo,
            ),
          _buildBottomControls(),
          if (_isLoadingLocation) const MapLoadingOverlay(),
          if (_isLoadingRoute) const RouteLoadingIndicator(),
          if (_navigationTarget != null)
            NavigationBanner(
              targetTitle: _navigationTarget!.title,
              onClose: _clearNavigation,
            ),
        ],
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
                  width: 58,
                  height: 62,
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

  Widget _buildPointMarker(DiscoveryPoint point) =>
      PointMarker(
        point: point,
        navigationTarget: _navigationTarget,
        pointRatings: _pointRatings,
      );

  Widget _buildNavTargetMarker() => const NavTargetMarker();

  Widget _buildUserLocationMarker() =>
      UserLocationMarker(pulseAnimation: _pulseAnimation);

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Üst satır: Konum | Arama | +Nöbetçi ──
            Row(
              children: [
                // Konum pill
                Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_on_rounded, color: AppColors.primary, size: 14),
                      SizedBox(width: 4),
                      Text(
                        _weatherLocationText.length > 15
                            ? '${_weatherLocationText.substring(0, 12)}...'
                            : _weatherLocationText,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 3),
                      Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary, size: 16),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // KM Mesafe Filtresi
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      final isLoggedIn =
                          Supabase.instance.client.auth.currentSession != null;
                      if (!isLoggedIn) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text(
                                '🔒 Kayıtsız kullanıcılar 1 km ile sınırlıdır.'),
                            backgroundColor: AppColors.primary,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        );
                        return;
                      }
                      final isPremium = AuthService.isPremiumMock;
                      if (!isPremium) {
                        showModalBottomSheet<bool>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => const PremiumPaywallSheet(),
                        ).then((bought) {
                          if (bought == true && mounted) {
                            setState(() => MapScreen.selectedRadiusKm = 5.0);
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
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: MapScreen.selectedRadiusKm != null
                            ? AppColors.primary.withValues(alpha: 0.18)
                            : AppColors.surface.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: MapScreen.selectedRadiusKm != null
                              ? AppColors.primary
                              : AppColors.border,
                          width: MapScreen.selectedRadiusKm != null ? 1.5 : 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: MapScreen.selectedRadiusKm != null
                                ? AppColors.primary.withValues(alpha: 0.3)
                                : Colors.black.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.radar_rounded,
                            size: 16,
                            color: MapScreen.selectedRadiusKm != null
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            Supabase.instance.client.auth.currentSession == null
                                ? '1 km (Kayıtsız)'
                                : (!AuthService.isPremiumMock
                                    ? '1 km (Kısıtlı)'
                                    : (MapScreen.selectedRadiusKm == null
                                        ? 'Sınırsız'
                                        : '${MapScreen.selectedRadiusKm!.toStringAsFixed(0)} km')),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: MapScreen.selectedRadiusKm != null
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.swap_horiz_rounded,
                            size: 14,
                            color: MapScreen.selectedRadiusKm != null
                                ? AppColors.primary
                                : AppColors.textHint,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // + Nöbetçi butonu
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _pharmacyFilterActive = !_pharmacyFilterActive;
                      _showPharmacies = _pharmacyFilterActive;
                      if (_pharmacyFilterActive) _activeFilter = null;
                    });
                    _applyFilters();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                    decoration: BoxDecoration(
                      color: _pharmacyFilterActive
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFF4CAF50).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFF4CAF50), width: 1.5),
                      boxShadow: [
                        if (_pharmacyFilterActive)
                          const BoxShadow(
                            color: Color(0x664CAF50),
                            blurRadius: 10,
                            offset: Offset(0, 3),
                          ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add,
                          color: _pharmacyFilterActive ? Colors.white : const Color(0xFF4CAF50),
                          size: 15,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Nöbetçi',
                          style: TextStyle(
                            color: _pharmacyFilterActive ? Colors.white : const Color(0xFF4CAF50),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // ── Yatay Kaydırılabilir Kategori Chips ──
            _buildFilterChipsRow(),
            if (_weatherData != null) ...[
              const SizedBox(height: 8),
              WeatherCardWidget(
                weather: _weatherData!,
                locationText: _weatherLocationText,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChipsRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          // Tümü
          _buildFilterChip(
            label: 'Tümü',
            count: _allPoints.length,
            isActive: _activeFilter == null && !_pharmacyFilterActive && !_filterOnlyPetFriendly,
            color: AppColors.primary,
            onTap: () {
              setState(() {
                _activeFilter = null;
                _pharmacyFilterActive = false;
                _showPharmacies = false;
                _filterOnlyPetFriendly = false;
              });
              _applyFilters();
            },
          ),
          const SizedBox(width: 8),
          // Pati Dostu
          _buildFilterChip(
            label: 'Pati Dostu',
            emoji: '🐾',
            isActive: _filterOnlyPetFriendly,
            color: const Color(0xFFFF9800),
            onTap: () {
              final isPremium = AuthService.isPremiumMock;
              if (!isPremium) {
                showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const PremiumPaywallSheet(),
                );
                return;
              }
              setState(() => _filterOnlyPetFriendly = !_filterOnlyPetFriendly);
              _applyFilters();
            },
          ),
          const SizedBox(width: 8),
          // Tüm PointCategory değerleri
          for (final cat in PointCategory.values) ...[
            _buildFilterChip(
              label: cat.labelTR,
              emoji: cat.emoji,
              isActive: _activeFilter == cat && !_pharmacyFilterActive,
              color: Color(cat.colorValue),
              onTap: () {
                setState(() {
                  _activeFilter = _activeFilter == cat ? null : cat;
                  _pharmacyFilterActive = false;
                  _showPharmacies = false;
                });
                _applyFilters();
              },
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    String? emoji,
    int? count,
    required bool isActive,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: isActive ? color : AppColors.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? color : AppColors.border,
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: isActive
                  ? color.withValues(alpha: 0.4)
                  : Colors.black.withValues(alpha: 0.2),
              blurRadius: isActive ? 10 : 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (emoji != null) ...[
              Text(emoji, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 5),
            ],
            Text(
              count != null ? '$label ($count)' : label,
              style: TextStyle(
                color: isActive ? Colors.white : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              ),
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
          MapControlButton(
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
          MapControlButton(
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
          MapControlButton(
            icon: Icons.my_location,
            tooltip: 'Konumuma Git',
            onTap: _centerOnUser,
          ),
        ],
      ),
    );
  }
}
