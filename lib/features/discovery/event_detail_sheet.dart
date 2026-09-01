import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/theme.dart';
import '../../services/events_service.dart';
import '../../shared/models/models.dart';
import '../../app/main_shell.dart';

class EventDetailSheet extends StatelessWidget {
  final EventModel event;
  final LatLng? userLocation;

  const EventDetailSheet({
    super.key,
    required this.event,
    this.userLocation,
  });

  @override
  Widget build(BuildContext context) {
    final style = EventsService.getCategoryStyle(event.category);
    final color = Color(style['color'] as int);
    final icon = style['icon'] as String;
    final label = style['label'] as String;

    String dateStr = '';
    try {
      dateStr = DateFormat('d MMMM yyyy, EEEE HH:mm', 'tr').format(event.startDate.toLocal());
    } catch (_) {
      dateStr = DateFormat('d MMMM, HH:mm').format(event.startDate.toLocal());
    }

    String? distanceStr;
    if (userLocation != null && event.latitude != null && event.longitude != null) {
      final double dist = const Distance().as(
        LengthUnit.Meter,
        userLocation!,
        LatLng(event.latitude!, event.longitude!),
      );
      if (dist >= 1000) {
        distanceStr = '${(dist / 1000).toStringAsFixed(1)} km uzaklıkta';
      } else {
        distanceStr = '${dist.toStringAsFixed(0)} m uzaklıkta';
      }
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Üst Kapatma Çubuğu
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Görsel Alanı
                  if (event.imageUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        event.imageUrl!,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _eventImagePlaceholder(color, icon),
                      ),
                    )
                  else
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _eventImagePlaceholder(color, icon),
                    ),

                  const SizedBox(height: 20),

                  // Rozetler (Kategori & Ücretsiz)
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
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.3)),
                        ),
                        child: const Text(
                          'ÜCRETSİZ GİRİŞ',
                          style: TextStyle(
                            color: Color(0xFF4CAF50),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Başlık
                  Text(
                    event.title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      height: 1.3,
                    ),
                  ),

                  const SizedBox(height: 20),
                  const Divider(color: AppColors.border),
                  const SizedBox(height: 12),

                  // Detay Bilgileri (Tarih, Konum)
                  _buildDetailRow(
                    Icons.schedule_rounded,
                    'Tarih ve Saat',
                    dateStr,
                  ),

                  const SizedBox(height: 16),

                  _buildDetailRow(
                    Icons.location_on_rounded,
                    'Etkinlik Yeri',
                    event.locationName ?? event.district ?? 'Belirtilmedi',
                    subtitle: distanceStr,
                  ),

                  const SizedBox(height: 20),
                  const Divider(color: AppColors.border),
                  const SizedBox(height: 16),

                  // Açıklama
                  if (event.description != null && event.description!.isNotEmpty) ...[
                    const Text(
                      'Etkinlik Hakkında',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      event.description!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // Alt Butonlar (Harita ve Web Sayfası)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                if (event.latitude != null && event.longitude != null) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      // Haritada göster
                      final point = DiscoveryPoint(
                        id: event.id,
                        title: event.title,
                        description: event.description ?? '',
                        latitude: event.latitude!,
                        longitude: event.longitude!,
                        category: PointCategory.historical, // Tarihi yer kategorisi
                        likes: 0,
                        createdAt: DateTime.now(),
                        isUserAdded: false,
                        isPetFriendly: false,
                      );
                      MainShell.shellKey.currentState?.switchTab(0, navigateToPoint: point);
                    },
                    icon: const Icon(Icons.map_rounded),
                    label: const Text(
                      'Haritada Göster & Yol Tarifi Al',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (event.sourceUrl != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      minimumSize: const Size(double.infinity, 44),
                    ),
                    onPressed: () async {
                      final uri = Uri.tryParse(event.sourceUrl!);
                      if (uri != null) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text(
                      'Resmi Duyuru Sayfasını Gör (Dış Bağlantı)',
                      style: TextStyle(fontSize: 13, decoration: TextDecoration.underline),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String title, String value, {String? subtitle}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
          ),
          child: Icon(icon, color: AppColors.textSecondary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF4CAF50),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _eventImagePlaceholder(Color color, String icon) {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.8), color.withValues(alpha: 0.4)],
        ),
      ),
      child: Center(
        child: Text(icon, style: const TextStyle(fontSize: 56)),
      ),
    );
  }
}
