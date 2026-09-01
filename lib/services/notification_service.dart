import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'kesif_high_importance',
    'Keşif Bildirimleri',
    description: 'Mesaj ve arkadaşlık isteği bildirimleri',
    importance: Importance.high,
    playSound: true,
  );

  static Future<void> initialize() async {
    // Local notifications kurulumu
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(initSettings);

    // Android'de yüksek öncelikli kanal oluştur
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // Ön planda gelen mesajları local bildirim olarak göster
    FirebaseMessaging.onMessage.listen((message) async {
      await _showLocalNotification(message);
    });

    // Android 13+ için bildirim izni iste
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  /// FCM token'ı alıp Supabase profiles tablosuna kaydet
  static Future<void> saveFcmToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;

      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      await Supabase.instance.client
          .from('profiles')
          .update({'fcm_token': token}).eq('id', userId);

      // Token yenilenirse güncelle
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        final uid = Supabase.instance.client.auth.currentUser?.id;
        if (uid != null) {
          await Supabase.instance.client
              .from('profiles')
              .update({'fcm_token': newToken}).eq('id', uid);
        }
      });
    } catch (e) {
      print('FCM token kaydetme hatası: $e');
    }
  }

  /// Uygulama arka planda/kapalıyken çağrılır (background handler'dan)
  static Future<void> showBackgroundNotification(RemoteMessage message) async {
    await _showLocalNotification(message);
  }

  /// Local bildirim göster
  static Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final data = message.data;

    final title = notification?.title ?? data['title'] ?? 'Keşif';
    final body = notification?.body ?? data['body'] ?? '';

    await _localNotifications.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: const Color(0xFFE91E63),
          playSound: true,
        ),
      ),
      payload: jsonEncode(data),
    );
  }
}
