import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../services/database_service.dart';
import '../../services/auth_service.dart';
import '../../shared/models/models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'point_detail_sheet.dart';
import '../../app/main_shell.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../map/map_screen.dart';
import '../../services/events_service.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'event_detail_sheet.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  static VoidCallback? refreshPoints;

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen>
    with SingleTickerProviderStateMixin {
  final DatabaseService _db = DatabaseService();
  List<DiscoveryPoint> _points = [];
  Map<String, List<int>> _pointRatings = {};
  PointCategory? _activeFilter;
  bool _isLoading = true;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  // Etkinlikler
  List<EventModel> _events = [];
  bool _eventsLoading = true;
  String? _currentCity;
  String? _currentDistrict;
  final EventsService _eventsService = EventsService();
  bool _showEventsTab = false;
  Position? _userPosition;

  @override
  void initState() {
    super.initState();
    DiscoveryScreen.refreshPoints = _loadPoints;
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _loadPoints();
    _loadEvents();
  }

  @override
  void dispose() {
    DiscoveryScreen.refreshPoints = null;
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadPoints() async {
    setState(() => _isLoading = true);
    
    final localPoints = _activeFilter != null
        ? await _db.getPointsByCategory(_activeFilter!)
        : await _db.getAllPoints();

    List<DiscoveryPoint> initialPoints = List.from(localPoints);
    final double activeRadiusKm = MapScreen.selectedRadiusKm ?? 5.0;
    try {
      final pos = await Geolocator.getCurrentPosition();
      initialPoints = initialPoints.where((p) {
        final dist = Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          p.latitude,
          p.longitude,
        );
        return dist <= (activeRadiusKm * 1000);
      }).toList();
    } catch (_) {}

    if (mounted) {
      setState(() {
        _points = initialPoints;
        _isLoading = false;
      });
      _animController.forward(from: 0.0);
    }

    try {
      var query = Supabase.instance.client
          .from('discovery_points')
          .select('*');
      
      if (_activeFilter != null) {
        query = query.eq('category', _activeFilter!.index);
      }

      final publicPointsRes = await query;
      final List<dynamic> data = publicPointsRes as List<dynamic>;

      List<DiscoveryPoint> updatedPoints = List.from(localPoints);
      for (final p in data) {
        final id = p['id'] as String;
        if (updatedPoints.any((lp) => lp.id == id)) continue;

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
          addedByNickname: (p['added_by_nickname'] ?? 'Gezgin') as String?,
          isPetFriendly: (p['is_pet_friendly'] ?? false) as bool,
        ));
      }

      try {
        final pos = await Geolocator.getCurrentPosition();
        updatedPoints = updatedPoints.where((p) {
          final dist = Geolocator.distanceBetween(
            pos.latitude,
            pos.longitude,
            p.latitude,
            p.longitude,
          );
          return dist <= (activeRadiusKm * 1000);
        }).toList();
      } catch (_) {}

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
      } catch (_) {}

      updatedPoints.sort((a, b) {
        final aRatings = pointRatings[a.id] ?? [];
        final bRatings = pointRatings[b.id] ?? [];
        
        final aVisits = aRatings.length;
        final bVisits = bRatings.length;
        
        final aAvg = aVisits > 0 ? aRatings.reduce((x, y) => x + y) / aVisits : 0.0;
        final bAvg = bVisits > 0 ? bRatings.reduce((x, y) => x + y) / bVisits : 0.0;

        if (aAvg != bAvg) {
          return bAvg.compareTo(aAvg);
        }
        if (aVisits != bVisits) {
          return bVisits.compareTo(aVisits);
        }
        return b.likes.compareTo(a.likes);
      });

      if (mounted) {
        setState(() {
          _points = updatedPoints;
          _pointRatings = pointRatings;
        });
      }
    } catch (e) {
      print('Supabase noktaları yükleme hatası: $e');
    }
  }

  Future<void> _loadEvents() async {
    try {
      final location = await _eventsService.getCurrentLocation();
      final targetCity = location['city'] ?? 'İstanbul';
      final district = location['district'];

      if (mounted) {
        setState(() {
          _currentCity = targetCity;
          _currentDistrict = district;
        });
      }

      List<EventModel> events = await _eventsService.getEventsByCity(targetCity);
        
        // Kullanıcının anlık konumunu al
        try {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
          );
          
          if (mounted) {
            setState(() {
              _userPosition = pos;
            });
          }
          
          // Etkinlikleri mesafeye göre sırala (en yakın en üstte)
          events.sort((a, b) {
            if (a.latitude == null || a.longitude == null) return 1;
            if (b.latitude == null || b.longitude == null) return -1;
            
            final distA = Geolocator.distanceBetween(
              pos.latitude,
              pos.longitude,
              a.latitude!,
              a.longitude!,
            );
            final distB = Geolocator.distanceBetween(
              pos.latitude,
              pos.longitude,
              b.latitude!,
              b.longitude!,
            );
            return distA.compareTo(distB);
          });
        } catch (_) {}

      if (mounted) {
        setState(() {
          _events = events;
          _eventsLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _eventsLoading = false);
    }
  }

  void _showPointDetail(DiscoveryPoint point) async {
    LatLng? userPos;
    try {
      final pos = await Geolocator.getCurrentPosition();
      userPos = LatLng(pos.latitude, pos.longitude);
    } catch (_) {}

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PointDetailSheet(
        point: point,
        userLocation: userPos,
        onLiked: () => _loadPoints(),
        onNavigate: () {
          MainShell.shellKey.currentState?.switchTab(0, navigateToPoint: point);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          _buildHeader(),
          _buildFilterBar(),
          if (_showEventsTab)
            _buildEventsVerticalList()
          else if (_isLoading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (_points.isEmpty)
            SliverFillRemaining(child: _buildEmpty())
          else
            _buildPointsList(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return SliverAppBar(
      expandedHeight: 140,
      floating: true,
      snap: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _showEventsTab ? Icons.event_note_rounded : Icons.explore_rounded,
                          color: AppColors.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _showEventsTab ? 'Etkinlikler' : 'Keşfet',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          _showEventsTab
                              ? '${_events.where((e) => e.startDate.isBefore(DateTime.now().add(const Duration(days: 10)))).length} etkinlik'
                              : '${_points.length} nokta',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _showEventsTab
                        ? '${_currentCity ?? "Şehriniz"} için 10 günlük etkinlik planı'
                        : (_activeFilter != null
                            ? '${_activeFilter!.emoji} ${_activeFilter!.labelTR} kategorisinde'
                            : 'Tüm kategorilerde keşif noktaları'),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _FilterBarDelegate(
        child: Container(
          color: AppColors.background,
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _chip(null, 'Tümü', Icons.layers_rounded, isEvents: false),
              _eventsChip(),
              ...PointCategory.values
                  .map((c) => _chip(c, c.labelTR, null, emoji: c.emoji, isEvents: false)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _eventsChip() {
    final isActive = _showEventsTab;
    const color = Color(0xFFE91E63);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _showEventsTab = true;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: isActive
                ? const LinearGradient(
                    colors: [color, Color(0xFFFF5722)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isActive ? null : AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isActive ? color : AppColors.border,
              width: isActive ? 0 : 1,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    )
                  ]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🎭', style: TextStyle(fontSize: 15)),
              const SizedBox(width: 6),
              Text(
                'Etkinlikler',
                style: TextStyle(
                  color: isActive ? Colors.white : AppColors.textSecondary,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(PointCategory? cat, String label, IconData? icon,
      {String? emoji, required bool isEvents}) {
    final isActive = isEvents ? _showEventsTab : (!_showEventsTab && _activeFilter == cat);
    final color =
        cat != null ? Color(cat.colorValue) : AppColors.primary;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _showEventsTab = isEvents;
            if (!isEvents) _activeFilter = cat;
          });
          if (!isEvents) _loadPoints();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: isActive
                ? LinearGradient(
                    colors: [
                      color,
                      color.withValues(alpha: 0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isActive ? null : AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isActive ? color : AppColors.border,
              width: isActive ? 0 : 1,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    )
                  ]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (emoji != null)
                Text(emoji, style: const TextStyle(fontSize: 15))
              else if (icon != null)
                Icon(icon,
                    size: 15,
                    color: isActive ? Colors.white : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.white : AppColors.textSecondary,
                  fontWeight:
                      isActive ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEventsVerticalList() {
    final limitDate = DateTime.now().add(const Duration(days: 10));
    final activeEvents = _events.where((e) => e.startDate.isBefore(limitDate)).toList();

    if (_eventsLoading) {
      return const SliverFillRemaining(
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFFE91E63)),
        ),
      );
    }

    if (activeEvents.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('📅', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 16),
                Text(
                  _currentCity != null
                      ? '$_currentCity için 10 gün içinde gerçekleşecek bir sosyal etkinlik bulunamadı.'
                      : 'Şehrinizde yaklaşan etkinlik bulunamadı.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) => _buildVerticalEventCard(activeEvents[i]),
          childCount: activeEvents.length,
        ),
      ),
    );
  }

  Widget _buildVerticalEventCard(EventModel event) {
    final style = EventsService.getCategoryStyle(event.category);
    final color = Color(style['color'] as int);
    final icon = style['icon'] as String;
    final label = style['label'] as String;

    String dateStr = '';
    try {
      dateStr = DateFormat('d MMMM yyyy, HH:mm', 'tr').format(event.startDate.toLocal());
    } catch (_) {
      dateStr = DateFormat('d MMMM').format(event.startDate.toLocal());
    }

    String? distanceStr;
    if (_userPosition != null && event.latitude != null && event.longitude != null) {
      final dist = Geolocator.distanceBetween(
        _userPosition!.latitude,
        _userPosition!.longitude,
        event.latitude!,
        event.longitude!,
      );
      if (dist >= 1000) {
        distanceStr = '${(dist / 1000).toStringAsFixed(1)} km uzaklıkta';
      } else {
        distanceStr = '${dist.toStringAsFixed(0)} m uzaklıkta';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => EventDetailSheet(
                event: event,
                userLocation: _userPosition != null ? LatLng(_userPosition!.latitude, _userPosition!.longitude) : null,
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (event.imageUrl != null)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  child: Image.network(
                    event.imageUrl!,
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _eventImagePlaceholder(color, icon),
                  ),
                )
              else
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  child: _eventImagePlaceholder(color, icon),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: color.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            '$icon $label',
                            style: TextStyle(
                              color: color,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.3)),
                          ),
                          child: const Text(
                            'ÜCRETSİZ',
                            style: TextStyle(
                              color: Color(0xFF4CAF50),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (event.city != null)
                          Text(
                            event.city!,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      event.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (event.description != null && event.description!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        event.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.schedule_rounded, size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            dateStr,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (event.district != null || event.locationName != null || distanceStr != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.location_on_rounded, size: 16, color: AppColors.textSecondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              distanceStr != null
                                  ? '${event.locationName ?? event.district ?? ""} ($distanceStr)'
                                  : (event.locationName ?? event.district ?? ''),
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _eventImagePlaceholder(Color color, String icon) {
    return Container(
      height: 150,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.8), color.withValues(alpha: 0.4)],
        ),
      ),
      child: Center(
        child: Text(icon, style: const TextStyle(fontSize: 48)),
      ),
    );
  }

  Widget _buildPointsList() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) => FadeTransition(
            opacity: _fadeAnim,
            child: _buildCard(_points[i], i),
          ),
          childCount: _points.length,
        ),
      ),
    );
  }

  Widget _buildCard(DiscoveryPoint point, int index) {
    final color = Color(point.category.colorValue);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showPointDetail(point),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        point.category.emoji,
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            point.title,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            point.category.labelTR,
                            style: TextStyle(
                              color: color,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (point.description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    point.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    if ((_pointRatings[point.id] ?? []).isNotEmpty) ...[
                      const Icon(Icons.star_rounded,
                          color: Color(0xFFFFB300), size: 18),
                      const SizedBox(width: 4),
                      Text(
                        ((_pointRatings[point.id]!.reduce((a, b) => a + b) /
                                _pointRatings[point.id]!.length))
                            .toStringAsFixed(1),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '(${_pointRatings[point.id]!.length})',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                    const Icon(Icons.favorite_rounded,
                        color: Color(0xFFE91E63), size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '${point.likes}',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (point.isPetFriendly)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Text('🐾', style: TextStyle(fontSize: 11)),
                            SizedBox(width: 4),
                            Text(
                              'Pet Dostu',
                              style: TextStyle(
                                color: Color(0xFF4CAF50),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.explore_off_rounded,
                color: AppColors.primary,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Burada Henüz Keşif Noktası Yok',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Haritaya uzun basarak ilk keşif noktasını sen ekleyebilirsin!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  const _FilterBarDelegate({required this.child});

  @override
  double get minExtent => 56;

  @override
  double get maxExtent => 56;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(_FilterBarDelegate oldDelegate) {
    return oldDelegate.child != child;
  }
}
