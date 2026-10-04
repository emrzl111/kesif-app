import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../shared/models/models.dart';
import '../../../services/auth_service.dart';
import '../../../shared/widgets/premium_paywall_sheet.dart';

/// Tam ekran glassmorphic kategori seçim paneli.
/// [showCategoryOverlay] çağrısıyla açılır.
void showCategoryOverlay(
  BuildContext context, {
  required PointCategory? activeFilter,
  required bool pharmacyFilterActive,
  required bool filterOnlyPetFriendly,
  required int allPointsCount,
  required int pharmaciesCount,
  required Map<PointCategory, int> categoryPointCounts,
  required void Function(PointCategory?) onCategorySelected,
  required VoidCallback onPharmacyToggle,
  required void Function(bool) onPetToggle,
}) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'CategoryOverlay',
    barrierColor: Colors.black.withValues(alpha: 0.5),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (ctx, anim1, anim2) {
      return _CategoryOverlayPage(
        activeFilter: activeFilter,
        pharmacyFilterActive: pharmacyFilterActive,
        filterOnlyPetFriendly: filterOnlyPetFriendly,
        allPointsCount: allPointsCount,
        pharmaciesCount: pharmaciesCount,
        categoryPointCounts: categoryPointCounts,
        onCategorySelected: onCategorySelected,
        onPharmacyToggle: onPharmacyToggle,
        onPetToggle: onPetToggle,
      );
    },
    transitionBuilder: (ctx, anim1, anim2, child) {
      return FadeTransition(
        opacity: anim1,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1.0).animate(
            CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      );
    },
  );
}

class _CategoryOverlayPage extends StatefulWidget {
  final PointCategory? activeFilter;
  final bool pharmacyFilterActive;
  final bool filterOnlyPetFriendly;
  final int allPointsCount;
  final int pharmaciesCount;
  final Map<PointCategory, int> categoryPointCounts;
  final void Function(PointCategory?) onCategorySelected;
  final VoidCallback onPharmacyToggle;
  final void Function(bool) onPetToggle;

  const _CategoryOverlayPage({
    required this.activeFilter,
    required this.pharmacyFilterActive,
    required this.filterOnlyPetFriendly,
    required this.allPointsCount,
    required this.pharmaciesCount,
    required this.categoryPointCounts,
    required this.onCategorySelected,
    required this.onPharmacyToggle,
    required this.onPetToggle,
  });

  @override
  State<_CategoryOverlayPage> createState() => _CategoryOverlayPageState();
}

class _CategoryOverlayPageState extends State<_CategoryOverlayPage> {
  late PointCategory? _activeFilter;
  late bool _pharmacyFilterActive;
  late bool _filterOnlyPetFriendly;

  @override
  void initState() {
    super.initState();
    _activeFilter = widget.activeFilter;
    _pharmacyFilterActive = widget.pharmacyFilterActive;
    _filterOnlyPetFriendly = widget.filterOnlyPetFriendly;
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ColorFilter.mode(
        Colors.black.withValues(alpha: 0.0),
        BlendMode.multiply,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background.withValues(alpha: 0.8),
        body: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.4)),
                      ),
                      child: const Icon(Icons.explore_rounded,
                          color: AppColors.primary, size: 24),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Kategorileri Keşfet',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Haritada filtrelemek istediğiniz mekan kategorisini seçin',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated.withValues(alpha: 0.8),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 22),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 12),

              // Grid
              Expanded(
                child: GridView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  physics: const BouncingScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1.45,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  children: [
                    _GlassCategoryCard(
                      title: 'Tüm Noktalar',
                      subtitle: '${widget.allPointsCount} mekan',
                      emoji: '🗺️',
                      accentColor: AppColors.primary,
                      isSelected:
                          _activeFilter == null && !_pharmacyFilterActive,
                      onTap: () {
                        setState(() {
                          _activeFilter = null;
                          _pharmacyFilterActive = false;
                          _filterOnlyPetFriendly = false;
                        });
                        widget.onCategorySelected(null);
                        Navigator.pop(context);
                      },
                    ),
                    _GlassCategoryCard(
                      title: 'Nöbetçi Eczaneler',
                      subtitle: '${widget.pharmaciesCount} eczane',
                      emoji: '🏥',
                      accentColor: const Color(0xFFE53935),
                      isSelected: _pharmacyFilterActive,
                      onTap: () {
                        setState(() {
                          _pharmacyFilterActive = !_pharmacyFilterActive;
                          _activeFilter = null;
                        });
                        widget.onPharmacyToggle();
                        Navigator.pop(context);
                      },
                    ),
                    ...PointCategory.values.map((cat) {
                      final catColor = Color(cat.colorValue);
                      final isCatSelected =
                          _activeFilter == cat && !_pharmacyFilterActive;
                      final count = widget.categoryPointCounts[cat] ?? 0;
                      return _GlassCategoryCard(
                        title: cat.labelTR,
                        subtitle: '$count mekan',
                        emoji: cat.emoji,
                        accentColor: catColor,
                        isSelected: isCatSelected,
                        onTap: () {
                          setState(() {
                            _activeFilter = cat;
                            _pharmacyFilterActive = false;
                          });
                          widget.onCategorySelected(cat);
                          Navigator.pop(context);
                        },
                      );
                    }),
                    _GlassCategoryCard(
                      title: 'Evcil Hayvan Dostu',
                      subtitle: 'Premium Filtre',
                      emoji: '🐾',
                      accentColor: const Color(0xFFFFB347),
                      isSelected: _filterOnlyPetFriendly,
                      onTap: () {
                        Navigator.pop(context);
                        if (!AuthService.isPremiumMock) {
                          showModalBottomSheet<bool>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => const PremiumPaywallSheet(),
                          );
                        } else {
                          widget.onPetToggle(!_filterOnlyPetFriendly);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassCategoryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String emoji;
  final Color accentColor;
  final bool isSelected;
  final VoidCallback onTap;

  const _GlassCategoryCard({
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.accentColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withValues(alpha: 0.25)
              : AppColors.card.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? accentColor
                : AppColors.border.withValues(alpha: 0.6),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: accentColor.withValues(alpha: 0.35),
                blurRadius: 14,
                spreadRadius: 1,
              )
            else
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 32)),
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.check, color: Colors.white, size: 12),
                  ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
