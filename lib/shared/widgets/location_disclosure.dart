import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/theme.dart';

/// Google Play "Belirgin Açıklama ve Rıza" (Prominent Disclosure) şartı için
/// konum izni istenmeden ÖNCE gösterilen açıklama.
///
/// Kural: Sistem konum izni penceresi, kullanıcı bu açıklamayı görüp
/// "Kabul Et" demeden asla açılmamalıdır.
class LocationDisclosure {
  static const String prefsKey = 'location_disclosure_accepted';

  static const String title = 'Konum Verilerinin Kullanımı';

  static const String body =
      'Keşif, aşağıdaki özellikleri sağlamak için cihazınızın konum verilerini '
      '(hassas ve yaklaşık konum) toplar ve kullanır:';

  static const List<String> usages = [
    '📍 Yakınınızdaki mekanları, etkinlikleri ve nöbetçi eczaneleri haritada göstermek',
    '🏙️ Bulunduğunuz şehir ve ilçeyi tespit ederek içerikleri kişiselleştirmek',
    '✅ Ziyaret ettiğiniz mekanlarda check-in yapabilmenizi sağlamak',
    '🧭 Rota kaydını başlattığınızda yürüyüş rotanızı ve mesafenizi kaydetmek '
        '(kayıt sırasında bildirim çubuğunda görünür bir bildirim bulunur ve '
        'kaydı durdurduğunuzda konum takibi sona erer)',
  ];

  static const String footer =
      'Konum verileriniz yalnızca bu özellikler için kullanılır; reklam amacıyla '
      'kullanılmaz ve üçüncü taraf reklam verenlerle paylaşılmaz. İzni dilediğiniz '
      'zaman cihaz ayarlarından geri alabilirsiniz.';

  static Future<bool> isAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefsKey) ?? false;
  }

  static Future<void> setAccepted(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKey, value);
  }

  /// Daha önce kabul edildiyse true döner; aksi halde açıklamayı gösterir.
  static Future<bool> ensureAccepted(BuildContext context) async {
    if (await isAccepted()) return true;
    if (!context.mounted) return false;
    final accepted = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          isDismissible: false,
          enableDrag: false,
          backgroundColor: AppColors.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (ctx) => const _DisclosureSheet(),
        ) ??
        false;
    await setAccepted(accepted);
    return accepted;
  }
}

/// Açıklama metnini gösteren yeniden kullanılabilir içerik.
class LocationDisclosureContent extends StatelessWidget {
  const LocationDisclosureContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          LocationDisclosure.body,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14.5,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 12),
        ...LocationDisclosure.usages.map(
          (u) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              u,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          LocationDisclosure.footer,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12.5,
            height: 1.4,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

class _DisclosureSheet extends StatelessWidget {
  const _DisclosureSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: const [
                  Icon(Icons.location_on, color: AppColors.primary, size: 28),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      LocationDisclosure.title,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const LocationDisclosureContent(),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Kabul Et ve Devam Et',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(
                    'Hayır, teşekkürler',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
