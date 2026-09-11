import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import '../../app/theme.dart';
import '../../services/location_service.dart';
import '../../services/database_service.dart';
import '../../shared/models/models.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final LocationService _locationService = LocationService();
  final DatabaseService _dbService = DatabaseService();
  final MapController _mapController = MapController();
  final _uuid = const Uuid();

  bool _isTracking = false;
  bool _isPaused = false;
  List<LatLng> _routePoints = [];
  double _totalDistance = 0;
  int _elapsedSeconds = 0;
  Timer? _timer;
  StreamSubscription<Position>? _positionSub;
  Position? _lastPosition;
  List<SavedRoute> _savedRoutes = [];
  late AnimationController _trackingPulse;
  int _tileLayerResetKey = 0; // Harita siyah ekran hatasını çözmek için dinamik key sayacı

  // Yürüyüş sırasında işaretlenen noktalar
  final List<_Waypoint> _waypoints = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _trackingPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _loadRoutes();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Arka plana geçince harita yenilemeyi durdur ama stream çalışmaya devam eder
      // (foreground service sayesinde konum akışı kesilmez)
    } else if (state == AppLifecycleState.resumed) {
      if (mounted) {
        setState(() {
          _tileLayerResetKey++; // Harita tile'larını yenile
        });
        // Son bilinen konuma haritayı taşı
        if (_lastPosition != null && _isTracking) {
          try {
            _mapController.move(
              LatLng(_lastPosition!.latitude, _lastPosition!.longitude),
              17,
            );
          } catch (_) {}
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _positionSub?.cancel();
    _trackingPulse.dispose();
    super.dispose();
  }

  Future<void> _loadRoutes() async {
    final routes = await _dbService.getAllRoutes();
    if (mounted) setState(() => _savedRoutes = routes);
  }

  void _startTracking() async {
    final hasPermission = await _locationService.checkPermissions();
    if (!mounted) return;
    if (!hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konum izni gerekli!')),
      );
      return;
    }

    // Android: Arka plan konum izni iste
    if (Platform.isAndroid) {
      final bgStatus = await Permission.locationAlways.status;
      if (!bgStatus.isGranted) {
        final result = await Permission.locationAlways.request();
        if (mounted && result.isDenied) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '⚠️ Arka plan konum izni verilmedi. '
                'Rota oluşturma uygulama açıkken çalışır.',
              ),
              duration: Duration(seconds: 4),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    }

    // İlk konumu al ve başlangıç noktası olarak hemen ekle
    Position? initialPos;
    try {
      initialPos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
    } catch (_) {}

    if (!mounted) return;

    setState(() {
      _isTracking = true;
      _isPaused = false;
      _routePoints = [];
      _totalDistance = 0;
      _elapsedSeconds = 0;
      _lastPosition = initialPos;
    });

    if (initialPos != null) {
      final startPoint = LatLng(initialPos.latitude, initialPos.longitude);
      setState(() => _routePoints.add(startPoint));
      try { _mapController.move(startPoint, 17); } catch (_) {}
    }

    _trackingPulse.repeat(reverse: true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isPaused) setState(() => _elapsedSeconds++);
    });

    // Platform'a göre konum ayarları
    // Android: foregroundNotificationConfig ile bildirim + arka plan stream
    // iOS: allowBackgroundLocationUpdates ile sürekli konum
    LocationSettings locationSettings;
    if (Platform.isAndroid) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
        forceLocationManager: false,
        intervalDuration: const Duration(seconds: 2),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: 'Rota kaydediliyor... GPS aktif',
          notificationTitle: '🧭 Keşif - Rota Takibi',
          enableWakeLock: true,
          notificationIcon: AndroidResource(
            name: 'ic_launcher',
            defType: 'mipmap',
          ),
          setOngoing: true,
        ),
      );
    } else if (Platform.isIOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.fitness,
        distanceFilter: 3,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      );
    }

    _positionSub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((pos) {
      if (_isPaused) return;
      final newPoint = LatLng(pos.latitude, pos.longitude);

      if (_lastPosition != null) {
        _totalDistance += _locationService.calculateDistance(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          pos.latitude,
          pos.longitude,
        );
      }

      _lastPosition = pos;
      // mounted kontrolü: arka planda widget ağaçta kalır ama
      // setState çağrısı yine de yapılır — rota noktası kaydedilir
      if (mounted) {
        setState(() => _routePoints.add(newPoint));
        // Harita ön plandayken takip et
        try { _mapController.move(newPoint, 17); } catch (_) {}
      } else {
        // Arka planda: setState olmadan listeye ekle (foreground service sayesinde)
        _routePoints.add(newPoint);
      }
    });
  }

  void _pauseTracking() {
    setState(() => _isPaused = !_isPaused);
  }

  void _stopTracking() async {
    _timer?.cancel();
    await _positionSub?.cancel();
    _trackingPulse.stop();
    _trackingPulse.reset();

    if (_routePoints.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rota kaydedilemedi: Yeterli konum noktası yok.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      setState(() {
        _isTracking = false;
        _isPaused = false;
        _routePoints = [];
        _lastPosition = null;
        _waypoints.clear();
      });
      return;
    }

    // Rota adlandırma dialog'u
    final name = await _showNameDialog();
    if (name != null && name.isNotEmpty) {
      final route = SavedRoute(
        id: _uuid.v4(),
        name: name,
        points: _routePoints
            .map((p) => RoutePoint(
                  latitude: p.latitude,
                  longitude: p.longitude,
                  timestamp: DateTime.now(),
                ))
            .toList(),
        distanceMeters: _totalDistance,
        durationSeconds: _elapsedSeconds,
        recordedAt: DateTime.now(),
      );
      await _dbService.saveRoute(route);
      await _loadRoutes();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rota "$name" kaydedildi! 🎉'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }

    setState(() {
      _isTracking = false;
      _isPaused = false;
      _routePoints = [];
      _lastPosition = null;
      _waypoints.clear();
    });
  }

  Future<void> _addWaypoint() async {
    if (_lastPosition == null) return;
    final result = await _showWaypointDialog();
    if (result == null) return;

    final category = result['category'] as PointCategory;
    final title = result['title'] as String;
    final photoFile = result['photo'] as File?;
    final point = LatLng(_lastPosition!.latitude, _lastPosition!.longitude);

    // Fotoğraf yolunu doğrudan kullan
    String? imagePath = photoFile?.path;

    // DB'ye kaydet
    final dp = DiscoveryPoint(
      id: const Uuid().v4(),
      title: title.isEmpty
          ? '${category.labelTR} - $_formattedTime'
          : title,
      description: 'Yürüyüş sırasında işaretlendi',
      latitude: point.latitude,
      longitude: point.longitude,
      category: category,
      imagePath: imagePath,
      createdAt: DateTime.now(),
      isUserAdded: true,
    );
    await _dbService.insertPoint(dp);

    setState(() {
      _waypoints.add(_Waypoint(
        id: dp.id,
        point: point,
        note: dp.title,
        category: category,
        time: _elapsedSeconds,
      ));
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            Text('${category.emoji} ', style: const TextStyle(fontSize: 16)),
            Text(dp.title),
          ]),
          backgroundColor: Color(category.colorValue),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<Map<String, dynamic>?> _showWaypointDialog() async {
    final titleCtrl = TextEditingController();
    PointCategory selectedCat = PointCategory.cafe;
    File? photo;
    final picker = ImagePicker();

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppColors.card,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [
            Text('📍', style: TextStyle(fontSize: 22)),
            SizedBox(width: 8),
            Text('Nokta İşaretle',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold)),
          ]),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Fotoğraf (zorunlu)
                const Text('Fotoğraf *',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    final xFile = await picker.pickImage(
                      source: ImageSource.camera,
                      imageQuality: 80,
                      maxWidth: 1200,
                    );
                    if (xFile != null) setS(() => photo = File(xFile.path));
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: double.infinity,
                    height: 120,
                    decoration: BoxDecoration(
                      color: photo != null
                          ? Colors.transparent
                          : AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: photo != null
                            ? AppColors.primary
                            : AppColors.border,
                        width: photo != null ? 2 : 1,
                      ),
                    ),
                    child: photo != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(photo!, fit: BoxFit.cover),
                                Positioned(
                                  bottom: 6,
                                  right: 6,
                                  child: GestureDetector(
                                    onTap: () async {
                                      final xFile = await picker.pickImage(
                                        source: ImageSource.camera,
                                        imageQuality: 80,
                                      );
                                      if (xFile != null)
                                        setS(() =>
                                            photo = File(xFile.path));
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black
                                            .withValues(alpha: 0.65),
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.camera_alt,
                                              color: Colors.white, size: 12),
                                          SizedBox(width: 4),
                                          Text('Yeniden Çek',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.camera_alt_rounded,
                                  color: AppColors.primary
                                      .withValues(alpha: 0.7),
                                  size: 28),
                              const SizedBox(height: 6),
                              const Text('Fotoğraf Çek (Zorunlu)',
                                  style: TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Kategori',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: PointCategory.values.map((cat) {
                    final isSelected = cat == selectedCat;
                    final color = Color(cat.colorValue);
                    return GestureDetector(
                      onTap: () => setS(() => selectedCat = cat),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? color.withValues(alpha: 0.2)
                              : AppColors.background,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? color : AppColors.border,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Text(
                          '${cat.emoji} ${cat.labelTR}',
                          style: TextStyle(
                              color: isSelected
                                  ? color
                                  : AppColors.textSecondary,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                              fontSize: 12),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: titleCtrl,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Başlık (isteğe bağlı)',
                    hintText: 'Örn: Güzel manzara',
                  ),
                  autofocus: false,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: photo == null
                  ? null
                  : () => Navigator.pop(ctx, {
                        'category': selectedCat,
                        'title': titleCtrl.text.trim(),
                        'photo': photo,
                      }),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    photo == null ? AppColors.textHint : AppColors.primary,
                disabledBackgroundColor: AppColors.textHint,
              ),
              child: Text(photo == null ? 'Önce Fotoğraf Çek' : 'İşaretle'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _showNameDialog() async {
    final controller = TextEditingController(
      text: 'Yürüyüş ${DateTime.now().day}.${DateTime.now().month}',
    );
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rotayı Kaydet', style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            labelText: 'Rota Adı',
            hintText: 'Örn: Sabah Yürüyüşü',
            filled: true,
            fillColor: AppColors.surfaceElevated,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kaydetme', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  String get _formattedTime {
    final h = _elapsedSeconds ~/ 3600;
    final m = (_elapsedSeconds % 3600) ~/ 60;
    final s = _elapsedSeconds % 60;
    if (h > 0) return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  double get _avgSpeedKmh {
    if (_elapsedSeconds == 0) return 0;
    return (_totalDistance / _elapsedSeconds) * 3.6;
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _isTracking ? _buildTrackingView() : _buildRouteHistory(),
    );
  }

  Widget _buildTrackingView() {
    return Stack(
      children: [
        // Harita
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _routePoints.isNotEmpty
                ? _routePoints.last
                : const LatLng(39.9334, 32.8597),
            initialZoom: 17,
            backgroundColor: AppColors.background,
          ),
          children: [
            TileLayer(
              key: ValueKey('tile_layer_$_tileLayerResetKey'),
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.kesif.app',
            ),
            if (_routePoints.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _routePoints,
                    color: AppColors.route,
                    strokeWidth: 5,
                    borderColor: AppColors.routeGlow.withValues(alpha: 0.4),
                    borderStrokeWidth: 8,
                  ),
                ],
              ),
            if (_routePoints.isNotEmpty)
              MarkerLayer(
                markers: [
                  // Mevcut konum marker’ı
                  Marker(
                    point: _routePoints.last,
                    width: 24,
                    height: 24,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.route,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.route.withValues(alpha: 0.6),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Waypoint marker’ları — tıklanabilir
                  ..._waypoints.map((wp) => Marker(
                        point: wp.point,
                        width: 40,
                        height: 50,
                        child: GestureDetector(
                          onTap: () => _showWaypointInfo(wp),
                          child: Column(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Color(wp.category.colorValue),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color(wp.category.colorValue)
                                          .withValues(alpha: 0.5),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(wp.category.emoji,
                                      style: const TextStyle(fontSize: 16)),
                                ),
                              ),
                              Container(
                                  width: 2,
                                  height: 10,
                                  color: Color(wp.category.colorValue)),
                            ],
                          ),
                        ),
                      )),
                ],
              ),
          ],
        ),
        // İstatistikler — kompakt şeffaf panel
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: AppColors.border.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Durum göstergesi
                  Row(children: [
                    AnimatedBuilder(
                      animation: _trackingPulse,
                      builder: (_, __) => Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _isPaused
                              ? AppColors.accent
                              : AppColors.route,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _formattedTime,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ]),
                  // Mesafe
                  Text(
                    _totalDistance < 1000
                        ? '${_totalDistance.toStringAsFixed(0)} m'
                        : '${(_totalDistance / 1000).toStringAsFixed(2)} km',
                    style: const TextStyle(
                        color: AppColors.route,
                        fontWeight: FontWeight.w700,
                        fontSize: 15),
                  ),
                  // Hız
                  Text(
                    '${_avgSpeedKmh.toStringAsFixed(1)} km/s',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Kontrol butonları
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _controlButton(
                icon: Icons.add_location_alt_rounded,
                color: AppColors.primary,
                size: 52,
                onTap: _addWaypoint,
                label: 'Nokta',
              ),
              const SizedBox(width: 16),
              _controlButton(
                icon: _isPaused ? Icons.play_arrow : Icons.pause,
                color: AppColors.accent,
                size: 52,
                onTap: _pauseTracking,
                label: _isPaused ? 'Devam' : 'Duraklat',
              ),
              const SizedBox(width: 16),
              _controlButton(
                icon: Icons.stop_rounded,
                color: AppColors.error,
                size: 68,
                onTap: _stopTracking,
                label: 'Bitir',
              ),
            ],
          ),
        ),
        // Waypoint sayacı
        if (_waypoints.isNotEmpty)
          Positioned(
            bottom: 160,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('📍', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 4),
                  Text(
                    '${_waypoints.length} nokta',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _showWaypointInfo(_Waypoint wp) {
    final color = Color(wp.category.colorValue);
    final h = wp.time ~/ 3600;
    final m = (wp.time % 3600) ~/ 60;
    final s = wp.time % 60;
    final timeStr = h > 0
        ? '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Center(
                    child: Text(wp.category.emoji,
                        style: const TextStyle(fontSize: 22))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(wp.note,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                      Text(wp.category.labelTR,
                          style:
                              TextStyle(color: color, fontSize: 13)),
                    ]),
              ),
              Text('⏱ $timeStr',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
            ]),
            const SizedBox(height: 16),
            Text(
              '${wp.point.latitude.toStringAsFixed(5)}, ${wp.point.longitude.toStringAsFixed(5)}',
              style: const TextStyle(
                  color: AppColors.textHint, fontSize: 11),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _statItem(String value, String label, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: AppColors.textSecondary, size: 18),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }

  Widget _controlButton({
    required IconData icon,
    required Color color,
    required double size,
    required VoidCallback onTap,
    String? label,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: size * 0.5),
          ),
          if (label != null) ...[
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }

  Widget _buildRouteHistory() {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          backgroundColor: AppColors.surface,
          floating: true,
          title: const Text('Rotalarım'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ElevatedButton.icon(
                onPressed: _startTracking,
                icon: const Icon(Icons.play_arrow, size: 20),
                label: const Text('Başla'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.route,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ),
          ],
        ),
        if (_savedRoutes.isEmpty)
          SliverFillRemaining(
            child: _buildEmptyState(),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _buildRouteCard(_savedRoutes[i]),
                childCount: _savedRoutes.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(Icons.route, color: AppColors.textHint, size: 48),
          ),
          const SizedBox(height: 20),
          const Text(
            'Henüz rota yok',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Yürüyüşe çık ve rotanı kaydet!',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _startTracking,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Yürüyüşe Başla'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.route),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteCard(SavedRoute route) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RouteDetailPage(route: route),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.route.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.route, color: AppColors.route),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          route.name,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${route.recordedAt.day}.${route.recordedAt.month}.${route.recordedAt.year}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textHint, size: 22),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: AppColors.textHint),
                    onPressed: () async {
                      await _dbService.deleteRoute(route.id);
                      _loadRoutes();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: AppColors.divider),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _routeStat(
                      route.formattedDistance, 'Mesafe', Icons.straighten),
                  _routeStat(
                      route.formattedDuration, 'Süre', Icons.timer_outlined),
                  _routeStat(
                    route.durationSeconds > 0
                        ? '${((route.distanceMeters / route.durationSeconds) * 3.6).toStringAsFixed(1)} km/s'
                        : '-',
                    'Ort. Hız',
                    Icons.speed,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _routeStat(String value, String label, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: AppColors.route, size: 18),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
      ],
    );
  }
}

