/// Uygulama yapılandırması
/// Anahtarlar derleme zamanında --dart-define ile inject edilir.
/// Örnek:
///   flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co
///               --dart-define=SUPABASE_ANON_KEY=eyJ...
///
/// CI/CD için android/local.properties veya GitHub Secrets kullanın.
class AppConfig {
  AppConfig._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '', // Boş bırakılırsa uygulama başlarken hata verir
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// Yapılandırmanın eksiksiz yüklendiğini doğrular.
  /// main() içinde başlangıçta çağrılmalıdır.
  static void validate() {
    assert(
      supabaseUrl.isNotEmpty,
      '\n\n❌ SUPABASE_URL tanımlanmamış!\n'
      'Çalıştırmak için:\n'
      '  flutter run --dart-define=SUPABASE_URL=<url> --dart-define=SUPABASE_ANON_KEY=<key>\n'
      'veya .vscode/launch.json içine ekleyin.\n',
    );
    assert(
      supabaseAnonKey.isNotEmpty,
      '\n\n❌ SUPABASE_ANON_KEY tanımlanmamış!\n'
      'Çalıştırmak için:\n'
      '  flutter run --dart-define=SUPABASE_URL=<url> --dart-define=SUPABASE_ANON_KEY=<key>\n',
    );
  }
}
