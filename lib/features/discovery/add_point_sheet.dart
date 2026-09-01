import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../app/theme.dart';
import '../../services/database_service.dart';
import '../../shared/models/models.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class AddPointSheet extends StatefulWidget {
  final double latitude;
  final double longitude;
  final VoidCallback onSaved;

  const AddPointSheet({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.onSaved,
  });

  @override
  State<AddPointSheet> createState() => _AddPointSheetState();
}

class _AddPointSheetState extends State<AddPointSheet> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  PointCategory _selectedCategory = PointCategory.cafe;
  bool _isSaving = false;
  bool _isPetFriendly = false;
  File? _photo;
  final _uuid = const Uuid();
  final _picker = ImagePicker();

  Future<void> _pickPhoto() async {
    try {
      final xFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1200,
      );
      if (xFile != null) {
        setState(() => _photo = File(xFile.path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kamera açılamadı: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }



  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen bir başlık girin')),
      );
      return;
    }
    if (_photo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📸 Fotoğraf çekmek zorunlu!'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final imagePath = _photo?.path;
      final point = DiscoveryPoint(
        id: _uuid.v4(),
        title: _titleController.text.trim(),
        description: _descController.text.trim(),
        latitude: widget.latitude,
        longitude: widget.longitude,
        category: _selectedCategory,
        imagePath: imagePath,
        createdAt: DateTime.now(),
        isUserAdded: true,
        isPetFriendly: _isPetFriendly,
      );
      await DatabaseService().insertPoint(point);
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ekleme başarısız oldu: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.only(
        top: 24,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                const Icon(Icons.add_location, color: AppColors.primary, size: 24),
                const SizedBox(width: 12),
                const Text(
                  'Yeni Keşif Noktası',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.latitude.toStringAsFixed(5)}, ${widget.longitude.toStringAsFixed(5)}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 20),

            // --- FOTOĞRAF ---
            const Text(
              'Fotoğraf *',
              style: TextStyle(
                  color: AppColors.textSecondary, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _pickPhoto,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                height: 160,
                decoration: BoxDecoration(
                  color: _photo != null
                      ? Colors.transparent
                      : AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _photo != null
                        ? AppColors.primary
                        : AppColors.border,
                    width: _photo != null ? 2 : 1,
                  ),
                ),
                child: _photo != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(_photo!, fit: BoxFit.cover),
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: GestureDetector(
                                onTap: _pickPhoto,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.camera_alt,
                                          color: Colors.white, size: 14),
                                      SizedBox(width: 4),
                                      Text('Yeniden Çek',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color:
                                  AppColors.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt_rounded,
                                color: AppColors.primary, size: 28),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Fotoğraf Çek',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Pin eklemek için fotoğraf zorunludur',
                            style: TextStyle(
                                color: AppColors.textHint, fontSize: 12),
                          ),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(labelText: 'Başlık *'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Açıklama',
                hintText: 'Bu yeri açıkla, özel bir şey var mı?',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            const Text(
              'Kategori',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: PointCategory.values.map((cat) {
                final isSelected = cat == _selectedCategory;
                final color = Color(cat.colorValue);
                return GestureDetector(
                  onTap: () => setState(() => _selectedCategory = cat),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.withValues(alpha: 0.2)
                          : AppColors.card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? color : AppColors.border,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(cat.emoji,
                            style: const TextStyle(fontSize: 15)),
                        const SizedBox(width: 6),
                        Text(
                          cat.labelTR,
                          style: TextStyle(
                            color: isSelected
                                ? color
                                : AppColors.textSecondary,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
             }).toList(),
            ),
            if (_selectedCategory == PointCategory.cafe ||
                _selectedCategory == PointCategory.restaurant) ...[
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: SwitchListTile(
                  title: const Row(
                    children: [
                      Text('🐾', style: TextStyle(fontSize: 18)),
                      SizedBox(width: 8),
                      Text(
                        'Hayvan Dostu Mekan mı?',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  subtitle: const Text(
                    'Evcil hayvanlara izin veriliyor mu?',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  value: _isPetFriendly,
                  activeColor: AppColors.primary,
                  onChanged: (val) => setState(() => _isPetFriendly = val),
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _photo == null
                      ? AppColors.textHint
                      : AppColors.primary,
                  disabledBackgroundColor: AppColors.textHint,
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _photo == null
                                ? Icons.camera_alt
                                : Icons.check_circle,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(_photo == null
                              ? 'Önce Fotoğraf Çek'
                              : 'Keşif Noktası Ekle'),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
