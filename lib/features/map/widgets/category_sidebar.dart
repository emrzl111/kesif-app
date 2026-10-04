import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../shared/models/models.dart';
import '../../../services/auth_service.dart';
import '../../../shared/widgets/premium_paywall_sheet.dart';
import '../map_screen.dart';

// ─────────────────────────────────────────────────────────────────
// Sağ kenar kategori sidebar'ı (dikey ikon menüsü)
// ─────────────────────────────────────────────────────────────────
class CategorySidebar extends StatelessWidget {
  final PointCategory? activeFilter;
  final bool pharmacyFilterActive;
  final bool filterOnlyPetFriendly;
  final void Function(PointCategory?) onCategorySelected;
  final VoidCallback onPharmacyToggle;
  final VoidCallback onPetToggle;
  final VoidCallback onExpandOverlay;

  const CategorySidebar({
    super.key,
    required this.activeFilter,
    required this.pharmacyFilterActive,
    required this.filterOnlyPetFriendly,
    required this.onCategorySelected,
    required this.onPharmacyToggle,
    required this.onPetToggle,
    required this.onExpandOverlay,
  });

  Widget _divider() => Container(
        width: 28,
        height: 1,
        margin: const EdgeInsets.symmetric(vertical: 2),
        color: AppColors.border.withValues(alpha: 0.6),
      );

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 80,
      right: 12,
      bottom: 120,
      child: SafeArea(
        child: Container(
          width: 50,
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.15),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(25),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 6),
                    // Grid genişlet butonu
                    Tooltip(
                      message: 'Tüm Kategoriler (Genişlet)',
                      child: GestureDetector(
                        onTap: onExpandOverlay,
                        child: Container(
                          width: 38,
                          height: 38,
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.primary, Color(0xFFB71C4B)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.5),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(Icons.grid_view_rounded,
                                color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ),
                    _divider(),
                    // Eczaneler
                    _PharmacyButton(
                      isActive: pharmacyFilterActive,
                      onTap: onPharmacyToggle,
                    ),
                    _divider(),
                    // Tümü
                    _CategoryButton(
                      category: null,
                      emoji: '🗺️',
                      label: 'Tümü',
                      isActive: activeFilter == null && !pharmacyFilterActive,
                      onTap: () => onCategorySelected(null),
                    ),
                    _divider(),
                    ...PointCategory.values.map((cat) => _CategoryButton(
                          category: cat,
                          emoji: cat.emoji,
                          label: cat.labelTR,
                          isActive: activeFilter == cat && !pharmacyFilterActive,
                          onTap: () => onCategorySelected(cat),
                        )),
                    _divider(),
                    _PetButton(
                      isActive: filterOnlyPetFriendly,
                      onTap: onPetToggle,
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryButton extends StatelessWidget {
  final PointCategory? category;
  final String emoji;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _CategoryButton({
    required this.category,
    required this.emoji,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        category != null ? Color(category!.colorValue) : AppColors.primary;
    return Tooltip(
      message: label,
      preferBelow: false,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 38,
          height: 38,
          margin: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: isActive ? color.withValues(alpha: 0.3) : Colors.transparent,
            shape: BoxShape.circle,
            border: isActive ? Border.all(color: color, width: 1.5) : null,
          ),
          child: Center(
            child: Text(emoji,
                style: TextStyle(fontSize: isActive ? 20 : 18)),
          ),
        ),
      ),
    );
  }
}

class _PharmacyButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;

  const _PharmacyButton({required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Nöbetçi Eczaneler',
      preferBelow: false,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 38,
          height: 38,
          margin: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFFE53935).withValues(alpha: 0.3)
                : Colors.transparent,
            shape: BoxShape.circle,
            border: isActive
                ? Border.all(color: const Color(0xFFE53935), width: 1.5)
                : null,
          ),
          child: const Center(child: Text('🏥', style: TextStyle(fontSize: 18))),
        ),
      ),
    );
  }
}

class _PetButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;

  const _PetButton({required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Evcil Hayvan Dostu (Premium)',
      preferBelow: false,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          margin: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary : Colors.transparent,
            shape: BoxShape.circle,
            border: isActive ? Border.all(color: Colors.white, width: 1.5) : null,
          ),
          child: const Center(child: Text('🐾', style: TextStyle(fontSize: 18))),
        ),
      ),
    );
  }
}
