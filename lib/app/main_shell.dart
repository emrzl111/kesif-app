import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kesif_app/features/map/map_screen.dart';
import 'package:kesif_app/features/tracking/tracking_screen.dart';
import 'package:kesif_app/features/discovery/discovery_screen.dart';
import 'package:kesif_app/features/profile/profile_screen.dart';
import 'package:kesif_app/features/profile/friends_screen.dart';
import 'package:kesif_app/features/profile/chat_screen.dart';
import 'package:kesif_app/features/auth/login_screen.dart';
import 'package:kesif_app/services/auth_service.dart';
import 'package:kesif_app/services/chat_service.dart';
import 'package:kesif_app/shared/widgets/premium_paywall_sheet.dart';
import 'package:kesif_app/features/auth/setup_nickname_sheet.dart';
import '../shared/models/models.dart';

class MainShell extends StatefulWidget {
  static final GlobalKey<MainShellState> shellKey = GlobalKey<MainShellState>();

  MainShell() : super(key: shellKey);

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  late final StreamSubscription<AuthState> _authSubscription;
  final ChatService _chatService = ChatService();
  RealtimeChannel? _globalNotificationChannel;

  @override
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (mounted) {
        setState(() {});
        if (data.session != null) {
          _startGlobalNotifications();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            SetupNicknameSheet.showIfNeeded(context);
          });
        } else {
          _stopGlobalNotifications();
        }
      }
    });

    // Uygulama başlangıçta zaten giriş yapılmışsa bildirimleri başlat ve nick kontrolü yap
    if (Supabase.instance.client.auth.currentSession != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startGlobalNotifications();
        SetupNicknameSheet.showIfNeeded(context);
      });
    }
  }

  void _startGlobalNotifications() {
    _stopGlobalNotifications();
    _globalNotificationChannel = _chatService.subscribeToGlobalNotifications(
      onNewMessage: (message) async {
        final senderId = message['sender_id'] as String;
        // Aktif sohbette o kişiyle konuşuyorsak bildirim gösterme
        if (ChatScreen.activeChatFriendId == senderId) return;
        final nickname = await _chatService.getNickname(senderId);
        final content = message['content'] as String? ?? '';
        if (mounted) {
          _showInAppNotification(
            icon: Icons.chat_bubble_rounded,
            title: nickname,
            body: content,
            onTap: () {
              // Arkadaşlarım sekmesine geç (index 3) ve Sohbet tab'ını aç
              setState(() => _currentIndex = 3);
              FriendsScreen.goToChatsTab?.call();
              FriendsScreen.refreshData?.call();
            },
          );
        }
      },
      onFriendRequest: (request) async {
        final senderId = request['sender_id'] as String;
        final nickname = await _chatService.getNickname(senderId);
        if (mounted) {
          _showInAppNotification(
            icon: Icons.person_add_rounded,
            title: 'Yeni Arkadaşlık İsteği',
            body: '$nickname sana arkadaşlık isteği gönderdi!',
            onTap: () {
              setState(() => _currentIndex = 3);
              FriendsScreen.goToRequestsTab?.call();
              FriendsScreen.refreshData?.call();
            },
          );
        }
      },
    );
  }

  void _stopGlobalNotifications() {
    if (_globalNotificationChannel != null) {
      _chatService.unsubscribe(_globalNotificationChannel!);
      _globalNotificationChannel = null;
    }
  }

  void _showInAppNotification({
    required IconData icon,
    required String title,
    required String body,
    required VoidCallback onTap,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        duration: const Duration(seconds: 5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        content: GestureDetector(
          onTap: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            onTap();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2340),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE91E63).withValues(alpha: 0.4)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE91E63).withOpacity(0.15),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE91E63).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: const Color(0xFFE91E63), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        body,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: Colors.white.withValues(alpha: 0.5), size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    _stopGlobalNotifications();
    super.dispose();
  }

  void switchTab(int index, {DiscoveryPoint? navigateToPoint}) {
    setState(() {
      _currentIndex = index;
    });
    if (navigateToPoint != null) {
      MapScreen.pendingNavigationTarget = navigateToPoint;
      MapScreen.triggerPendingNavigation?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    final isLoggedIn = session != null;
    final List<Widget> screens = [
      const MapScreen(),
      const TrackingScreen(),
      const DiscoveryScreen(),
      if (isLoggedIn) const FriendsScreen(),
      isLoggedIn ? const ProfileScreen() : const LoginScreen(),
    ];

    int activeIndex = _currentIndex;
    if (activeIndex >= screens.length) {
      activeIndex = screens.length - 1;
    }

    return Scaffold(
      body: IndexedStack(
        index: activeIndex,
        children: screens,
      ),
      bottomNavigationBar: _buildBottomNav(session, screens.length),
    );
  }

  Widget _buildBottomNav(Session? session, int screensCount) {
    final isLoggedIn = session != null;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        border: Border(
          top: BorderSide(color: Color(0xFF2A3550), width: 1),
        ),
      ),
      child: BottomNavigationBar(
        currentIndex: _currentIndex >= screensCount ? screensCount - 1 : _currentIndex,
        onTap: (index) {
          if (isLoggedIn && index == 3) {
            final isPremium = AuthService.isPremiumMock;
            if (!isPremium) {
              showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const PremiumPaywallSheet(),
              );
              return;
            }
            FriendsScreen.refreshData?.call();
          }
          setState(() => _currentIndex = index);
          if (index == 0) {
            MapScreen.refreshPoints?.call();
          } else if (index == 2) {
            DiscoveryScreen.refreshPoints?.call();
          }
        },
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: 'Harita',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.route_outlined),
            activeIcon: Icon(Icons.route),
            label: 'Rota',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.explore_outlined),
            activeIcon: Icon(Icons.explore),
            label: 'Keşfet',
          ),
          if (isLoggedIn)
            const BottomNavigationBarItem(
              icon: Icon(Icons.people_outline_rounded),
              activeIcon: Icon(Icons.people_rounded),
              label: 'Arkadaşlarım',
            ),
          BottomNavigationBarItem(
            icon: Icon(isLoggedIn ? Icons.person_outlined : Icons.login_outlined),
            activeIcon: Icon(isLoggedIn ? Icons.person : Icons.login),
            label: isLoggedIn ? 'Profil' : 'Giriş Yap',
          ),
        ],
      ),
    );
  }
}
