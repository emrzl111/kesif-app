import 'package:supabase_flutter/supabase_flutter.dart';

class ChatService {
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  String? get currentUserId => _supabase.auth.currentUser?.id;

  // Kullanıcı nickname'ini getir
  Future<String> getNickname(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('nickname')
          .eq('id', userId)
          .single();
      return response['nickname'] as String? ?? 'Kullanıcı';
    } catch (e) {
      return 'Kullanıcı';
    }
  }

  // FCM token kaydet
  Future<void> saveFcmToken(String token) async {
    final myId = currentUserId;
    if (myId == null) return;
    try {
      await _supabase
          .from('profiles')
          .update({'fcm_token': token})
          .eq('id', myId);
    } catch (e) {
      print('FCM token kaydedilemedi: $e');
    }
  }

  // Profil Arama
  Future<List<Map<String, dynamic>>> searchProfiles(String nicknameQuery) async {
    final myId = currentUserId;
    if (myId == null || nicknameQuery.trim().isEmpty) return [];

    try {
      final response = await _supabase
          .from('profiles')
          .select('id, nickname')
          .neq('id', myId)
          .ilike('nickname', '%$nicknameQuery%')
          .limit(20);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Arama hatası: $e');
      return [];
    }
  }

  // Arkadaşlık İsteği Gönder
  Future<bool> sendFriendRequest(String receiverId) async {
    final myId = currentUserId;
    if (myId == null) return false;

    try {
      await _supabase.from('friendships').insert({
        'sender_id': myId,
        'receiver_id': receiverId,
        'status': 'pending',
      });
      return true;
    } catch (e) {
      print('Arkadaşlık isteği hatası: $e');
      return false;
    }
  }

  // Arkadaşlıkları Listele (Gelen, Giden ve Arkadaşlar)
  Future<List<Map<String, dynamic>>> getFriendships() async {
    final myId = currentUserId;
    if (myId == null) return [];

    try {
      // sender_id veya receiver_id biz olan ilişkileri çek, ilişki kurulan kişilerin profil bilgilerini de al
      final response = await _supabase
          .from('friendships')
          .select('''
            id,
            status,
            sender_id,
            receiver_id,
            sender:profiles!friendships_sender_id_fkey(id, nickname),
            receiver:profiles!friendships_receiver_id_fkey(id, nickname)
          ''');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Arkadaşlık listeleme hatası: $e');
      return [];
    }
  }

  // Arkadaşlık İsteğini Kabul Et
  Future<bool> acceptFriendRequest(String friendshipId) async {
    try {
      await _supabase
          .from('friendships')
          .update({'status': 'accepted'})
          .eq('id', friendshipId);
      return true;
    } catch (e) {
      print('İstek kabul hatası: $e');
      return false;
    }
  }

  // Arkadaşlık İsteğini Reddet veya Arkadaşı Sil
  Future<bool> deleteFriendship(String friendshipId) async {
    try {
      await _supabase
          .from('friendships')
          .delete()
          .eq('id', friendshipId);
      return true;
    } catch (e) {
      print('Arkadaşlık silme hatası: $e');
      return false;
    }
  }

  // Mesajları Getir
  Future<List<Map<String, dynamic>>> getMessages(String friendId) async {
    final myId = currentUserId;
    if (myId == null) return [];

    try {
      final response = await _supabase
          .from('messages')
          .select()
          .or('and(sender_id.eq.$myId,receiver_id.eq.$friendId),and(sender_id.eq.$friendId,receiver_id.eq.$myId)')
          .order('created_at', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Mesaj çekme hatası: $e');
      return [];
    }
  }

  // Mesaj Gönder
  Future<Map<String, dynamic>?> sendMessage(String receiverId, String content) async {
    final myId = currentUserId;
    if (myId == null || content.trim().isEmpty) return null;

    try {
      final response = await _supabase.from('messages').insert({
        'sender_id': myId,
        'receiver_id': receiverId,
        'content': content.trim(),
      }).select().single();
      return Map<String, dynamic>.from(response);
    } catch (e) {
      print('Mesaj gönderme hatası: $e');
      return null;
    }
  }

  // Mesaj Realtime Aboneliği
  RealtimeChannel subscribeToMessages(
    String friendId,
    void Function(Map<String, dynamic> message) onNewMessage,
  ) {
    final myId = currentUserId ?? '';
    final channelName = 'chat_${myId}_${friendId}_${DateTime.now().millisecondsSinceEpoch}';
    
    final channel = _supabase
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final newRecord = payload.newRecord;
            if (newRecord.isNotEmpty) {
              final senderId = newRecord['sender_id'] as String?;
              final receiverId = newRecord['receiver_id'] as String?;
              
              // Eğer mesaj bizim ve arkadaşımızın arasındaysa callback tetikle
              if ((senderId == myId && receiverId == friendId) ||
                  (senderId == friendId && receiverId == myId)) {
                onNewMessage(newRecord);
              }
            }
          },
        )
        .subscribe();

    return channel;
  }

  // Realtime Aboneliği Kapat
  Future<void> unsubscribe(RealtimeChannel channel) async {
    await _supabase.removeChannel(channel);
  }

  // Tüm sohbetleri getir (arkadaş listesi için son mesajla birlikte)
  Future<List<Map<String, dynamic>>> getAllConversations(
      List<Map<String, dynamic>> friends) async {
    final myId = currentUserId;
    if (myId == null) return [];

    final List<Map<String, dynamic>> conversations = [];
    for (final friend in friends) {
      final friendId = friend['id'] as String;
      final messages = await getMessages(friendId);
      if (messages.isNotEmpty) {
        final lastMsg = messages.last;
        conversations.add({
          'friend_id': friendId,
          'friend_nickname': friend['nickname'],
          'friendship_id': friend['friendship_id'],
          'last_message': lastMsg['content'],
          'last_message_sender': lastMsg['sender_id'],
          'last_message_time': lastMsg['created_at'],
          'all_messages': messages,
        });
      } else {
        // Hiç mesaj olmayan arkadaşları da göster
        conversations.add({
          'friend_id': friendId,
          'friend_nickname': friend['nickname'],
          'friendship_id': friend['friendship_id'],
          'last_message': null,
          'last_message_sender': null,
          'last_message_time': null,
          'all_messages': [],
        });
      }
    }

    // Son mesaja göre sırala
    conversations.sort((a, b) {
      final aTime = a['last_message_time'] as String?;
      final bTime = b['last_message_time'] as String?;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });

    return conversations;
  }

  // Global bildirim aboneliği (mesaj + arkadaşlık isteği)
  RealtimeChannel subscribeToGlobalNotifications({
    required void Function(Map<String, dynamic> message) onNewMessage,
    required void Function(Map<String, dynamic> request) onFriendRequest,
  }) {
    final myId = currentUserId ?? '';

    final channel = _supabase
        .channel('global_notifications_$myId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final newRecord = payload.newRecord;
            final receiverId = newRecord['receiver_id'] as String;
            if (receiverId == myId) {
              onNewMessage(newRecord);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'friendships',
          callback: (payload) {
            final newRecord = payload.newRecord;
            final receiverId = newRecord['receiver_id'] as String;
            if (receiverId == myId) {
              onFriendRequest(newRecord);
            }
          },
        )
        .subscribe();

    return channel;
  }

  // 🚫 Kullanıcı Engelleme
  Future<bool> blockUser(String blockedUserId) async {
    final myId = currentUserId;
    if (myId == null) return false;
    try {
      await _supabase.from('user_blocks').insert({
        'blocker_id': myId,
        'blocked_id': blockedUserId,
      });
      return true;
    } catch (e) {
      print('Engelleme hatası: $e');
      return false;
    }
  }

  // Engeli Kaldır
  Future<bool> unblockUser(String blockedUserId) async {
    final myId = currentUserId;
    if (myId == null) return false;
    try {
      await _supabase
          .from('user_blocks')
          .delete()
          .eq('blocker_id', myId)
          .eq('blocked_id', blockedUserId);
      return true;
    } catch (e) {
      print('Engel kaldırma hatası: $e');
      return false;
    }
  }

  // Engellenen kullanıcı kimliklerini getir (Çift taraflı)
  Future<List<String>> getBlockedUserIds() async {
    final myId = currentUserId;
    if (myId == null) return [];
    try {
      final myBlocks = await _supabase
          .from('user_blocks')
          .select('blocked_id')
          .eq('blocker_id', myId);

      final blockedMe = await _supabase
          .from('user_blocks')
          .select('blocker_id')
          .eq('blocked_id', myId);

      final List<String> ids = [];
      for (final item in (myBlocks as List)) {
        ids.add(item['blocked_id'] as String);
      }
      for (final item in (blockedMe as List)) {
        ids.add(item['blocker_id'] as String);
      }
      return ids.toSet().toList();
    } catch (e) {
      print('Engellenen listesi çekme hatası: $e');
      return [];
    }
  }

  // ⚠️ Kullanıcı veya Mesaj Şikayet Etme
  Future<bool> reportUserOrMessage({
    required String reportedUserId,
    String? messageId,
    required String reason,
    String? description,
  }) async {
    final myId = currentUserId;
    if (myId == null) return false;
    try {
      await _supabase.from('reports').insert({
        'reporter_id': myId,
        'reported_user_id': reportedUserId,
        'message_id': messageId,
        'reason': reason,
        'description': description,
      });
      return true;
    } catch (e) {
      print('Şikayet gönderme hatası: $e');
      return false;
    }
  }

  // 🗑️ Hesap Kalıcı Silme (KVKK Uyumlu)
  Future<bool> deleteAccount() async {
    final myId = currentUserId;
    if (myId == null) return false;
    try {
      await _supabase.from('profiles').delete().eq('id', myId);
      await _supabase.auth.signOut();
      return true;
    } catch (e) {
      print('Hesap silme hatası: $e');
      return false;
    }
  }

  // Kullanıcı İstatistikleri
  Future<Map<String, dynamic>> getUserStats(String userId) async {
    try {
      final pointsCount = await _supabase
          .from('discovery_points')
          .select('id')
          .eq('user_id', userId);

      final nickname = await getNickname(userId);

      return {
        'nickname': nickname,
        'points_count': (pointsCount as List).length,
      };
    } catch (e) {
      return {
        'nickname': 'Kullanıcı',
        'points_count': 0,
      };
    }
  }
}
