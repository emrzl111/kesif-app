import 'dart:ui';
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../services/chat_service.dart';

class UserInfoSheet extends StatefulWidget {
  final String userId;
  final String nickname;
  final VoidCallback? onStartChat;
  final VoidCallback? onUserBlocked;

  const UserInfoSheet({
    super.key,
    required this.userId,
    required this.nickname,
    this.onStartChat,
    this.onUserBlocked,
  });

  static void show(
    BuildContext context, {
    required String userId,
    required String nickname,
    VoidCallback? onStartChat,
    VoidCallback? onUserBlocked,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UserInfoSheet(
        userId: userId,
        nickname: nickname,
        onStartChat: onStartChat,
        onUserBlocked: onUserBlocked,
      ),
    );
  }

  @override
  State<UserInfoSheet> createState() => _UserInfoSheetState();
}

class _UserInfoSheetState extends State<UserInfoSheet> {
  final ChatService _chatService = ChatService();
  bool _isLoading = true;
  int _pointsCount = 0;
  String _displayName = '';

  @override
  void initState() {
    super.initState();
    _displayName = widget.nickname;
    _loadUserStats();
  }

  Future<void> _loadUserStats() async {
    final stats = await _chatService.getUserStats(widget.userId);
    if (mounted) {
      setState(() {
        _pointsCount = stats['points_count'] as int? ?? 0;
        _displayName = stats['nickname'] as String? ?? widget.nickname;
        _isLoading = false;
      });
    }
  }

  // 🚫 Engelleme Diyaloğu
  void _confirmBlockUser() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.block, color: AppColors.error, size: 24),
            SizedBox(width: 10),
            Text('Kullanıcıyı Engelle', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          '$_displayName isimli kullanıcıyı engellemek istediğinizden emin misiniz?\n\nEngellediğinizde birbirinizin konumlarını haritada göremeyecek ve mesajlaşamayacaksınız.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal', style: TextStyle(color: AppColors.textHint)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await _chatService.blockUser(widget.userId);
              if (mounted) {
                Navigator.pop(context); // Close sheet
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success ? 'Kullanıcı engellendi.' : 'Engelleme başarısız oldu.'),
                    backgroundColor: success ? AppColors.primary : AppColors.error,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                if (success) widget.onUserBlocked?.call();
              }
            },
            child: const Text('Engelle', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ⚠️ Şikayet Etme Diyaloğu
  void _showReportDialog() {
    String selectedReason = 'Taciz / Rahatsız Etme';
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
                SizedBox(width: 10),
                Text('Kullanıcıyı Şikayet Et', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Şikayet Nedeni:', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedReason,
                      isExpanded: true,
                      dropdownColor: AppColors.surfaceElevated,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                      items: const [
                        DropdownMenuItem(value: 'Taciz / Rahatsız Etme', child: Text('Taciz / Rahatsız Etme')),
                        DropdownMenuItem(value: 'Uygunsuz İçerik', child: Text('Uygunsuz İçerik')),
                        DropdownMenuItem(value: 'Spam / Reklam', child: Text('Spam / Reklam')),
                        DropdownMenuItem(value: 'Sahte Profil', child: Text('Sahte Profil')),
                        DropdownMenuItem(value: 'Diğer', child: Text('Diğer')),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedReason = val);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: descController,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Açıklama ekleyin (isteğe bağlı)...',
                    hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 13),
                    filled: true,
                    fillColor: AppColors.surfaceElevated,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('İptal', style: TextStyle(color: AppColors.textHint)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  final success = await _chatService.reportUserOrMessage(
                    reportedUserId: widget.userId,
                    reason: selectedReason,
                    description: descController.text.trim(),
                  );
                  if (mounted) {
                    Navigator.pop(context); // Close sheet
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(success ? 'Şikayetiniz yöneticilere iletildi. Teşekkür ederiz.' : 'Şikayet iletilemedi.'),
                        backgroundColor: success ? AppColors.success : AppColors.error,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                child: const Text('Gönder', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firstChar = _displayName.isNotEmpty ? _displayName[0].toUpperCase() : 'K';

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: const Border(top: BorderSide(color: AppColors.border, width: 1.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sürükleme Çubuğu
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // Sağ Üst 3 Nokta Menü & Avatar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 32),
                  // Profil Avatarı
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, Color(0xFF0F3460)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        firstChar,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  // Üç Nokta Menü
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary, size: 26),
                    color: AppColors.surfaceElevated,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    onSelected: (val) {
                      if (val == 'block') {
                        _confirmBlockUser();
                      } else if (val == 'report') {
                        _showReportDialog();
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'report',
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                            SizedBox(width: 10),
                            Text('Kullanıcıyı Şikayet Et', style: TextStyle(color: Colors.white, fontSize: 14)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'block',
                        child: Row(
                          children: [
                            Icon(Icons.block, color: AppColors.error, size: 20),
                            SizedBox(width: 10),
                            Text('Kullanıcıyı Engelle', style: TextStyle(color: AppColors.error, fontSize: 14, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Nickname
              Text(
                _displayName,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Keşif Üyesi',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),

              // İstatistik Kartı
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        _isLoading
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                            : Text('$_pointsCount', style: const TextStyle(color: AppColors.primary, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        const Text('Keşif Noktası', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                    Container(width: 1, height: 28, color: AppColors.divider),
                    const Column(
                      children: [
                        Text('Aktif', style: TextStyle(color: Color(0xFF4CAF50), fontSize: 18, fontWeight: FontWeight.bold)),
                        SizedBox(height: 2),
                        Text('Durum', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Sohbet Başlat Butonu
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onStartChat?.call();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 20),
                  label: const Text(
                    'Sohbet Başlat',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
