import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:permission_handler/permission_handler.dart';

import 'firebase_options.dart';
import 'notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // TODO: 필요한 백그라운드 로직 (예: 로컬DB 저장, 로그 전송 등)
  debugPrint('BG message: ${message.messageId}');
}

class FirebaseMessageService {
  bool _initialized = false;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  Future<void> init({Future<void> Function(String url)? onDeepLink}) async {
    if (_initialized) return;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    await _messaging.requestPermission(); // iOS/웹용. Android 13+는 아래 별도 처리.
    if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        await Permission.notification.request();
      }
    }

    // 🔸 앱 포그라운드 수신
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      debugPrint('FG message data: ${message.data}');
      if (message.notification != null) {
        await LocalPush.showFromMessage(message);
      }
    });

    // 알림 탭(백그라운드 → 포그라운드)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      final url = (message.data['deep_link'] ?? message.data['url'])
          ?.toString();
      if (url != null && url.isNotEmpty) {
        await onDeepLink?.call(url);
      }
    });

    // 완전 종료 상태에서 시작
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      final url = (initial.data['deep_link'] ?? initial.data['url'])
          ?.toString();
      if (url != null && url.isNotEmpty) {
        await onDeepLink?.call(url);
      }
    }

    _initialized = true;
  }
}
