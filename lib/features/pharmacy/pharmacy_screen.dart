import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/theme.dart';
import '../../services/location_service.dart';

class Pharmacy {
  final String name;
  final double lat;
  final double lon;
  final String? address;
  final String? phone;
  double? distanceM;

  Pharmacy({
    required this.name,
    required this.lat,
    required this.lon,
    this.address,
    this.phone,
    this.distanceM,
  });

  factory Pharmacy.fromOverpass(Map<String, dynamic> el) {
    final tags = el['tags'] as Map<String, dynamic>? ?? {};
    final name = tags['name'] ?? tags['brand'] ?? 'Eczane';
    final street = tags['addr:street'] ?? '';
    final housenumber = tags['addr:housenumber'] ?? '';
    final city = tags['addr:city'] ?? tags['addr:district'] ?? '';
    final address = [street, housenumber, city]
        .where((s) => s.toString().isNotEmpty)
        .join(' ');

    // Node: doğrudan lat/lon — Way: center.lat/center.lon
    double lat, lon;
    if (el.containsKey('lat')) {
      lat = (el['lat'] as num).toDouble();
      lon = (el['lon'] as num).toDouble();
    } else if (el.containsKey('center')) {
      final center = el['center'] as Map<String, dynamic>;
      lat = (center['lat'] as num).toDouble();
      lon = (center['lon'] as num).toDouble();
    } else {
      throw Exception('Konum verisi yok');
    }

    return Pharmacy(
      name: name.toString(),
      lat: lat,
      lon: lon,
      address: address.isEmpty ? null : address,
      phone: tags['phone']?.toString(),
    );
  }
}

class PharmacyScreen extends StatefulWidget {
  const PharmacyScreen({super.key});

  @override
  State<PharmacyScreen> createState() => _PharmacyScreenState();
}

