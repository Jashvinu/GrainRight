import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return web;
    }
  }

  static const web = FirebaseOptions(
    apiKey: 'AIzaSyDUtCog-IIzfSo4Rl0QObZUANNskcaPwiY',
    appId: '1:590561808882:web:c6650fcef94594db701b6b',
    messagingSenderId: '590561808882',
    projectId: 'milletsnow-eae4f',
    authDomain: 'milletsnow-eae4f.firebaseapp.com',
    storageBucket: 'milletsnow-eae4f.firebasestorage.app',
    measurementId: 'G-PSY6X3CH4V',
  );

  static const android = FirebaseOptions(
    apiKey: 'AIzaSyBEyDj_dItLzlD_dQzGP_u1eMM_ZsLciig',
    appId: '1:590561808882:android:27f447bbc85ea7b0701b6b',
    messagingSenderId: '590561808882',
    projectId: 'milletsnow-eae4f',
    storageBucket: 'milletsnow-eae4f.firebasestorage.app',
  );

  static const ios = FirebaseOptions(
    apiKey: 'AIzaSyDjZbHYoj4EUrjPd0S2F_zWdxf8ggNvGmk',
    appId: '1:590561808882:ios:a654b7a6f0045322701b6b',
    messagingSenderId: '590561808882',
    projectId: 'milletsnow-eae4f',
    storageBucket: 'milletsnow-eae4f.firebasestorage.app',
  );
}
