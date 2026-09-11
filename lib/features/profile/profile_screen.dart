import 'dart:io';
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../services/database_service.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../../shared/models/models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'friends_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final DatabaseService _db = DatabaseService();
  final AuthService _auth = AuthService();
  Map<String, dynamic> _stats = {};
  List<DiscoveryPoint> _myPoints = [];
  List<Map<String, dynamic>> _myVisits = [];
  bool _isLoading = true;
  String _nickname = 'Yükleniyor...';
  late TabController _tabController;
  static const bool _showSocialFeature = false; // Sosyal özellikleri aktifleştirmek için true yapın

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if ((_tabController.index == 1 || _tabController.index == 2) && !_tabController.indexIsChanging) {
        _loadData();
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final stats = await _db.getStats();
    final points = await _db.getUserPoints();
    
    List<Map<String, dynamic>> myVisits = [];
    String nick = 'Keşifçi';
    final user = _auth.currentUser;
    if (user != null) {
      try {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('nickname')
            .eq('id', user.id)
            .maybeSingle();
        if (profile != null && profile['nickname'] != null) {
          nick = profile['nickname'] as String;
        } else {
          nick = user.email?.split('@').first ?? 'Keşifçi';
        }
      } catch (_) {
        nick = user.email?.split('@').first ?? 'Keşifçi';
      }

      try {
        List<dynamic> visitsData;
        try {
          // Önce join ile dene (Supabase'de FK tanımlıysa çalışır)
          final res = await Supabase.instance.client
              .from('point_visits')
              .select('rating, created_at, point_id, discovery_points(*)')
              .eq('user_id', user.id);
          visitsData = res as List<dynamic>;
          myVisits = List<Map<String, dynamic>>.from(
            visitsData.where((v) => v['discovery_points'] != null),
          );
        } catch (_) {
          // Join yoksa önce point_id'leri çek, sonra noktaları ayrıca sorgula
          final res = await Supabase.instance.client
              .from('point_visits')
              .select('rating, created_at, point_id')
              .eq('user_id', user.id);
          visitsData = res as List<dynamic>;

          if (visitsData.isNotEmpty) {
            final pointIds = visitsData.map((v) => v['point_id'] as String).toList();
            try {
              final pointsRes = await Supabase.instance.client
                  .from('discovery_points')
                  .select('*')
                  .inFilter('id', pointIds);
              final pointsMap = <String, dynamic>{
                for (final p in pointsRes as List<dynamic>) p['id'] as String: p,
              };
              myVisits = List<Map<String, dynamic>>.from(
                visitsData.map((v) {
                  final pid = v['point_id'] as String;
                  return {
                    'rating': v['rating'],
                    'created_at': v['created_at'],
                    'discovery_points': pointsMap[pid],
                  };
                }).where((v) => v['discovery_points'] != null),
              );
            } catch (_) {
              // Noktalar da çekilemediyse boş bırak
              myVisits = [];
            }
          }
        }
      } catch (e) {
        debugPrint('Kullanıcı ziyaret verisi yükleme hatası: $e');
      }
    }

    if (mounted) {
      setState(() {
        _stats = stats;
        _myPoints = points;
        _myVisits = myVisits;
        _nickname = nick;
        _isLoading = false;
      });
    }
  }

  Future<void> _deletePoint(DiscoveryPoint point) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Pin\'i Sil',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          '"${point.title}" adlı keşif noktasını silmek istiyor musun?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _db.deletePoint(point.id);
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pin silindi'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // Header
          SliverAppBar(
            backgroundColor: AppColors.surface,
            expandedHeight: 200,
            pinned: true,
            bottom: TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              indicatorSize: TabBarIndicatorSize.label,
              tabs: const [
                Tab(text: 'Profilim'),
                Tab(text: 'Gittiğim Yerler'),
                Tab(text: 'İşaretlerim'),
              ],
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.secondary, AppColors.surface],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 48),
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.secondary],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.35),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ],
                        border: Border.all(color: Colors.white, width: 2.5),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.explore_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '@$_nickname',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildUserBadge(),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout, color: AppColors.textSecondary),
                onPressed: () async {
                  await _auth.signOut();
                },
              ),
            ],
          ),
          // Tab içeriği
          SliverFillRemaining(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Profilim
                _buildProfileTab(),
                // Tab 2: Gittiğim Yerler
                _buildGittigimYerlerTab(),
                // Tab 3: İşaretlerim
                _buildMyPinsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserBadge() {
    final isPremium = AuthService.isPremiumMock;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPremium
              ? [const Color(0xFFFFD700), const Color(0xFFFFA500)]
              : [const Color(0xFF2196F3), const Color(0xFF1976D2)],
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: (isPremium ? const Color(0xFFFFD700) : const Color(0xFF2196F3))
                .withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: Text(
        isPremium ? '💎 PREMIUM' : '👤 STANDART',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildProfileTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isLoading)
            const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
          else
            _buildStatsGrid(),
          if (_showSocialFeature) ...[
            _buildSection('Sosyal', _buildSocialSection()),
            const SizedBox(height: 24),
          ],
          _buildSection('Rozetler', _buildBadges()),
          const SizedBox(height: 24),
          _buildSection('Uygulama Hakkında', _buildAbout()),
          const SizedBox(height: 24),
          _buildDeleteAccountSection(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildDeleteAccountSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shield_outlined, color: AppColors.error, size: 20),
              SizedBox(width: 8),
              Text(
                'Hesap & Gizlilik (KVKK)',
                style: TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Hesabınızı ve tüm kişisel verilerinizi sunucularımızdan kalıcı olarak silebilirsiniz.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _confirmDeleteAccount,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.delete_forever_rounded, size: 20),
              label: const Text(
                'Hesabımı ve Verilerimi Kalıcı Sil',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAccount() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 24),
            SizedBox(width: 10),
            Text('Kalıcı Silme Onayı', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: const Text(
          'Hesabınızı sildiğinizde eklediğiniz keşif noktaları, sohbet mesajlarınız, arkadaşlıklarınız ve tüm profil verileriniz GERİ DÖNDÜRÜLEMEZ şekilde silinecektir.\n\nDevam etmek istiyor musunuz?',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal', style: TextStyle(color: AppColors.textHint)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.pop(ctx);
              _secondConfirmationDeleteAccount();
            },
            child: const Text('Evet, Silmek İstiyorum', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _secondConfirmationDeleteAccount() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Son Onay', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 18)),
        content: const Text('Bu işlem GERİ ALINAMAZ. Hesabınız şu an tamamen silinecektir.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç', style: TextStyle(color: AppColors.textHint)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await ChatService().deleteAccount();
              if (mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Hesabınız ve tüm verileriniz silindi.'),
                      backgroundColor: AppColors.primary,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  Navigator.of(context).pushReplacementNamed('/login');
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Hesap silme işlemi gerçekleştirilemedi.'),
                      backgroundColor: AppColors.error,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            child: const Text('HESABIMI KALICI SİL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildMyPinsTab() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }

    if (_myPoints.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadData,
        color: AppColors.primary,
        child: ListView(
          children: [
            const SizedBox(height: 80),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.2)),
                    ),
                    child: const Icon(Icons.location_off_rounded,
                        color: AppColors.primary, size: 48),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Henüz pin eklemedin',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Haritada uzun bas ve ilk keşif noktanı ekle!',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _myPoints.length,
        itemBuilder: (ctx, i) => _buildPinCard(_myPoints[i]),
      ),
    );
  }

  Widget _buildPinCard(DiscoveryPoint point) {
    final color = Color(point.category.colorValue);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          // Fotoğraf
          if (point.imagePath != null && point.imagePath!.isNotEmpty)
            ClipRRect(
              borderRadius:
                  const BorderRadius.horizontal(left: Radius.circular(18)),
              child: Image.file(
                File(point.imagePath!),
                width: 90,
                height: 90,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _emojiBox(point, color),
              ),
            )
          else
            _emojiBox(point, color),

          // İçerik
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    point.title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(point.category.emoji,
                                style: const TextStyle(fontSize: 11)),
                            const SizedBox(width: 3),
                            Text(point.category.labelTR,
                                style: TextStyle(
                                    color: color,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${point.createdAt.day}.${point.createdAt.month}.${point.createdAt.year}',
                    style: const TextStyle(
                        color: AppColors.textHint, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),

          // Sil butonu
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.error, size: 22),
              onPressed: () => _deletePoint(point),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emojiBox(DiscoveryPoint point, Color color) {
    return Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius:
            const BorderRadius.horizontal(left: Radius.circular(18)),
      ),
      child: Center(
        child: Text(point.category.emoji,
            style: const TextStyle(fontSize: 34)),
      ),
    );
  }

  Widget _buildStatsGrid() {
    final routeCount = _stats['routeCount'] ?? 0;
    final totalDist = (_stats['totalDistance'] ?? 0.0) as double;
    final pointCount = _stats['pointCount'] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('İstatistiklerim',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
                child: _statCard(
                    '$routeCount', 'Rota', Icons.route, AppColors.route)),
            const SizedBox(width: 12),
            Expanded(
                child: _statCard(
                    totalDist < 1000
                        ? '${totalDist.toStringAsFixed(0)} m'
                        : '${(totalDist / 1000).toStringAsFixed(1)} km',
                    'Yürünen',
                    Icons.straighten,
                    AppColors.accent)),
            const SizedBox(width: 12),
            Expanded(
                child: _statCard('$pointCount', 'Keşif',
                    Icons.location_on, AppColors.primary)),
          ],
        ),
      ],
    );
  }

  Widget _statCard(String value, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildSection(String title, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 14),
        content,
      ],
    );
  }

  Widget _buildBadges() {
    final routeCount = _stats['routeCount'] ?? 0;
    final totalDist = (_stats['totalDistance'] ?? 0.0) as double;
    final badges = [
      {
        'icon': '🚶',
        'title': 'İlk Adım',
        'desc': 'İlk rotanı kaydet',
        'unlocked': routeCount >= 1
      },
      {
        'icon': '🗺️',
        'title': 'Kaşif',
        'desc': '5 rota kaydet',
        'unlocked': routeCount >= 5
      },
      {
        'icon': '🏃',
        'title': 'Koşucu',
        'desc': '10 km yürü',
        'unlocked': totalDist >= 10000
      },
      {
        'icon': '⭐',
        'title': 'Yıldız Kaşif',
        'desc': '50 km yürü',
        'unlocked': totalDist >= 50000
      },
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.2,
      children: badges.map((b) => _badgeCard(b)).toList(),
    );
  }

  Widget _badgeCard(Map<String, dynamic> badge) {
    final unlocked = badge['unlocked'] as bool;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: unlocked
            ? AppColors.primary.withValues(alpha: 0.1)
            : AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: unlocked
              ? AppColors.primary.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Text(
            badge['icon'] as String,
            style: TextStyle(
                fontSize: 24,
                color: unlocked ? null : Colors.transparent),
          ),
          if (!unlocked)
            const Icon(Icons.lock, color: AppColors.textHint, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  badge['title'] as String,
                  style: TextStyle(
                    color: unlocked
                        ? AppColors.textPrimary
                        : AppColors.textHint,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  badge['desc'] as String,
                  style:
                      const TextStyle(color: AppColors.textHint, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAbout() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _aboutRow(Icons.map_outlined, 'Harita', 'OpenStreetMap'),
          const Divider(color: AppColors.divider, height: 24),
          _aboutRow(Icons.location_on_outlined, 'Konum', 'Cihaz GPS'),
          const Divider(color: AppColors.divider, height: 24),
          _aboutRow(Icons.storage_outlined, 'Veri', 'Supabase + Yerel DB'),
          const Divider(color: AppColors.divider, height: 24),
          _aboutRow(Icons.info_outline, 'Versiyon', '1.0.0'),
        ],
      ),
    );
  }

  Widget _aboutRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: AppColors.textSecondary, size: 20),
        const SizedBox(width: 12),
        Text(label,
            style: const TextStyle(color: AppColors.textSecondary)),
        const Spacer(),
        Text(value,
            style: const TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildSocialSection() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.people_alt_rounded, color: AppColors.primary),
        ),
        title: const Text(
          'Arkadaşlarım & Sohbet',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: const Text(
          'Arkadaş ekle, istekleri yönet ve sohbet et',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FriendsScreen()),
          );
        },
      ),
    );
  }

  Widget _buildGittigimYerlerTab() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }

    if (_myVisits.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadData,
        color: AppColors.primary,
        child: ListView(
          children: [
            const SizedBox(height: 80),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_box_outline_blank,
                        color: AppColors.primary, size: 48),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Henüz bir yere gitmedin',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Haritadaki yer işaretlerinin 10m yakınına git,\n"Gittim & Puan Ver" seçeneğiyle ziyaret et!',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _myVisits.length,
        itemBuilder: (ctx, i) {
          final visit = _myVisits[i];
          final pointData = visit['discovery_points'] as Map<String, dynamic>;
          final rating = visit['rating'] as int;
          final dateStr = visit['created_at'] != null 
              ? DateTime.parse(visit['created_at'] as String) 
              : DateTime.now();

          // DiscoveryPoint modeline dönüştür
          final point = DiscoveryPoint(
            id: pointData['id'] as String,
            title: pointData['title'] as String,
            description: (pointData['description'] ?? '') as String,
            latitude: (pointData['latitude'] as num).toDouble(),
            longitude: (pointData['longitude'] as num).toDouble(),
            category: PointCategory.values[pointData['category'] as int],
            likes: (pointData['likes'] ?? 0) as int,
            createdAt: DateTime.parse(pointData['created_at'] as String),
            isUserAdded: false,
          );

          return _buildVisitCard(point, rating, dateStr);
        },
      ),
    );
  }

  Widget _buildVisitCard(DiscoveryPoint point, int rating, DateTime date) {
    final color = Color(point.category.colorValue);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          // Emoji kutusu
          _emojiBox(point, color),
          const SizedBox(width: 14),

          // İçerik
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    point.title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: List.generate(5, (index) {
                      return Icon(
                        index < rating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 16,
                      );
                    }),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Ziyaret: ${date.day}.${date.month}.${date.year}',
                    style: const TextStyle(
                        color: AppColors.textHint, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),

          // Ziyaret simgesi
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: Colors.green, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
