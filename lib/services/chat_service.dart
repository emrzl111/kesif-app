import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_logger.dart';

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
      AppLogger.error('FCM token kaydedilemedi', error: e, tag: 'ChatService');
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
      AppLogger.error('Arama hatası', error: e, tag: 'ChatService');
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
      AppLogger.error('Arkadaşlık isteği hatası', error: e, tag: 'ChatService');
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
      AppLogger.error('Arkadaşlık listeleme hatası', error: e, tag: 'ChatService');
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
      AppLogger.error('İstek kabul hatası', error: e, tag: 'ChatService');
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
      AppLogger.error('Arkadaşlık silme hatası', error: e, tag: 'ChatService');
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
      AppLogger.error('Mesaj çekme hatası', error: e, tag: 'ChatService');
      return [];
    }
  }

  // Belirli bir zamandan sonraki mesajları getir (yedek kontrol için hafif sorgu)
  Future<List<Map<String, dynamic>>> getMessagesAfter(
      String friendId, String? afterCreatedAt) async {
    final myId = currentUserId;
    if (myId == null) return [];
    if (afterCreatedAt == null) return getMessages(friendId);

    try {
      final response = await _supabase
          .from('messages')
          .select()
          .or('and(sender_id.eq.$myId,receiver_id.eq.$friendId),and(sender_id.eq.$friendId,receiver_id.eq.$myId)')
          .gt('created_at', afterCreatedAt)
          .order('created_at', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      AppLogger.error('Yeni mesaj çekme hatası', error: e, tag: 'ChatService');
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
      AppLogger.error('Mesaj gönderme hatası', error: e, tag: 'ChatService');
      return null;
    }
  }

  // Mesaj Realtime Aboneliği
  RealtimeChannel subscribeToMessages(
    String friendId,
    void Function(Map<String, dynamic> message) onNewMessage, {
    void Function(bool isConnected)? onStatusChange,
  }) {
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
        .subscribe((status, [error]) {
      onStatusChange?.call(status == RealtimeSubscribeStatus.subscribed);
    });

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
      AppLogger.error('Engelleme hatası', error: e, tag: 'ChatService');
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
      AppLogger.error('Engel kaldırma hatası', error: e, tag: 'ChatService');
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
      AppLogger.error('Engellenen listesi çekme hatası', error: e, tag: 'ChatService');
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
      AppLogger.error('Şikayet gönderme hatası', error: e, tag: 'ChatService');
      return false;
    }
  }

  // 🗑️ Hesap Kalıcı Silme (KVKK Uyumlu)
  /// Kullanıcıya ait TÜM verileri sıralı olarak siler:
  /// messages → friendships → user_blocks → reports → discovery_points
  /// → FCM token temizle → profiles → auth.signOut()
  ///
  /// NOT: Supabase RLS politikalarının bu silme işlemlerine izin verdiğinden
  /// emin olun. Gerekirse Supabase Dashboard > Authentication > Policies
  /// bölümünden kontrol edin.
  Future<bool> deleteAccount() async {
    final myId = currentUserId;
    if (myId == null) return false;

    AppLogger.warning('Hesap silme başlatıldı: $myId', tag: 'ChatService');

    try {
      // 1. Gönderilen ve alınan tüm mesajlar
      await _supabase
          .from('messages')
          .delete()
          .or('sender_id.eq.$myId,receiver_id.eq.$myId');

      // 2. Tüm arkadaşlık ilişkileri
      await _supabase
          .from('friendships')
          .delete()
          .or('sender_id.eq.$myId,receiver_id.eq.$myId');

      // 3. Engelleme kayıtları (her iki yön)
      await _supabase
          .from('user_blocks')
          .delete()
          .or('blocker_id.eq.$myId,blocked_id.eq.$myId');

      // 4. Raporlar (gönderilen)
      await _supabase
          .from('reports')
          .delete()
          .eq('reporter_id', myId);

      // 5. Nokta ziyaret geçmişi
      await _supabase
          .from('point_visits')
          .delete()
          .eq('user_id', myId);

      // 6. Kullanıcının eklediği keşif noktaları
      await _supabase
          .from('discovery_points')
          .delete()
          .eq('user_id', myId);

      // 7. FCM token'ı temizle (null yap, profil silinmeden önce)
      try {
        await _supabase
            .from('profiles')
            .update({'fcm_token': null})
            .eq('id', myId);
      } catch (_) {}

      // 8. Profil kaydı (CASCADE ile bağlı kayıtlar DB tarafında da temizlenir)
      await _supabase.from('profiles').delete().eq('id', myId);

      // 9. Oturumu kapat
      await _supabase.auth.signOut();

      AppLogger.info('Hesap başarıyla silindi: $myId', tag: 'ChatService');
      return true;
    } catch (e, stack) {
      AppLogger.error(
        'Hesap silme hatası — kullanıcı: $myId',
        error: e,
        stack: stack,
        tag: 'ChatService',
      );
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
