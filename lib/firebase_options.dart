import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Firebase client configuration generated from google-services.json & GoogleService-Info.plist
/// for project `zevapp-3c6b5` (Sender ID `467206192154`).
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
    apiKey: 'AIzaSyBwbaVJ_8LCkWlCZer5DfijbyCwYsBkckA',
    appId: '1:467206192154:web:3bfe5b870b675fc6fc25a3',
    messagingSenderId: '467206192154',
    projectId: 'zevapp-3c6b5',
    authDomain: 'zevapp-3c6b5.firebaseapp.com',
    storageBucket: 'zevapp-3c6b5.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBwbaVJ_8LCkWlCZer5DfijbyCwYsBkckA',
    appId: '1:467206192154:android:3bfe5b870b675fc6fc25a3',
    messagingSenderId: '467206192154',
    projectId: 'zevapp-3c6b5',
    storageBucket: 'zevapp-3c6b5.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBG6k76jkU_6tT6NUi4JY7DEs4lq5_QRkg',
    appId: '1:467206192154:ios:9a30149aa891ddc5fc25a3',
    messagingSenderId: '467206192154',
    projectId: 'zevapp-3c6b5',
    storageBucket: 'zevapp-3c6b5.firebasestorage.app',
    iosBundleId: 'com.zevapp.app',
  );
}
