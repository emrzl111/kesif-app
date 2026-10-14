import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static bool isPremiumMock = true; // All features 100% free and unlocked

  final SupabaseClient _supabase = Supabase.instance.client;

  User? get currentUser => _supabase.auth.currentUser;
  bool get isLoggedIn => currentUser != null;

  Stream<AuthState> get authStateStream => _supabase.auth.onAuthStateChange;

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String nickname,
  }) async {
    // Önce kullanıcı adının alınmadığını kontrol et
    final check = await _supabase
        .from('profiles')
        .select('id')
        .ilike('nickname', nickname)
        .maybeSingle();

    if (check != null) {
      throw const AuthException('Bu kullanıcı adı zaten alınmış.');
    }

    final res = await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {'nickname': nickname},
    );

    if (res.user != null) {
      try {
        await _supabase.from('profiles').upsert({
          'id': res.user!.id,
          'nickname': nickname.trim(),
          'updated_at': DateTime.now().toIso8601String(),
        });
      } catch (_) {}
    }

    return res;
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<bool> signInWithGoogle() async {
    return await _supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'com.kesif.app://login-callback',
    );
  }

  /// iOS: Apple ile giriş (App Store Kural 4.8).
  /// Apple'dan gelen kimlik belirteci Supabase oturumuna çevrilir.
  /// Kullanıcı pencereyi kapatırsa [SignInWithAppleAuthorizationException] (canceled) fırlatılır.
  /// Apple'dan gelen ad soyad (yalnızca ilk girişte verilir); takma ad önerisinde kullanılır.
  static String? _pendingAppleName;

  Future<AuthResponse> signInWithApple() async {
    final rawNonce = _supabase.auth.generateRawNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );

    final idToken = credential.identityToken;
    if (idToken == null) {
      throw const AuthException('Apple kimlik bilgisi alınamadı.');
    }

    // Oturum açılır açılmaz takma ad ekranı çıkabileceği için adı önceden sakla
    final givenName = credential.givenName;
    final familyName = credential.familyName;
    if (givenName != null && givenName.trim().isNotEmpty) {
      _pendingAppleName = [givenName, familyName]
          .where((s) => s != null && s.trim().isNotEmpty)
          .join(' ');
    }

    final res = await _supabase.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );

    // Apple adı yalnızca ilk girişte verir; varsa meta veriye kaydet
    // (kullanıcı adı önerisi için kullanılır).
    final given = credential.givenName;
    final family = credential.familyName;
    if (given != null && given.trim().isNotEmpty) {
      final fullName = [given, family]
          .where((s) => s != null && s.trim().isNotEmpty)
          .join(' ');
      try {
        await _supabase.auth.updateUser(UserAttributes(data: {'full_name': fullName}));
      } catch (_) {}
    }

    return res;
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  Future<void> resetPassword(String email) async {
    await _supabase.auth.resetPasswordForEmail(email);
  }

  /// Kullanıcının profiles tablosunda tanımlı geçerli bir kullanıcı adı var mı?
  Future<bool> hasNickname(String userId) async {
    try {
      final res = await _supabase
          .from('profiles')
          .select('nickname')
          .eq('id', userId)
          .maybeSingle();
      if (res != null && res['nickname'] != null && (res['nickname'] as String).trim().isNotEmpty) {
        final nick = (res['nickname'] as String).trim();

        // Apple "E-postamı gizle" ile gelen kullanıcılarda veritabanı, takma adı
        // gizli e-postanın rastgele ön ekinden üretmiş olabilir -> geçerli sayma.
        final email = currentUser?.email?.toLowerCase();
        if (email != null && email.contains('privaterelay.appleid.com')) {
          final prefix = email.split('@').first;
          if (nick.toLowerCase() == prefix || _slugify(nick) == _slugify(prefix)) {
            return false;
          }
        }
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Kullanıcı adı kullanılabilir mi kontrol et (çakışma var mı)
  Future<bool> isNicknameAvailable(String nickname, {String? currentUserId}) async {
    try {
      final query = _supabase
          .from('profiles')
          .select('id')
          .ilike('nickname', nickname.trim());
      
      final check = await query.maybeSingle();
      if (check == null) return true;
      if (currentUserId != null && check['id'] == currentUserId) return true;
      return false;
    } catch (_) {
      return true;
    }
  }

  /// Kullanıcı adını profiles tablosuna kaydet / güncelle
  Future<void> saveNickname(String nickname) async {
    final user = currentUser;
    if (user == null) throw const AuthException('Kullanıcı oturumu bulunamadı.');

    final trimmed = nickname.trim();
    if (trimmed.isEmpty) throw const AuthException('Kullanıcı adı boş olamaz.');

    final available = await isNicknameAvailable(trimmed, currentUserId: user.id);
    if (!available) {
      throw const AuthException('Bu kullanıcı adı zaten alınmış.');
    }

    await _supabase.from('profiles').upsert({
      'id': user.id,
      'nickname': trimmed,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  /// Google veya E-posta meta verisinden otomatik temiz kullanıcı adı önerisi üret
  String generateSuggestedNickname() {
    final user = currentUser;
    if (user == null) return 'kesifci_${DateTime.now().millisecondsSinceEpoch % 1000}';

    final metaName = _pendingAppleName ??
        user.userMetadata?['full_name'] as String? ??
        user.userMetadata?['name'] as String?;
    if (metaName != null && metaName.trim().isNotEmpty) {
      final cleaned = _slugify(metaName);
      if (cleaned.length >= 3) return cleaned;
    }

    // Apple'ın gizli (relay) e-posta adresi anlamsız bir öneri üretir, kullanma
    final email = user.email;
    if (email != null &&
        email.contains('@') &&
        !email.toLowerCase().contains('privaterelay.appleid.com')) {
      final emailPrefix = email.split('@').first;
      final cleaned = _slugify(emailPrefix);
      if (cleaned.length >= 3) return cleaned;
    }

    return 'kesifci_${user.id.substring(0, 4)}';
  }

  static String _slugify(String input) {
    var result = input.trim().toLowerCase();
    const trMap = {
      'ç': 'c', 'ğ': 'g', 'ı': 'i', 'i': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u',
      'Ç': 'c', 'Ğ': 'g', 'İ': 'i', 'Ö': 'o', 'Ş': 's', 'Ü': 'u',
    };
    trMap.forEach((key, value) {
      result = result.replaceAll(key, value);
    });
    result = result.replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    result = result.replaceAll(RegExp(r'_+'), '_');
    result = result.replaceAll(RegExp(r'^_|_$'), '');
    return result;
  }
}
