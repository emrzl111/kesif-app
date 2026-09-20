import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../app/theme.dart';
import '../../shared/models/models.dart';

/// Instagram Story formatında (9:16) paylaşım kartı
class ShareCardWidget extends StatelessWidget {
  final DiscoveryPoint point;
  final GlobalKey repaintKey;

  const ShareCardWidget({
    super.key,
    required this.point,
    required this.repaintKey,
  });

  @override
  Widget build(BuildContext context) {
    final categoryColor = Color(point.category.colorValue);

    return RepaintBoundary(
      key: repaintKey,
      child: Container(
        width: 360,
        height: 640, // 9:16 oranı (küçültülmüş)
        decoration: const BoxDecoration(
          color: AppColors.background,
        ),
        child: Stack(
          children: [
            // Arka plan fotoğrafı
            if (point.imagePath != null)
              Positioned.fill(child: _buildPhoto()),

            // Üst + Alt karartma gradyanı
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xCC0D0D1A),
                      Colors.transparent,
                      Colors.transparent,
                      Color(0xEE0D0D1A),
                    ],
                    stops: [0.0, 0.25, 0.55, 1.0],
                  ),
                ),
              ),
            ),

            // Üst kısım: Uygulama logosu + kategori rozeti
            Positioned(
              top: 32,
              left: 24,
              right: 24,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.explore,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Keşif',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  // Kategori rozeti — model'deki emoji & labelTR kullan
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: categoryColor.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${point.category.emoji} ${point.category.labelTR}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Alt kısım: Mekan bilgileri
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // "Yeni bir yer keşfedildi!" etiketi
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '📍 Yeni bir yer keşfedildi!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Mekan adı
                    Text(
                      point.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                        shadows: [
                          Shadow(
                              color: Colors.black54,
                              blurRadius: 8,
                              offset: Offset(0, 2)),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    // Açıklama (varsa)
                    if (point.description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        point.description,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 14,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Kaşif adı + "Keşif'ten paylaşıldı"
                    Row(
                      children: [
                        if (point.addedByNickname != null) ...[
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.person,
                                color: Colors.white, size: 18),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '@${point.addedByNickname}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Keşif uygulamasından paylaşıldı',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.65),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const Spacer(),
                        Icon(
                          Icons.location_on,
                          color: AppColors.primary.withValues(alpha: 0.9),
                          size: 20,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoto() {
    final path = point.imagePath;
    if (path == null) return _placeholder();

    if (path.startsWith('http')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    } else {
      final file = File(path);
      if (file.existsSync()) {
        return Image.file(file, fit: BoxFit.cover);
      }
      return _placeholder();
    }
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.surface,
      child: const Center(
        child: Icon(Icons.image_outlined,
            color: AppColors.textHint, size: 60),
      ),
    );
  }
}

// ─── Widget'ı PNG olarak yakala ve paylaş ─────────────────────────────────────
Future<void> captureAndShare(GlobalKey repaintKey, String title) async {
  try {
    final boundary = repaintKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return;

    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;

    final Uint8List pngBytes = byteData.buffer.asUint8List();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/kesif_share.png');
    await file.writeAsBytes(pngBytes);

    await Share.shareXFiles(
      [XFile(file.path)],
      text: '📍 $title • Keşif uygulamasında keşfedildi! #Keşif',
    );
  } catch (e) {
    debugPrint('Paylaşım hatası: $e');
  }
}

// ─── Paylaş Bottom Sheet ──────────────────────────────────────────────────────
class SharePointSheet extends StatefulWidget {
  final DiscoveryPoint point;

  const SharePointSheet({super.key, required this.point});

  @override
  State<SharePointSheet> createState() => _SharePointSheetState();
}

class _SharePointSheetState extends State<SharePointSheet> {
  final GlobalKey _repaintKey = GlobalKey();
  bool _isSharing = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
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

          const Text(
            '📸 Instagram\'da Paylaş',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Bu görseli Instagram Hikayene ekleyebilirsin',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),

          // Önizleme kartı
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ShareCardWidget(
              point: widget.point,
              repaintKey: _repaintKey,
            ),
          ),
          const SizedBox(height: 20),

          // Paylaş butonu
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSharing
                  ? null
                  : () async {
                      setState(() => _isSharing = true);
                      await captureAndShare(
                          _repaintKey, widget.point.title);
                      setState(() => _isSharing = false);
                    },
              icon: _isSharing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.share_rounded, color: Colors.white),
              label: Text(
                _isSharing ? 'Hazırlanıyor...' : 'Görseli Paylaş',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 10),

          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Şimdi Değil',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
