import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Firebase client configuration generated from google-services.json & GoogleService-Info.plist
/// for project `zev-app-844ef` (Sender ID `557150004230`).
class DefaultFirebaseOptions {
  DefaultFirebaseOptions._();

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return android; // Safe fallback instead of crash
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyC93RFaZP68rcX_5GxRT4HY8a02XlviKpE',
    appId: '1:557150004230:web:bac688ed8bf4f51d33cf87',
    messagingSenderId: '557150004230',
    projectId: 'zev-app-844ef',
    authDomain: 'zev-app-844ef.firebaseapp.com',
    storageBucket: 'zev-app-844ef.firebasestorage.app',
    measurementId: 'G-6CB58SB5EL',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDMXc5s_L6DmkBxxYitxYbR-WrgD8aU_S8',
    appId: '1:557150004230:android:5d9e8501608c6d8933cf87',
    messagingSenderId: '557150004230',
    projectId: 'zev-app-844ef',
    storageBucket: 'zev-app-844ef.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDwPetWEBJrpR5im8mPs-yvcqi_fNIX8mM',
    appId: '1:557150004230:ios:5e7441bd05f98b6833cf87',
    messagingSenderId: '557150004230',
    projectId: 'zev-app-844ef',
    storageBucket: 'zev-app-844ef.firebasestorage.app',
    iosBundleId: 'com.zevapp.app',
  );
}
