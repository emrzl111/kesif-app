import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../app/theme.dart';
import '../../services/database_service.dart';
import '../../services/chat_service.dart';
import '../../services/auth_service.dart';
import '../../shared/widgets/premium_paywall_sheet.dart';
import '../../shared/models/models.dart';

class PointDetailSheet extends StatefulWidget {
  final DiscoveryPoint point;
  final LatLng? userLocation;
  final VoidCallback onLiked;
  final VoidCallback? onNavigate;

  const PointDetailSheet({
    super.key,
    required this.point,
    this.userLocation,
    required this.onLiked,
    this.onNavigate,
  });

  @override
  State<PointDetailSheet> createState() => _PointDetailSheetState();
}

class _PointDetailSheetState extends State<PointDetailSheet>
    with SingleTickerProviderStateMixin {
  bool _liked = false;
  late int _likes;
  late AnimationController _heartController;
  late Animation<double> _heartScale;

  bool _isLoadingVisits = true;
  int _visitorCount = 0;
  double _averageRating = 0.0;
  bool _canCheckIn = false;
  bool _hasVisited = false;
  int? _myRating;

  @override
  void initState() {
    super.initState();
    _likes = widget.point.likes;
    _heartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _heartScale = TweenSequence([
      TweenSequenceItem(tween: Tween<double>(begin: 1, end: 1.4), weight: 50),
      TweenSequenceItem(tween: Tween<double>(begin: 1.4, end: 1), weight: 50),
    ]).animate(CurvedAnimation(parent: _heartController, curve: Curves.easeInOut));
    _loadVisits();
  }

  Future<void> _loadVisits() async {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    
    // Yere olan uzaklığı kontrol et (10 metre kısıtı)
    if (widget.userLocation != null) {
      final dist = const Distance().as(
        LengthUnit.Meter,
        widget.userLocation!,
        LatLng(widget.point.latitude, widget.point.longitude),
      );
      _canCheckIn = dist <= 10.0;
    } else {
      _canCheckIn = false;
    }

    try {
      final res = await Supabase.instance.client
          .from('point_visits')
          .select('user_id, rating')
          .eq('point_id', widget.point.id);

      final List<dynamic> data = res as List<dynamic>;
      _visitorCount = data.length;

      if (_visitorCount > 0) {
        final total = data.fold<int>(0, (sum, item) => sum + (item['rating'] as int));
        _averageRating = total / _visitorCount;

        if (myId != null) {
          // firstWhereOrNull alternatifi
          final userVisit = data.where((item) => item['user_id'] == myId).toList();
          if (userVisit.isNotEmpty) {
            _hasVisited = true;
            _myRating = userVisit.first['rating'] as int;
          }
        }
      }
    } catch (e) {
      print('Ziyaret verisi çekme hatası: $e');
    }

    if (mounted) {
      setState(() => _isLoadingVisits = false);
    }
  }

  Future<void> _toggleLike() async {
    if (_liked) return;
    setState(() {
      _liked = true;
      _likes++;
    });
    _heartController.forward(from: 0);
    await DatabaseService().likePoint(widget.point.id);
    widget.onLiked();
  }

  void _showRatingDialog() {
    int selectedRating = 5;
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.card,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text(
                'Gittim & Puan Ver',
                style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Bu mekanı ziyaretinizi kaydedin ve puan verin:',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final starVal = index + 1;
                      return IconButton(
                        icon: Icon(
                          starVal <= selectedRating ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                          size: 36,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            selectedRating = starVal;
                          });
                        },
                      );
                    }),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('İptal', style: TextStyle(color: AppColors.textSecondary)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _submitVisit(selectedRating);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  child: const Text('Gönder'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _submitVisit(int rating) async {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (myId == null) return;

    setState(() => _isLoadingVisits = true);
    try {
      await Supabase.instance.client.from('point_visits').upsert({
        'user_id': myId,
        'point_id': widget.point.id,
        'rating': rating,
      });
      await _loadVisits();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 Ziyaretiniz kaydedildi! (Puan: $rating)'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      print('Ziyaret kaydetme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ziyaret kaydedilirken bir hata oluştu.'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      setState(() => _isLoadingVisits = false);
    }
  }

  Future<void> _sendFriendRequestFromDetail() async {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (myId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Arkadaş eklemek için giriş yapmalısınız.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final nickname = widget.point.addedByNickname;
    if (nickname == null) return;

    try {
      final profileRes = await Supabase.instance.client
          .from('profiles')
          .select('id')
          .eq('nickname', nickname)
          .maybeSingle();

      if (profileRes == null) return;
      final friendId = profileRes['id'] as String;

      if (friendId == myId) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Kendinizi arkadaş olarak ekleyemezsiniz.'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      if (!mounted) return;

      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Arkadaş Ekle', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
          content: Text('@$nickname kullanıcısına arkadaşlık isteği göndermek istiyor musunuz?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal', style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('İstek Gönder'),
            ),
          ],
        ),
      );

      if (confirm == true) {
        final success = await ChatService().sendFriendRequest(friendId);
        if (mounted) {
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('🎉 @$nickname kullanıcısına arkadaşlık isteği gönderildi!'),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Arkadaşlık isteği gönderilemedi (Zaten istek gönderilmiş olabilir).'),
                backgroundColor: AppColors.error,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    } catch (e) {
      print('Arkadaş ekleme hatası: $e');
    }
  }

  String? _getDistance() {
    if (widget.userLocation == null) return null;
    final dist = const Distance().as(
      LengthUnit.Meter,
      widget.userLocation!,
      LatLng(widget.point.latitude, widget.point.longitude),
    );
    if (dist < 1000) return '${dist.toStringAsFixed(0)} m';
    return '${(dist / 1000).toStringAsFixed(1)} km';
  }

  Widget _buildCheckInSection() {
    final isLoggedIn = Supabase.instance.client.auth.currentSession != null;

    if (!isLoggedIn) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: const Center(
          child: Text(
            '🔒 Gittim işaretlemek için giriş yapın',
            style: TextStyle(color: AppColors.textHint, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      );
    }

    if (_hasVisited) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 18),
            const SizedBox(width: 8),
            Text(
              'Burayı ziyaret ettin (Puanın: ⭐ $_myRating)',
              style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _canCheckIn ? _showRatingDialog : null,
            icon: Icon(
              Icons.check_box_outlined,
              color: _canCheckIn ? Colors.white : AppColors.textHint,
            ),
            label: const Text('Gittim & Puan Ver'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _canCheckIn ? Colors.teal : AppColors.border,
              disabledBackgroundColor: AppColors.border,
            ),
          ),
        ),
        if (!_canCheckIn) ...[
          const SizedBox(height: 4),
          const Center(
            child: Text(
              '🔒 Gittim işaretlemek için yerin 10 metre yakınında olmalısınız.',
              style: TextStyle(color: AppColors.error, fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    _heartController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(widget.point.category.colorValue);
    final distance = _getDistance();

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.point.imagePath != null &&
              widget.point.imagePath!.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: Image.file(
                File(widget.point.imagePath!),
                width: double.infinity,
                height: 180,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: color.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(widget.point.category.emoji,
                              style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 6),
                          Text(
                            widget.point.category.labelTR,
                            style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w600,
                                fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    if (distance != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.near_me,
                                size: 12, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Text(distance,
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                    if (widget.point.isPetFriendly) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('🐾', style: TextStyle(fontSize: 12)),
                            SizedBox(width: 4),
                            Text(
                              'Hayvan Dostu',
                              style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (widget.point.isSponsored) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFFFD700)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('👑', style: TextStyle(fontSize: 12)),
                            SizedBox(width: 4),
                            Text(
                              'Sponsorlu',
                              style: TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),

                // Sponsorlu İndirim Kartı (Eğer indirim kodu tanımlıysa)
                if (widget.point.discountCode != null &&
                    widget.point.discountCode!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2A2111), Color(0xFF1E170A)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.6)),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                          blurRadius: 12,
                          spreadRadius: 1,
                        )
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.local_offer, color: Color(0xFFFFD700), size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.point.discountNote ?? 'Özel Müşteri İndirimi',
                                style: const TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF141008),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.4)),
                              ),
                              child: Text(
                                widget.point.discountCode!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            const Spacer(),
                            ElevatedButton.icon(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: widget.point.discountCode!));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('✂️ İndirim kodu panoya kopyalandı!'),
                                    backgroundColor: Colors.teal,
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy, size: 16),
                              label: const Text('Kopyala'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFFD700),
                                foregroundColor: Colors.black,
                                textStyle: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  widget.point.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (widget.point.addedByNickname != null) ...[
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: _sendFriendRequestFromDetail,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.person_add_alt_1_rounded,
                              color: AppColors.primary, size: 15),
                          const SizedBox(width: 6),
                          Text(
                            'Ekleyen: @${widget.point.addedByNickname} (Ekle)',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (widget.point.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.point.description,
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 15,
                        height: 1.5),
                  ),
                ],
                
                // Ortalama Puan & Ziyaretçi Sayısı
                if (!_isLoadingVisits) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            const Text(
                              'Ortalama Puan',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.star, color: Colors.amber, size: 20),
                                const SizedBox(width: 4),
                                Text(
                                  _visitorCount > 0 ? _averageRating.toStringAsFixed(1) : 'Puan yok',
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: AppColors.divider,
                        ),
                        Column(
                          children: [
                            const Text(
                              'Ziyaretçi Sayısı',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.people, color: AppColors.primary, size: 20),
                                const SizedBox(width: 4),
                                Text(
                                  '$_visitorCount kişi',
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildCheckInSection(),
                ],

                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.location_on,
                        color: AppColors.textHint, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${widget.point.latitude.toStringAsFixed(4)}, ${widget.point.longitude.toStringAsFixed(4)}',
                      style: const TextStyle(
                          color: AppColors.textHint, fontSize: 12),
                    ),
                    const Spacer(),
                    const Icon(Icons.calendar_today,
                        color: AppColors.textHint, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${widget.point.createdAt.day}.${widget.point.createdAt.month}.${widget.point.createdAt.year}',
                      style: const TextStyle(
                          color: AppColors.textHint, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(color: AppColors.divider),
                const SizedBox(height: 16),
                Row(
                  children: [
                    // Beğen butonu
                    Expanded(
                      child: GestureDetector(
                        onTap: _toggleLike,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _liked
                                ? AppColors.primary.withValues(alpha: 0.15)
                                : AppColors.card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _liked
                                  ? AppColors.primary
                                  : AppColors.border,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ScaleTransition(
                                scale: _heartScale,
                                child: Icon(
                                  _liked
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: _liked
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$_likes beğeni',
                                style: TextStyle(
                                  color: _liked
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                  fontWeight: _liked
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Buraya Git butonu
                    if (widget.onNavigate != null) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            widget.onNavigate!();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF2196F3), Color(0xFF1565C0)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF2196F3)
                                      .withValues(alpha: 0.35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.navigation_rounded,
                                    color: Colors.white, size: 20),
                                SizedBox(width: 6),
                                Text(
                                  'Buraya Git',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
