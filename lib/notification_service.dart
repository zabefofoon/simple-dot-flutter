import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalPush {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // Android 8.0+ 채널
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'high_importance', // 고유 ID
    'High Importance Notifications',
    description: 'Foreground FCM notifications',
    importance: Importance.high,
  );

  static final _tapController = StreamController<String>.broadcast();

  static Stream<String> get taps => _tapController.stream;

  static Future<void> init() async {
    // 초기화 (아이콘은 @mipmap/ic_launcher 사용, 필요시 커스텀 가능)
    const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        if (payload != null && payload.isNotEmpty) {
          _tapController.add(payload);
        }
      },
      onDidReceiveBackgroundNotificationResponse:
          notificationTapBackground, // 선택
    );

    // Android 채널 생성
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);
  }

  // 포그라운드에서 FCM 수신 시 로컬 알림 표시
  static Future<void> showFromMessage(RemoteMessage m) async {
    final notif = m.notification;
    final title = notif?.title ?? m.data['title'] ?? 'Notification';
    final body = notif?.body ?? m.data['body'] ?? '';
    final payload = (m.data['deep_link'] ?? m.data['url'] ?? '') as String;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/launcher_icon',
      ),
      iOS: const DarwinNotificationDetails(),
    );

    await _plugin.show(m.hashCode, title, body, details, payload: payload);
  }

  static String get _channelId => _channel.id;

  static String get _channelName => _channel.name;

  static String? get _channelDescription => _channel.description;
}

// (선택) 백그라운드 탭 콜백. 실제로는 시스템(Notification) → 앱 진입 흐름은
// FCM의 onMessageOpenedApp/getInitialMessage로 다루는 편이 낫습니다.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  final payload = response.payload;
  if (payload != null && payload.isNotEmpty) {
    // 앱이 살아나면 처리할 수 있도록 브로드캐스트하고 싶다면
    // Isolate comm 등 별도 설계가 필요. 보통은 생략합니다.
  }
}
