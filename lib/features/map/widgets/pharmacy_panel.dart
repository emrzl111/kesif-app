import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../shared/models/models.dart';
import '../../pharmacy/pharmacy_screen.dart' show Pharmacy;

/// Eczane listesi yan paneli (sol taraf).
/// [onClose] ile kapatılır, [onPharmacyNavTap] ile eczaneye navigasyon başlar.
class PharmacyListPanel extends StatelessWidget {
  final List<Pharmacy> pharmacies;
  final DiscoveryPoint? navigationTarget;
  final VoidCallback onClose;
  final void Function(Pharmacy) onPharmacyTap;
  final void Function(Pharmacy) onPharmacyNavTap;
  final bool Function(String) isOnDuty;

  const PharmacyListPanel({
    super.key,
    required this.pharmacies,
    required this.navigationTarget,
    required this.onClose,
    required this.onPharmacyTap,
    required this.onPharmacyNavTap,
    required this.isOnDuty,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      top: 80,
      bottom: 95,
      width: 250,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(4, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Başlık
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: const Color(0xFFE53935).withValues(alpha: 0.1),
                child: Row(
                  children: [
                    const Icon(Icons.local_hospital_rounded,
                        color: Color(0xFFE53935), size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Nöbetçi Eczaneler',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: onClose,
                      child: const Icon(Icons.close,
                          color: AppColors.textSecondary, size: 18),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              // Liste
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: pharmacies.length,
                  itemBuilder: (context, index) {
                    final ph = pharmacies[index];
                    final isTarget = navigationTarget?.title == ph.name;
                    return _PharmacyListItem(
                      pharmacy: ph,
                      isTarget: isTarget,
                      onTap: () => onPharmacyTap(ph),
                      onNavTap: () => onPharmacyNavTap(ph),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PharmacyListItem extends StatelessWidget {
  final Pharmacy pharmacy;
  final bool isTarget;
  final VoidCallback onTap;
  final VoidCallback onNavTap;

  const _PharmacyListItem({
    required this.pharmacy,
    required this.isTarget,
    required this.onTap,
    required this.onNavTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isTarget
            ? const Color(0xFFE53935).withValues(alpha: 0.08)
            : AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isTarget ? const Color(0xFFE53935) : AppColors.border,
        ),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        title: Text(
          pharmacy.name,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              pharmacy.address ?? 'Adres yok',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ),
        trailing: GestureDetector(
          onTap: onNavTap,
          child: const CircleAvatar(
            radius: 16,
            backgroundColor: Color(0xFFE53935),
            child: Icon(Icons.navigation_rounded,
                color: Colors.white, size: 14),
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
