import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Platforma göre Firebase yapılandırması.
///
/// - Android: null döner → android/app/google-services.json kullanılır.
/// - iOS: değerler ios/Runner/GoogleService-Info.plist dosyasından alınmıştır.
///   Kod içinde verildiği için plist'in Xcode projesine eklenmesi gerekmez
///   (Windows + Codemagic ile derlerken Xcode kullanılamıyor).
///
/// Not: Bu değerler gizli değildir; her Firebase istemci uygulamasına gömülür.
class DefaultFirebaseOptions {
  DefaultFirebaseOptions._();

  static FirebaseOptions? get currentPlatform {
    if (kIsWeb) return null;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return ios;
      default:
        return null;
    }
  }

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDEGKcpoIbW5CcKARIuD8KhIjStY61gCHM',
    appId: '1:563269087218:ios:d17f4101d31c9f5123456b',
    messagingSenderId: '563269087218',
    projectId: 'kesif-92b61',
    storageBucket: 'kesif-92b61.firebasestorage.app',
    iosBundleId: 'com.kesif.kesifApp',
  );
}