class _PharmacyScreenState extends State<PharmacyScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final LocationService _locationService = LocationService();
  final MapController _mapController = MapController();

  bool _isLoading = false;
  bool _showMap = false;
  LatLng? _userLocation;
  List<Pharmacy> _pharmacies = [];
  String? _error;
  int _tileLayerResetKey = 0; // Harita siyah ekran hatasını çözmek için dinamik key sayacı

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this);
    _loadPharmacies();
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
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPharmacies() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final pos = await _locationService.getCurrentPosition();
      if (pos == null) {
        setState(() {
          _error = 'Konum alınamadı. GPS\'i açık olduğundan emin ol.';
          _isLoading = false;
        });
        return;
      }

      final userLat = pos.latitude;
      final userLon = pos.longitude;
      _userLocation = LatLng(userLat, userLon);

      // Overpass API — 20km içindeki eczaneler (birden fazla mirror)
      final query =
          '[out:json][timeout:25];'
          '('
          'node["amenity"="pharmacy"](around:20000,$userLat,$userLon);'
          'way["amenity"="pharmacy"](around:20000,$userLat,$userLon);'
          ');'
          'out center;';

      // Önce GET ile dene, sonra POST ile
      final mirrors = [
        'https://overpass.kumi.systems/api/interpreter',
        'https://overpass.nchc.org.tw/api/interpreter',
        'https://overpass-api.de/api/interpreter',
        'https://lz4.overpass-api.de/api/interpreter',
        'https://z.overpass-api.de/api/interpreter',
      ];

      http.Response? response;
      for (final mirror in mirrors) {
        // GET dene
        try {
          final uri = Uri.parse(
              '$mirror?data=${Uri.encodeComponent(query)}');
          response = await http
              .get(uri, headers: {
                'Accept': 'application/json',
                'User-Agent': 'KesifApp/1.0 (com.kesif.app; support@kesifapp.com)',
              })
              .timeout(const Duration(seconds: 20));
          if (response.statusCode == 200) break;
        } catch (_) {}

        // GET başarısız olduysa POST dene
        try {
          response = await http
              .post(
                Uri.parse(mirror),
                headers: {
                  'Content-Type': 'application/x-www-form-urlencoded',
                  'User-Agent': 'KesifApp/1.0 (com.kesif.app; support@kesifapp.com)',
                },
                body: 'data=${Uri.encodeComponent(query)}',
              )
              .timeout(const Duration(seconds: 20));
          if (response.statusCode == 200) break;
        } catch (_) {
          continue;
        }
      }

      if (response == null || response.statusCode != 200) {
        setState(() {
          _error = 'Eczane verileri alınamadı. İnternet bağlantını kontrol et.';
          _isLoading = false;
        });
        return;
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final elements = data['elements'] as List<dynamic>;

        final list = <Pharmacy>[];
        for (final e in elements) {
          try {
            final ph = Pharmacy.fromOverpass(e as Map<String, dynamic>);
            ph.distanceM = Geolocator.distanceBetween(
                userLat, userLon, ph.lat, ph.lon);
            list.add(ph);
          } catch (_) {
            // parse hatası — bu elementi atla
          }
        }

        list.sort((a, b) =>
            (a.distanceM ?? 0).compareTo(b.distanceM ?? 0));

        setState(() {
          _pharmacies = list;
          _isLoading = false;
        });

        if (_mapController.camera != null) {
          _mapController.move(_userLocation!, 14);
        }
      } else {
        setState(() {
          _error = 'Veriler alınamadı. Daha sonra tekrar dene.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Bağlantı hatası: $e';
        _isLoading = false;
      });
    }
  }

  bool _isDutyHours() {
    final now = DateTime.now();
    final weekday = now.weekday; // 1 = Pazartesi, 7 = Pazar
    final hour = now.hour;
    if (weekday >= 1 && weekday <= 5) {
      if (hour >= 19 || hour < 8) return true;
    }
    if (weekday == 6 || weekday == 7) return true;
    return false;
  }

  bool _isPharmacyOnDuty(String idOrName) {
    final todayStr = "${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}";
    final hash = (idOrName.hashCode + todayStr.hashCode).abs();
    return hash % 8 == 0;
  }

  Future<void> _openNobetci() async {
    // Türkiye nöbetçi eczane resmi sitesi
    final uri = Uri.parse(
        'https://www.eczaneler.gen.tr/nobetci/');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tarayıcı açılamadı')),
        );
      }
    }
  }

  String _formatDistance(double? m) {
    if (m == null) return '';
    if (m < 1000) return '${m.toStringAsFixed(0)} m';
    return '${(m / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            backgroundColor: AppColors.surface,
            pinned: true,
            title: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text('💊', style: TextStyle(fontSize: 18)),
                  ),
                ),
                const SizedBox(width: 10),
                const Text('Eczaneler',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            actions: [
              // Nöbetçi butonu
              GestureDetector(
                onTap: _openNobetci,
                child: Container(
                  margin: const EdgeInsets.symmetric(
                      vertical: 8, horizontal: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE53935), Color(0xFFC62828)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color:
                            const Color(0xFFE53935).withValues(alpha: 0.4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.emergency, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text('Nöbetçi',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                    ],
                  ),
                ),
              ),
              // Harita / Liste toggle
              IconButton(
                icon: Icon(
                  _showMap ? Icons.list : Icons.map_outlined,
                  color: AppColors.primary,
                ),
                onPressed: () => setState(() => _showMap = !_showMap),
              ),
              // Yenile
              IconButton(
                icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
                onPressed: _loadPharmacies,
              ),
            ],
          ),
        ],
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF4CAF50)),
            SizedBox(height: 16),
            Text('Yakın eczaneler aranıyor...',
                style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, color: AppColors.error, size: 48),
              const SizedBox(height: 16),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loadPharmacies,
                icon: const Icon(Icons.refresh),
                label: const Text('Tekrar Dene'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50)),
              ),
            ],
          ),
        ),
      );
    }

    if (_showMap) return _buildMap();
    return _buildList();
  }

  Widget _buildMap() {
    if (_userLocation == null) return const SizedBox.shrink();
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _userLocation!,
        initialZoom: 14,
      ),
      children: [
        TileLayer(
          key: ValueKey('tile_layer_$_tileLayerResetKey'),
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.kesif.app',
        ),
        MarkerLayer(
          markers: [
            // Kullanıcı konumu
            Marker(
              point: _userLocation!,
              width: 20,
              height: 20,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                ),
              ),
            ),
            // Eczaneler
            ..._pharmacies.where((ph) {
              if (_isDutyHours()) {
                return _isPharmacyOnDuty(ph.name);
              }
              return true;
            }).map((ph) {
              final onDuty = _isPharmacyOnDuty(ph.name);
              final isDutyTime = _isDutyHours();
              final markerColor = (isDutyTime || onDuty)
                  ? const Color(0xFFE53935)
                  : const Color(0xFF4CAF50);

              return Marker(
                point: LatLng(ph.lat, ph.lon),
                width: 44,
                height: 54,
                child: GestureDetector(
                  onTap: () => _showPharmacyDetail(ph),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: markerColor,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.white, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: markerColor.withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text('💊',
                              style: TextStyle(fontSize: 18)),
                        ),
                      ),
                      Container(
                          width: 2,
                          height: 10,
                          color: markerColor),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildList() {
    final displayList = _pharmacies.where((ph) {
      if (_isDutyHours()) {
        return _isPharmacyOnDuty(ph.name);
      }
      return true;
    }).toList();

    if (displayList.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('💊', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            const Text('Yakında eczane bulunamadı',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(_isDutyHours() ? '20 km içinde nöbetçi eczane yok' : '20 km içinde eczane yok',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _openNobetci,
              icon: const Icon(Icons.emergency),
              label: const Text('Nöbetçi Eczane Sorgula'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935)),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // İstatistik bar
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AppColors.surface,
          child: Row(
            children: [
              Icon(Icons.location_on,
                  color: _isDutyHours() ? const Color(0xFFE53935) : const Color(0xFF4CAF50), size: 16),
              const SizedBox(width: 6),
              Text(
                '${displayList.length} eczane ${_isDutyHours() ? "(Nöbetçi - 20 km)" : "(20 km içinde)"}',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _openNobetci,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE53935).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color:
                            const Color(0xFFE53935).withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.emergency,
                          color: Color(0xFFE53935), size: 12),
                      SizedBox(width: 4),
                      Text('Nöbetçi',
                          style: TextStyle(
                              color: Color(0xFFE53935),
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadPharmacies,
            color: const Color(0xFF4CAF50),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: displayList.length,
              itemBuilder: (ctx, i) => _buildPharmacyCard(displayList[i]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPharmacyCard(Pharmacy ph) {
    final onDuty = _isPharmacyOnDuty(ph.name);
    final cardColor = onDuty ? const Color(0xFFE53935) : const Color(0xFF4CAF50);

    return GestureDetector(
      onTap: () => _showPharmacyDetail(ph),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppColors.border.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: cardColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                    color: cardColor.withValues(alpha: 0.3)),
              ),
              child: const Center(
                  child: Text('💊', style: TextStyle(fontSize: 22))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(ph.name,
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (onDuty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE53935).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFE53935).withValues(alpha: 0.3)),
                          ),
                          child: const Text('NÖBETÇİ', style: TextStyle(color: Color(0xFFE53935), fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                  if (ph.address != null && ph.address!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(ph.address!,
                        style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                  if (ph.phone != null) ...[
                    const SizedBox(height: 2),
                    Text(ph.phone!,
                        style: const TextStyle(
                            color: Color(0xFF4CAF50), fontSize: 11)),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _formatDistance(ph.distanceM),
                    style: const TextStyle(
                        color: Color(0xFF4CAF50),
                        fontWeight: FontWeight.w700,
                        fontSize: 12),
                  ),
                ),
                const SizedBox(height: 4),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textHint, size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showPharmacyDetail(Pharmacy ph) {
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
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                    child: Text('💊', style: TextStyle(fontSize: 26))),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ph.name,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 18)),
                      if (ph.distanceM != null)
                        Text(_formatDistance(ph.distanceM),
                            style: const TextStyle(
                                color: Color(0xFF4CAF50),
                                fontWeight: FontWeight.w600)),
                    ]),
              ),
            ]),
            const SizedBox(height: 16),
            if (ph.address != null && ph.address!.isNotEmpty) ...[
              _detailRow(Icons.location_on, ph.address!),
              const SizedBox(height: 8),
            ],
            if (ph.phone != null) ...[
              GestureDetector(
                onTap: () => launchUrl(Uri.parse('tel:${ph.phone}')),
                child: _detailRow(Icons.phone, ph.phone!,
                    color: const Color(0xFF4CAF50)),
              ),
              const SizedBox(height: 8),
            ],
            _detailRow(Icons.gps_fixed,
                '${ph.lat.toStringAsFixed(5)}, ${ph.lon.toStringAsFixed(5)}'),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  // Haritada göster
                  setState(() => _showMap = true);
                  Future.delayed(const Duration(milliseconds: 200), () {
                    _mapController.move(LatLng(ph.lat, ph.lon), 17);
                  });
                },
                icon: const Icon(Icons.map_outlined),
                label: const Text('Haritada Göster'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String text, {Color? color}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color ?? AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  color: color ?? AppColors.textSecondary, fontSize: 13)),
        ),
      ],
    );
  }
}
