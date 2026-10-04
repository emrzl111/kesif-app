import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../services/weather_service.dart';

class WeatherCardWidget extends StatefulWidget {
  final WeatherData weather;
  final String locationText;

  const WeatherCardWidget({
    super.key,
    required this.weather,
    required this.locationText,
  });

  @override
  State<WeatherCardWidget> createState() => _WeatherCardWidgetState();
}

class _WeatherCardWidgetState extends State<WeatherCardWidget> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
      child: _isExpanded ? _buildExpandedCard() : _buildCompactPill(),
    );
  }

  // ─── KAPALI (KOMPAKT) HALİ ───
  Widget _buildCompactPill() {
    return GestureDetector(
      onTap: () => setState(() => _isExpanded = true),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF131524).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF332948), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Hava durumu ikonu
            _buildWeatherIcon(size: 20),
            const SizedBox(width: 8),
            // Sıcaklık
            Text(
              '${widget.weather.temperature.round()}°C',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            // Dikey çizgi ayırıcı
            Container(
              width: 1,
              height: 16,
              color: Colors.white.withValues(alpha: 0.25),
            ),
            const SizedBox(width: 8),
            // Konum
            Text(
              widget.locationText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            // Aşağı ok
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppColors.textSecondary,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  // ─── AÇIK (DETAYLI) KART HALİ ───
  Widget _buildExpandedCard() {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131524).withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF3D2D56), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE91E63).withValues(alpha: 0.15),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Üst Kısım: İkon + Sıcaklık/Durum + Kapatma Oku ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // İkon kutucuğu
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB300).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFFFB300).withValues(alpha: 0.5),
                    width: 1.2,
                  ),
                ),
                child: Center(
                  child: _buildWeatherIcon(size: 26),
                ),
              ),
              const SizedBox(width: 12),
              // Derece ve Parçalı Bulutlu
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${widget.weather.temperature.round()}°C',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '(Hissedilen ${widget.weather.apparentTemperature.round()}°C)',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.weather.conditionText,
                      style: const TextStyle(
                        color: Color(0xFFF06292), // Canlı pembe
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // Kapatma butonu (Yukarı ok)
              GestureDetector(
                onTap: () => setState(() => _isExpanded = false),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.keyboard_arrow_up_rounded,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── Konum & Günbatımı Satırı ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.location_on_rounded,
                    color: Color(0xFFFF5252),
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.locationText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Text(
                'Günbatımı ${widget.weather.sunsetTime}',
                style: const TextStyle(
                  color: Color(0xFFFFB74D), // Altın sarısı
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ── Nem ve Rüzgar Rozetleri ──
          Row(
            children: [
              // Nem
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2038),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.water_drop_outlined, color: Color(0xFF64B5F6), size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'Nem: ',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '%${widget.weather.humidity}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Rüzgar
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2038),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.air_rounded, color: Color(0xFF4DD0E1), size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'Rüzgar: ',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '${widget.weather.windSpeed.round()} km/s',
                        style: const TextStyle(
                          color: Colors.white,
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

          // ── Alt Tavsiye Kutucuğu ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF241634),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFE91E63).withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0xFFF06292),
                  size: 15,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.weather.recommendation,
                    style: const TextStyle(
                      color: Color(0xFFEDE7F6),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherIcon({required double size}) {
    final code = widget.weather.weatherCode;
    if (code == 0) {
      return Icon(Icons.wb_sunny_rounded, color: const Color(0xFFFFB300), size: size);
    } else if (code <= 3) {
      return Icon(Icons.wb_cloudy_rounded, color: const Color(0xFFFFB300), size: size);
    } else if ((code >= 71 && code <= 77) || code == 85 || code == 86) {
      return Icon(Icons.ac_unit_rounded, color: const Color(0xFF81D4FA), size: size);
    } else if (code >= 51 && code <= 82) {
      return Icon(Icons.grain_rounded, color: const Color(0xFF64B5F6), size: size);
    } else if (code >= 95) {
      return Icon(Icons.flash_on_rounded, color: const Color(0xFFFFD54F), size: size);
    }
    return Icon(Icons.cloud_outlined, color: const Color(0xFFFFB300), size: size);
  }
}