// Waypoint modeli
class _Waypoint {
  final String id;
  final LatLng point;
  final String note;
  final PointCategory category;
  final int time;
  const _Waypoint({
    required this.id,
    required this.point,
    required this.note,
    required this.category,
    required this.time,
  });
}

// ============================
// Rota Detay Ekranı
// ============================
class RouteDetailPage extends StatefulWidget {
  final SavedRoute route;
  const RouteDetailPage({super.key, required this.route});

  @override
  State<RouteDetailPage> createState() => _RouteDetailPageState();
}

class _RouteDetailPageState extends State<RouteDetailPage> with WidgetsBindingObserver {
  final MapController _mapController = MapController();
  int _tileLayerResetKey = 0;

  List<LatLng> get _latLngs => widget.route.points
      .map((p) => LatLng(p.latitude, p.longitude))
      .toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pts = _latLngs;
    final hasPoints = pts.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Harita
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter:
                  hasPoints ? pts[pts.length ~/ 2] : const LatLng(39.9334, 32.8597),
              initialZoom: 14,
            ),
            children: [
              TileLayer(
                key: ValueKey('tile_layer_$_tileLayerResetKey'),
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.kesif.app',
              ),
              if (hasPoints) ...
                [
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: pts,
                        color: AppColors.route,
                        strokeWidth: 4.5,
                        borderColor: AppColors.route.withValues(alpha: 0.3),
                        borderStrokeWidth: 8,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      // Başlangıç
                      Marker(
                        point: pts.first,
                        width: 40,
                        height: 40,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.route,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.route.withValues(alpha: 0.5),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 20),
                        ),
                      ),
                      // Bitiş
                      Marker(
                        point: pts.last,
                        width: 40,
                        height: 40,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.error.withValues(alpha: 0.5),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.flag_rounded,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                ],
            ],
          ),

          // Üst Bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: AppColors.textPrimary, size: 18),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.97),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.route.name,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            '${widget.route.recordedAt.day}.${widget.route.recordedAt.month}.${widget.route.recordedAt.year}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Alt istatistikler
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                border: const Border(top: BorderSide(color: AppColors.border)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _detailStat(
                        widget.route.formattedDistance,
                        'Mesafe',
                        Icons.straighten,
                        AppColors.route,
                      ),
                      _vDivider(),
                      _detailStat(
                        widget.route.formattedDuration,
                        'Süre',
                        Icons.timer_outlined,
                        AppColors.accent,
                      ),
                      _vDivider(),
                      _detailStat(
                        widget.route.durationSeconds > 0
                            ? '${((widget.route.distanceMeters / widget.route.durationSeconds) * 3.6).toStringAsFixed(1)} km/s'
                            : '-',
                        'Ort. Hız',
                        Icons.speed,
                        AppColors.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Rotayı sığdır butonu
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        if (pts.length >= 2) {
                          _mapController.fitCamera(
                            CameraFit.bounds(
                              bounds: LatLngBounds.fromPoints(pts),
                              padding: const EdgeInsets.all(50),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.fit_screen_rounded,
                          color: AppColors.route),
                      label: const Text('Rotayı Sığdır',
                          style: TextStyle(color: AppColors.route)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.route),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailStat(
      String value, String label, IconData icon, Color color) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _vDivider() => Container(
        width: 1,
        height: 50,
        color: AppColors.divider,
      );
}
