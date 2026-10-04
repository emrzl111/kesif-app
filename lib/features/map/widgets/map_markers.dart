import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../app/theme.dart';
import '../../../shared/models/models.dart';

// ─────────────────────────────────────────────
// Keşif noktası pin marker'ı — konuşma balonu stili
// ─────────────────────────────────────────────
class PointMarker extends StatelessWidget {
  final DiscoveryPoint point;
  final DiscoveryPoint? navigationTarget;
  final Map<String, List<int>> pointRatings;

  const PointMarker({
    super.key,
    required this.point,
    required this.navigationTarget,
    required this.pointRatings,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(point.category.colorValue);
    final isTarget = navigationTarget?.id == point.id;
    final isSponsored = point.isSponsored;

    final ratings = pointRatings[point.id] ?? [];
    final visitorCount = ratings.length;
    final avgRating =
        visitorCount > 0 ? ratings.reduce((a, b) => a + b) / visitorCount : 0.0;
    final isHotspot = avgRating >= 4.5 || visitorCount >= 3;

    final pinColor = isSponsored
        ? const Color(0xFFFFD700)
        : (isTarget ? const Color(0xFF2196F3) : color);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Balon gövdesi ──────────────────────
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: isSponsored ? 52 : 48,
              height: isSponsored ? 48 : 44,
              decoration: BoxDecoration(
                gradient: isSponsored
                    ? const LinearGradient(
                        colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : LinearGradient(
                        colors: [
                          pinColor,
                          Color.lerp(pinColor, Colors.black, 0.28)!,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isHotspot
                      ? const Color(0xFFFFD700)
                      : Colors.white.withValues(alpha: 0.85),
                  width: isHotspot ? 2.5 : 2.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: pinColor.withValues(alpha: isHotspot ? 0.9 : 0.65),
                    blurRadius: isHotspot ? 22 : 14,
                    spreadRadius: isHotspot ? 4 : 2,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  point.category.emoji,
                  style: TextStyle(fontSize: isSponsored ? 24 : 20),
                ),
              ),
            ),
            // 👑 Sponsor rozeti
            if (isSponsored)
              Positioned(
                top: -7,
                right: -5,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1A1A2E),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Color(0xFFFFD700), blurRadius: 6),
                    ],
                  ),
                  child: const Text('👑', style: TextStyle(fontSize: 11)),
                ),
              ),
            // 🔥 Hotspot rozeti
            if (isHotspot && !isSponsored)
              Positioned(
                top: -7,
                right: -5,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF6D00).withValues(alpha: 0.8),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: const Text('🔥', style: TextStyle(fontSize: 10)),
                ),
              ),
          ],
        ),
        // ── Üçgen uç ───────────────────────────
        CustomPaint(
          size: const Size(14, 9),
          painter: _BubbleTailPainter(pinColor: pinColor),
        ),
      ],
    );
  }
}

/// Konuşma balonu üçgen kuyruk boyayıcısı
class _BubbleTailPainter extends CustomPainter {
  final Color pinColor;
  const _BubbleTailPainter({required this.pinColor});

  @override
  void paint(Canvas canvas, Size size) {
    // Dolu üçgen (gövdeyle aynı renk, biraz koyulaştırılmış)
    final fill = Paint()
      ..color = Color.lerp(pinColor, Colors.black, 0.22)!
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, fill);

    // Yan kenar için hafif beyaz çizgi (3B efekti)
    final stroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.round;
    final border = Path()
      ..moveTo(1.5, 0)
      ..lineTo(size.width / 2, size.height - 1.5)
      ..lineTo(size.width - 1.5, 0);
    canvas.drawPath(border, stroke);
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter old) =>
      old.pinColor != pinColor;
}

// ─────────────────────────────────────────────
// Navigasyon hedef marker'ı (bayrak)
// ─────────────────────────────────────────────
class NavTargetMarker extends StatelessWidget {
  const NavTargetMarker({super.key});

  @override
  Widget build(BuildContext context) {
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
}

// ─────────────────────────────────────────────
// Kullanıcı konumu pulsing marker
// ─────────────────────────────────────────────
class UserLocationMarker extends StatelessWidget {
  final Animation<double> pulseAnimation;

  const UserLocationMarker({super.key, required this.pulseAnimation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (ctx, child) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 50 * pulseAnimation.value,
            height: 50 * pulseAnimation.value,
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
}

// ─────────────────────────────────────────────
// Sağ alt harita kontrol butonları (FAB grubu)
// ─────────────────────────────────────────────
class MapControlButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const MapControlButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
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
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Navigasyon bilgi bandı (alt, aktif rotada gösterilir)
// ─────────────────────────────────────────────
class NavigationBanner extends StatelessWidget {
  final String targetTitle;
  final VoidCallback onClose;

  const NavigationBanner({
    super.key,
    required this.targetTitle,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
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
                    targetTitle,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: onClose,
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
}

// ─────────────────────────────────────────────
// Rota yükleniyor göstergesi
// ─────────────────────────────────────────────
class RouteLoadingIndicator extends StatelessWidget {
  const RouteLoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
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
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Konum alınıyor yükleme ekranı
// ─────────────────────────────────────────────
class MapLoadingOverlay extends StatelessWidget {
  const MapLoadingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
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
