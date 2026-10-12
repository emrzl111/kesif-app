import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../services/auth_service.dart';

/// "Apple ile Devam Et" butonu.
///
/// Yalnızca iOS'ta görünür (Android'de boş bir widget döner).
/// App Store Kural 4.8: Google gibi 3. taraf girişi sunan uygulamalar
/// Apple ile girişi de sunmalıdır.
///
/// Giriş başarılı olunca oturum değişikliğini main.dart'taki auth state
/// dinleyicisi yakalar (Google ile aynı akış).
class AppleSignInButton extends StatefulWidget {
  /// Giriş sürerken diğer butonların da kilitlenebilmesi için üst widget'a haber verir.
  final ValueChanged<bool>? onLoadingChanged;
  final bool disabled;

  const AppleSignInButton({super.key, this.onLoadingChanged, this.disabled = false});

  /// Bu platformda buton gösterilmeli mi?
  static bool get isSupported => !kIsWeb && Platform.isIOS;

  @override
  State<AppleSignInButton> createState() => _AppleSignInButtonState();
}

class _AppleSignInButtonState extends State<AppleSignInButton> {
  bool _busy = false;

  Future<void> _signIn() async {
    setState(() => _busy = true);
    widget.onLoadingChanged?.call(true);
    try {
      await AuthService().signInWithApple();
    } on SignInWithAppleAuthorizationException catch (e) {
      // Kullanıcı vazgeçtiyse sessizce geç
      if (e.code != AuthorizationErrorCode.canceled && mounted) {
        _showError();
      }
    } catch (_) {
      if (mounted) _showError();
    } finally {
      if (mounted) setState(() => _busy = false);
      widget.onLoadingChanged?.call(false);
    }
  }

  void _showError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Apple ile giriş yaparken bir hata oluştu.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!AppleSignInButton.isSupported) return const SizedBox.shrink();

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton(
        onPressed: (widget.disabled || _busy) ? null : _signIn,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.apple, color: Colors.black, size: 26),
            const SizedBox(width: 10),
            Text(
              _busy ? 'Bağlanıyor...' : 'Apple ile Devam Et',
              style: const TextStyle(
                color: Colors.black,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
