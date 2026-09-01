import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/theme.dart';
import '../../services/chat_service.dart';
import '../../services/auth_service.dart';
import '../../shared/widgets/premium_paywall_sheet.dart';
import 'chat_screen.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  static VoidCallback? refreshData;
  static VoidCallback? goToChatsTab;
  static VoidCallback? goToRequestsTab;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen>
    with SingleTickerProviderStateMixin {
  final ChatService _chatService = ChatService();
  final TextEditingController _searchController = TextEditingController();

  late TabController _tabController;
  bool _isLoading = false;
  bool _isSearching = false;
  bool _isConversationsLoading = false;

  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _incomingRequests = [];
  List<Map<String, dynamic>> _outgoingRequests = [];
  List<Map<String, dynamic>> _conversations = [];

  // Okunmamış mesaj sayıları: friendId -> count
  Map<String, int> _unreadCounts = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    FriendsScreen.refreshData = _loadData;
    FriendsScreen.goToChatsTab = () {
      if (mounted) _tabController.animateTo(1);
    };
    FriendsScreen.goToRequestsTab = () {
      if (mounted) _tabController.animateTo(2);
    };
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    if (FriendsScreen.refreshData == _loadData) {
      FriendsScreen.refreshData = null;
    }
    if (FriendsScreen.goToChatsTab != null) FriendsScreen.goToChatsTab = null;
    if (FriendsScreen.goToRequestsTab != null) FriendsScreen.goToRequestsTab = null;
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final myId = _chatService.currentUserId;
    if (myId == null) return;

    final allFriendships = await _chatService.getFriendships();

    final List<Map<String, dynamic>> friendsList = [];
    final List<Map<String, dynamic>> incomingList = [];
    final List<Map<String, dynamic>> outgoingList = [];

    for (final f in allFriendships) {
      final status = f['status'] as String;
      final senderId = f['sender_id'] as String;
      final receiverId = f['receiver_id'] as String;

      final senderData = f['sender'] as Map<String, dynamic>?;
      final receiverData = f['receiver'] as Map<String, dynamic>?;

      if (status == 'accepted') {
        final friendProfile = senderId == myId ? receiverData : senderData;
        if (friendProfile != null) {
          friendsList.add({
            'friendship_id': f['id'],
            'id': friendProfile['id'],
            'nickname': friendProfile['nickname'],
          });
        }
      } else if (status == 'pending') {
        if (senderId == myId) {
          if (receiverData != null) {
            outgoingList.add({
              'friendship_id': f['id'],
              'id': receiverData['id'],
              'nickname': receiverData['nickname'],
            });
          }
        } else if (receiverId == myId) {
          if (senderData != null) {
            incomingList.add({
              'friendship_id': f['id'],
              'id': senderData['id'],
              'nickname': senderData['nickname'],
            });
          }
        }
      }
    }

    if (mounted) {
      setState(() {
        _friends = friendsList;
        _incomingRequests = incomingList;
        _outgoingRequests = outgoingList;
        _isLoading = false;
      });
    }

    // Sohbetleri ve okunmamış sayıları yükle
    await _loadConversations(friendsList, myId);
  }

  Future<void> _loadConversations(
      List<Map<String, dynamic>> friends, String myId) async {
    if (!mounted) return;
    setState(() => _isConversationsLoading = true);

    final conversations = await _chatService.getAllConversations(friends);

    // SharedPreferences'ten okundu zamanlarını al ve unread sayısını hesapla
    final prefs = await SharedPreferences.getInstance();
    final Map<String, int> unreadCounts = {};

    for (final conv in conversations) {
      final friendId = conv['friend_id'] as String;
      final messages = conv['all_messages'] as List<Map<String, dynamic>>;
      final lastReadStr = prefs.getString('chat_last_read_$friendId');

      DateTime? lastReadTime;
      if (lastReadStr != null) {
        lastReadTime = DateTime.tryParse(lastReadStr);
      }

      int unread = 0;
      for (final msg in messages) {
        final senderId = msg['sender_id'] as String;
        if (senderId == myId) continue; // kendi mesajım
        final createdAt = msg['created_at'] as String?;
        if (createdAt == null) continue;
        final msgTime = DateTime.tryParse(createdAt);
        if (msgTime == null) continue;
        if (lastReadTime == null || msgTime.isAfter(lastReadTime)) {
          unread++;
        }
      }
      unreadCounts[friendId] = unread;
    }

    if (mounted) {
      setState(() {
        _conversations = conversations;
        _unreadCounts = unreadCounts;
        _isConversationsLoading = false;
      });
    }
  }

  Future<void> _searchUsers() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    setState(() => _isSearching = true);
    final results = await _chatService.searchProfiles(query);
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  Future<void> _sendRequest(String userId) async {
    final success = await _chatService.sendFriendRequest(userId);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Arkadaşlık isteği gönderildi!'),
          backgroundColor: AppColors.success,
        ),
      );
      _loadData();
    }
  }

  Future<void> _acceptRequest(String friendshipId) async {
    final success = await _chatService.acceptFriendRequest(friendshipId);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Arkadaşlık isteği kabul edildi! 🎉'),
          backgroundColor: AppColors.success,
        ),
      );
      _loadData();
    }
  }

  Future<void> _removeOrRejectFriendship(
      String friendshipId, String message) async {
    final success = await _chatService.deleteFriendship(friendshipId);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
        ),
      );
      _loadData();
    }
  }

  bool _isAlreadyFriend(String userId) =>
      _friends.any((f) => f['id'] == userId);
  bool _hasPendingIncoming(String userId) =>
      _incomingRequests.any((r) => r['id'] == userId);
  bool _hasPendingOutgoing(String userId) =>
      _outgoingRequests.any((r) => r['id'] == userId);

  @override
  Widget build(BuildContext context) {
    final totalUnread = _unreadCounts.values.fold(0, (a, b) => a + b);
    final pendingRequests = _incomingRequests.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Arkadaşlarım',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: [
            const Tab(text: 'Arkadaşlarım'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Sohbet'),
                  if (totalUnread > 0) ...[
                    const SizedBox(width: 6),
                    _buildBadge(totalUnread, AppColors.primary),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('İstekler'),
                  if (pendingRequests > 0) ...[
                    const SizedBox(width: 6),
                    _buildBadge(pendingRequests, AppColors.error),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFriendsTab(),
          _buildChatsTab(),
          _buildRequestsTab(),
        ],
      ),
    );
  }

  Widget _buildBadge(int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ─── SEKME 1: Arkadaşlarım ────────────────────────────────────────────────

  Widget _buildFriendsTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppColors.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Arama kutusu
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      hintText: 'Kullanıcı adı ile ara...',
                      prefixIcon:
                          Icon(Icons.search, color: AppColors.textSecondary),
                      filled: true,
                      fillColor: AppColors.surface,
                    ),
                    onSubmitted: (_) => _searchUsers(),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _searchUsers,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                        vertical: 16, horizontal: 18),
                  ),
                  child: _isSearching
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Ara'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Arama Sonuçları
            if (_searchResults.isNotEmpty) ...[
              const Text(
                'Arama Sonuçları',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              ...List.generate(_searchResults.length, (i) {
                final user = _searchResults[i];
                final userId = user['id'] as String;
                Widget actionButton;
                if (_isAlreadyFriend(userId)) {
                  actionButton = const Text('Arkadaşsınız',
                      style: TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.bold));
                } else if (_hasPendingIncoming(userId)) {
                  actionButton = const Text('İstek Gönderdi',
                      style: TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.bold));
                } else if (_hasPendingOutgoing(userId)) {
                  actionButton = const Text('Beklemede',
                      style: TextStyle(color: AppColors.textHint));
                } else {
                  actionButton = ElevatedButton(
                    onPressed: () => _sendRequest(userId),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary),
                    child: const Text('Ekle'),
                  );
                }
                return _buildUserTile(
                  nickname: user['nickname'],
                  avatarColor: AppColors.primary.withOpacity(0.1),
                  trailing: actionButton,
                );
              }),
              const SizedBox(height: 20),
            ],

            // Arkadaş listesi başlığı
            if (_isLoading)
              const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
            else if (_friends.isEmpty && _searchResults.isEmpty)
              _buildEmptyState(
                emoji: '🤝',
                title: 'Henüz arkadaşın yok',
                subtitle: 'Yukarıdan kullanıcı aratarak ekleyebilirsin!',
              )
            else if (_friends.isNotEmpty) ...[
              const Text(
                'Arkadaşlarım',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              ...List.generate(_friends.length, (i) {
                final f = _friends[i];
                return _buildUserTile(
                  nickname: f['nickname'],
                  avatarColor: AppColors.primary.withOpacity(0.12),
                  avatarTextColor: AppColors.primary,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chat_bubble_outline_rounded,
                            color: AppColors.primary),
                        onPressed: () => _openChat(f),
                      ),
                      IconButton(
                        icon: const Icon(Icons.person_remove_outlined,
                            color: AppColors.error),
                        onPressed: () => _showRemoveFriendDialog(f),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  // ─── SEKME 2: Sohbet ──────────────────────────────────────────────────────

  Widget _buildChatsTab() {
    if (_isConversationsLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }

    if (_conversations.isEmpty) {
      return _buildEmptyState(
        emoji: '💬',
        title: 'Henüz sohbet yok',
        subtitle: 'Arkadaşlarına mesaj göndererek başlayabilirsin!',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _conversations.length,
        itemBuilder: (ctx, i) {
          final conv = _conversations[i];
          final friendId = conv['friend_id'] as String;
          final nickname = conv['friend_nickname'] as String;
          final lastMsg = conv['last_message'] as String?;
          final senderIsMe = conv['last_message_sender'] ==
              _chatService.currentUserId;
          final unread = _unreadCounts[friendId] ?? 0;

          String preview = 'Henüz mesaj yok';
          if (lastMsg != null) {
            preview = senderIsMe ? 'Sen: $lastMsg' : lastMsg;
          }

          return GestureDetector(
            onTap: () => _openChatByConv(conv),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: unread > 0
                      ? AppColors.primary.withOpacity(0.4)
                      : AppColors.border,
                ),
              ),
              child: Row(
                children: [
                  // Avatar
                  Stack(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppColors.primary.withOpacity(0.12),
                        radius: 24,
                        child: Text(
                          nickname[0].toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      if (unread > 0)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                                minWidth: 18, minHeight: 18),
                            child: Text(
                              unread > 99 ? '99+' : '$unread',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nickname,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: unread > 0
                                ? FontWeight.bold
                                : FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          preview,
                          style: TextStyle(
                            color: unread > 0
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: unread > 0
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textHint),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── SEKME 3: İstekler ────────────────────────────────────────────────────

  Widget _buildRequestsTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppColors.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_incomingRequests.isEmpty && _outgoingRequests.isEmpty)
              _buildEmptyState(
                emoji: '📭',
                title: 'Bekleyen istek yok',
                subtitle: 'Arkadaşlık isteklerin burada görünecek',
              )
            else ...[
              if (_incomingRequests.isNotEmpty) ...[
                Row(
                  children: [
                    const Text(
                      'Gelen İstekler',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    _buildBadge(_incomingRequests.length, AppColors.error),
                  ],
                ),
                const SizedBox(height: 10),
                ...List.generate(_incomingRequests.length, (i) {
                  final req = _incomingRequests[i];
                  return _buildRequestTile(req, isIncoming: true);
                }),
                const SizedBox(height: 20),
              ],
              if (_outgoingRequests.isNotEmpty) ...[
                const Text(
                  'Gönderilen İstekler',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                ...List.generate(_outgoingRequests.length, (i) {
                  final req = _outgoingRequests[i];
                  return _buildRequestTile(req, isIncoming: false);
                }),
              ],
            ],
          ],
        ),
      ),
    );
  }

  // ─── Yardımcı Widget'lar ──────────────────────────────────────────────────

  Widget _buildUserTile({
    required String nickname,
    required Widget trailing,
    Color? avatarColor,
    Color? avatarTextColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: avatarColor ?? AppColors.primary.withOpacity(0.1),
            child: Text(
              nickname[0].toUpperCase(),
              style: TextStyle(
                color: avatarTextColor ?? AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              nickname,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _buildRequestTile(Map<String, dynamic> req, {required bool isIncoming}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isIncoming
              ? AppColors.accent.withOpacity(0.3)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: isIncoming
                ? AppColors.accent.withOpacity(0.12)
                : AppColors.textHint.withOpacity(0.1),
            child: Text(
              req['nickname'][0].toUpperCase(),
              style: TextStyle(
                color: isIncoming ? AppColors.accent : AppColors.textSecondary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              req['nickname'],
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (isIncoming) ...[
            ElevatedButton(
              onPressed: () => _acceptRequest(req['friendship_id']),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8)),
              child: const Text('Kabul Et', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 6),
            OutlinedButton(
              onPressed: () => _removeOrRejectFriendship(
                  req['friendship_id'], 'İstek reddedildi.'),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.error),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: const Text('Reddet',
                  style:
                      TextStyle(color: AppColors.error, fontSize: 12)),
            ),
          ] else
            OutlinedButton(
              onPressed: () => _removeOrRejectFriendship(
                  req['friendship_id'], 'İstek iptal edildi.'),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.textHint),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: const Text('İptal Et',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required String emoji,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _openChat(Map<String, dynamic> friend) {
    final isPremium = AuthService.isPremiumMock;
    if (!isPremium) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const PremiumPaywallSheet(),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          friendId: friend['id'],
          friendNickname: friend['nickname'],
        ),
      ),
    ).then((_) => _loadData());
  }

  void _openChatByConv(Map<String, dynamic> conv) {
    final isPremium = AuthService.isPremiumMock;
    if (!isPremium) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const PremiumPaywallSheet(),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          friendId: conv['friend_id'],
          friendNickname: conv['friend_nickname'],
        ),
      ),
    ).then((_) => _loadData());
  }

  void _showRemoveFriendDialog(Map<String, dynamic> f) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Arkadaşı Sil',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text('${f['nickname']} arkadaş listenizden silinsin mi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.pop(ctx);
              _removeOrRejectFriendship(
                  f['friendship_id'], 'Arkadaş silindi.');
            },
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }
}
