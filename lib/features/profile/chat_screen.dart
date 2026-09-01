import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../app/theme.dart';
import '../../services/chat_service.dart';
import '../../shared/widgets/user_info_sheet.dart';
import 'friends_screen.dart';

class ChatScreen extends StatefulWidget {
  final String friendId;
  final String friendNickname;

  const ChatScreen({
    super.key,
    required this.friendId,
    required this.friendNickname,
  });

  /// Şu an hangi arkadaşla sohbet ekranındayız (bildirim filtresi için)
  static String? activeChatFriendId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  RealtimeChannel? _subscription;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    ChatScreen.activeChatFriendId = widget.friendId;
    _loadMessages();
    _setupSubscription();
    _markAsRead();
    // Realtime haricinde arka planda 3 saniyede bir otomatik yeni mesaj kontrolü (bağlantı kesilmesine karşı)
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _fetchNewMessages();
    });
  }

  Future<void> _fetchNewMessages() async {
    if (!mounted || _isLoading) return;
    final msgs = await _chatService.getMessages(widget.friendId);
    if (!mounted) return;
    bool hasNew = false;
    for (final m in msgs) {
      final id = m['id'];
      if (!_messages.any((existing) => existing['id'] == id)) {
        _messages.add(m);
        hasNew = true;
      }
    }
    if (hasNew) {
      setState(() {});
      _scrollToBottom();
      _markAsRead();
    }
  }

  @override
  void dispose() {
    ChatScreen.activeChatFriendId = null;
    _pollTimer?.cancel();
    if (_subscription != null) {
      _chatService.unsubscribe(_subscription!);
    }
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Tüm mesajları okundu olarak işaretle (SharedPreferences'te zaman damgası kaydet)
  Future<void> _markAsRead() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'chat_last_read_${widget.friendId}',
        DateTime.now().toUtc().toIso8601String(),
      );
      FriendsScreen.refreshData?.call();
    } catch (e) {
      print('Mark as read hatası: $e');
    }
  }

  Future<void> _loadMessages() async {
    final msgs = await _chatService.getMessages(widget.friendId);
    if (mounted) {
      setState(() {
        _messages = msgs;
        _isLoading = false;
      });
      _scrollToBottom();
      _markAsRead();
    }
  }

  void _setupSubscription() {
    _subscription = _chatService.subscribeToMessages(widget.friendId, (newMsg) {
      if (mounted) {
        final id = newMsg['id'];
        if (!_messages.any((m) => m['id'] == id)) {
          setState(() {
            _messages.add(newMsg);
          });
          _scrollToBottom();
          _markAsRead();
        }
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    final sentMsg = await _chatService.sendMessage(widget.friendId, text);
    if (sentMsg != null) {
      if (mounted) {
        setState(() {
          if (!_messages.any((m) => m['id'] == sentMsg['id'])) {
            _messages.add(sentMsg);
          }
        });
        _scrollToBottom();
        _markAsRead();
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mesaj gönderilemedi.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = _chatService.currentUserId;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: GestureDetector(
          onTap: () {
            UserInfoSheet.show(
              context,
              userId: widget.friendId,
              nickname: widget.friendNickname,
              onUserBlocked: () {
                Navigator.pop(context);
              },
            );
          },
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.primary.withOpacity(0.12),
                child: Text(
                  widget.friendNickname[0].toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.friendNickname,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const Text(
                    'Profili Gör',
                    style: TextStyle(color: AppColors.primary, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          // Mesaj listesi
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('💬', style: TextStyle(fontSize: 48)),
                            const SizedBox(height: 12),
                            Text(
                              '${widget.friendNickname} ile sohbeti başlat!',
                              style: const TextStyle(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                        itemCount: _messages.length,
                        itemBuilder: (ctx, i) {
                          final msg = _messages[i];
                          final isMe = msg['sender_id'] == myId;
                          return _buildMessageBubble(msg, isMe);
                        },
                      ),
          ),

          // Giriş alanı
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, bool isMe) {
    final content = msg['content'] as String? ?? '';
    final msgId = msg['id'] as String?;

    return GestureDetector(
      onLongPress: () {
        showModalBottomSheet(
          context: context,
          backgroundColor: AppColors.card,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.copy_rounded, color: AppColors.textPrimary),
                  title: const Text('Mesajı Kopyala', style: TextStyle(color: AppColors.textPrimary)),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: content));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Mesaj kopyalandı'), behavior: SnackBarBehavior.floating),
                    );
                  },
                ),
                if (!isMe)
                  ListTile(
                    leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                    title: const Text('Mesajı Şikayet Et', style: TextStyle(color: Colors.orange)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _reportMessage(msgId, widget.friendId);
                    },
                  ),
              ],
            ),
          ),
        );
      },
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          decoration: BoxDecoration(
            color: isMe ? AppColors.primary : AppColors.card,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMe ? 16 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 16),
            ),
            border: isMe ? null : Border.all(color: AppColors.border),
          ),
          child: Text(
            content,
            style: TextStyle(
              color: isMe ? Colors.white : AppColors.textPrimary,
              fontSize: 15,
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }

  void _reportMessage(String? messageId, String senderId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Mesajı Şikayet Et', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text('Bu mesajı uygunsuz içerik veya taciz olarak yöneticilere bildirmek istiyor musunuz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal', style: TextStyle(color: AppColors.textHint)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await _chatService.reportUserOrMessage(
                reportedUserId: senderId,
                messageId: messageId,
                reason: 'Uygunsuz Mesaj',
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success ? 'Mesaj şikayeti iletildi.' : 'Şikayet iletilemedi.'),
                    backgroundColor: success ? AppColors.success : AppColors.error,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Şikayet Et', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              style: const TextStyle(color: AppColors.textPrimary),
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Bir mesaj yazın...',
                filled: true,
                fillColor: AppColors.background,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _send,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.send_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
