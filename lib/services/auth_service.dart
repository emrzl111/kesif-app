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
          'email': email.trim(),
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
      'email': user.email,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  /// Google veya E-posta meta verisinden otomatik temiz kullanıcı adı önerisi üret
  String generateSuggestedNickname() {
    final user = currentUser;
    if (user == null) return 'kesifci_${DateTime.now().millisecondsSinceEpoch % 1000}';

    final metaName = user.userMetadata?['full_name'] as String? ?? 
                     user.userMetadata?['name'] as String?;
    if (metaName != null && metaName.trim().isNotEmpty) {
      final cleaned = _slugify(metaName);
      if (cleaned.length >= 3) return cleaned;
    }

    if (user.email != null && user.email!.contains('@')) {
      final emailPrefix = user.email!.split('@').first;
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
