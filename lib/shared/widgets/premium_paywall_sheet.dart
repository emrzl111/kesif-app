import 'dart:ui';
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../services/auth_service.dart';

class PremiumPaywallSheet extends StatefulWidget {
  const PremiumPaywallSheet({super.key});

  @override
  State<PremiumPaywallSheet> createState() => _PremiumPaywallSheetState();
}

class _PremiumPaywallSheetState extends State<PremiumPaywallSheet> {
  int _selectedPlanIndex = 1; // 1 = Yıllık (varsayılan)

  final List<Map<String, String>> _plans = [
    {
      'title': 'Aylık Plan',
      'price': '1 Ay Ücretsiz',
      'period': 'Sonra 39.99 TL/ay',
      'saving': '30 Gün Deneme',
    },
    {
      'title': 'Yıllık Plan',
      'price': '289.99 TL',
      'period': '/ yıl',
      'saving': '%40 Tasarruf',
    }
  ];

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF151528).withValues(alpha: 0.92),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.fromBorderSide(
            BorderSide(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1.5,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 40,
              spreadRadius: 10,
            )
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Top Bar Indicator
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 28),

            // Premium Crown Icon
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFFFD700),
                    const Color(0xFFFF8C00),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF8C00).withValues(alpha: 0.45),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Text(
                '👑',
                style: TextStyle(fontSize: 48),
              ),
            ),
            const SizedBox(height: 20),

            // Header Text
            const Text(
              'Keşif Premium\'a Geç',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Keşif sınırlarını kaldırın, yeni yerleri ilk siz keşfedin.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),

             Column(
               children: [
                 _benefitRow('🌟', 'Sınırsız Arama & Filtreleme', '1 km arama sınırını kaldırın, tüm noktaları görüntüleyin'),
                 const SizedBox(height: 14),
                 _benefitRow('🛰️', 'Uydu Harita Görünümü', 'Gerçek zamanlı yüksek çözünürlüklü uydu haritasını aktif edin'),
                 const SizedBox(height: 14),
                 _benefitRow('🐾', 'Pati Dostu Mekanlar', 'Sadece evcil hayvan kabul eden kafeleri ve parkları listeleyin'),
                 const SizedBox(height: 14),
                 _benefitRow('🚫', 'Reklamsız Harita', 'Tamamen kesintisiz, hızlı ve reklamsız deneyim'),
               ],
             ),
            const SizedBox(height: 32),

            // Pricing Plans
            Row(
              children: List.generate(2, (index) {
                final isSelected = _selectedPlanIndex == index;
                final plan = _plans[index];
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedPlanIndex = index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: EdgeInsets.only(
                        left: index == 1 ? 8 : 0,
                        right: index == 0 ? 8 : 0,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF221F45)
                            : const Color(0xFF1C1A35),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFFFFD700)
                              : Colors.white.withValues(alpha: 0.08),
                          width: isSelected ? 2 : 1,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                                  blurRadius: 10,
                                )
                              ]
                            : [],
                      ),
                      child: Column(
                        children: [
                          if (plan['saving']!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF8C00),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                plan['saving']!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          Text(
                            plan['title']!,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            plan['price']!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            plan['period']!,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 32),

            // Purchase Button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFFFD700),
                      const Color(0xFFFF8C00),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF8C00).withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: () {
                    // Mock premium aktivasyonu
                    AuthService.isPremiumMock = true;
                    Navigator.pop(context, true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    _selectedPlanIndex == 0
                        ? '30 Günlük Ücretsiz Denemeyi Başlat'
                        : 'Premium Üye Ol (Mock)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Close Button
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Belki Daha Sonra',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _benefitRow(String emoji, String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              emoji,
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
