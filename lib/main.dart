import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'firebase_options.dart';
import 'interstitial_manager.dart';
import 'notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // TODO: 필요한 백그라운드 로직 (예: 로컬DB 저장, 로그 전송 등)
  debugPrint('BG message: ${message.messageId}');
}

const _downloadsChannel = MethodChannel('com.justpixel.studio/downloads');

Future<void> openDownloadsFolder() async {
  await _downloadsChannel.invokeMethod('openDownloads');
}

Future<String?> saveBase64ToDownloads({
  required String base64,
  required String
  filename, // 반드시 확장자 포함 (예: image.gif / archive.zip / data.json)
  required String
  mime, // 예: image/gif, image/png, application/zip, application/json
}) async {
  final bytes = base64Decode(base64);
  final uri = await _downloadsChannel.invokeMethod<String>('saveToDownloads', {
    'filename': filename,
    'mime': mime,
    'bytes': bytes,
  });
  return uri;
}

Future<String> _getOrCreateGaUserId() async {
  final prefs = await SharedPreferences.getInstance();
  const key = 'ga_user_id';

  // 이미 저장돼 있으면 재사용
  final existing = prefs.getString(key);
  if (existing != null) return existing;

  // 없으면 새로 만들고 저장
  final newId = const Uuid().v4(); // e4c1c7fd-1d15-4e2a-a9e7-a9b9e1…
  await prefs.setString(key, newId);
  return newId;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await MobileAds.instance.initialize();

  // 🔸 백그라운드 핸들러 등록
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // 🔸 iOS/웹 권한 요청(알림 표시 허용 팝업)
  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(); // iOS/웹용. Android 13+는 아래 별도 처리.

  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  messaging.getToken().then((token) {
    debugPrint(token);
  });

  if (Platform.isAndroid) {
    final sdkInt = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    if (sdkInt >= 33) {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        await Permission.notification.request();
      }
    }
  }

  // 🔸 앱 포그라운드 수신
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    debugPrint('FG message data: ${message.data}');
    if (message.notification != null) {
      await LocalPush.showFromMessage(message);
    }
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Just Pixel Studio',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.white),
      ),
      home: const WebPage(),
    );
  }
}

class WebPage extends StatefulWidget {
  const WebPage({super.key});

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  late final WebViewController _controller;
  late final WebViewWidget _webViewWidget;
  final _ads = InterstitialManager();
  bool _exiting = false;
  DateTime? currentBackPressTime;
  final WebViewCookieManager cookieManager = WebViewCookieManager();
  bool _isWebPageLoaded = false;

  @override
  void initState() {
    super.initState();

    _ads.load();

    String os = Platform.isAndroid ? "android" : "ios";
    _controller = WebViewController(onPermissionRequest: (req) => req.grant())
      ..setJavaScriptMode(JavaScriptMode.unrestricted) // JS 허용
      ..setBackgroundColor(Colors.transparent) // 투명 배경
      ..addJavaScriptChannel(
        'appChannel',
        onMessageReceived: (JavaScriptMessage message) async {
          try {
            final data = jsonDecode(message.message) as Map<String, dynamic>;

            switch (data['type']) {
              case "load":
                setState(() => _isWebPageLoaded = true);
                break;
              case 'updateCookies':
                final jsResult = await _controller.runJavaScriptReturningResult(
                  'document.cookie',
                );
                final raw = jsResult is String ? jsResult : jsResult.toString();
                final cookieHeader = raw.replaceAll(
                  RegExp(r'^"|"$'),
                  '',
                ); // 양끝 " 제거
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('appCookies', cookieHeader);
                break;
              case 'download': // ✅ 한 번에 받는 케이스
                await _saveBase64File(
                  base64: data['base64'],
                  filename: data['filename'],
                  mime: data['mime'],
                );
                break;
              case 'openUrl':
                final Uri url = Uri.parse(data['url']);
                await launchUrl(url);
                break;
              case 'showAd':
                final shown = await _ads.show();
                if (!shown) _ads.load();
                break;
            }
          } catch (e) {
            debugPrint('⚠️ JS message parse error: $e');
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            debugPrint('Start: $url');
            setState(() => _isWebPageLoaded = false);
          },
          onProgress: (progress) {
            debugPrint('Loading: $progress%');
          },
          onPageFinished: (url) async {
            debugPrint('Finish: $url');
          },
          onWebResourceError: (error) =>
              debugPrint('Error: ${error.description}'),
        ),
      );

    PackageInfo.fromPlatform().then((packageInfo) {
      final appVersion = '${packageInfo.version}_${packageInfo.buildNumber}';

      SharedPreferences.getInstance().then((prefs) {
        final String cookies = prefs.getString('appCookies') ?? '';

        cookies
            .split(';')
            .fold<List<Map<String, String>>>([], (acc, current) {
              List<String> parts = current.split("=");
              if (parts.length >= 2) {
                Map<String, String> map = {};
                final key = parts[0].trim();
                final value = parts.sublist(1).join('=').trim();
                map['key'] = key;
                map['value'] = value;
                acc.add(map);
              }

              return acc;
            })
            .forEach((map) {
              final key = map['key'];
              final value = map['value'];
              if (key != null && value != null) {
                cookieManager.setCookie(
                  WebViewCookie(
                    name: key,
                    value: value,
                    domain: 'justpixelstudio.netlify.app',
                  ),
                );
              }
            });

        _getOrCreateGaUserId().then((uuid) {
          _controller.loadRequest(
            Uri.parse(
              'https://justpixelstudio.netlify.app/canvas?platform=$os&uid=$uuid&appVersion=$appVersion',
            ),
          );
        });
      });
    });

    if (WebViewPlatform.instance is AndroidWebViewPlatform) {
      _webViewWidget = WebViewWidget.fromPlatformCreationParams(
        params: AndroidWebViewWidgetCreationParams(
          controller: _controller.platform,
          displayWithHybridComposition: true,
        ),
      );

      final androidCtrl = _controller.platform as AndroidWebViewController;
      androidCtrl.setOnShowFileSelector((params) async {
        final result = await FilePicker.platform.pickFiles(
          allowMultiple: params.mode == FileSelectorMode.openMultiple,
          type: FileType.any,
        );

        if (result == null) return <String>[];
        return result.files
            .map((f) => f.path)
            .whereType<String>()
            .map((p) => Uri.file(p).toString())
            .toList();
      });
    } else {
      _webViewWidget = WebViewWidget(controller: _controller);
    }
  }

  Future<void> _saveBase64File({
    required String base64,
    required String
    filename, // 확장자 포함: image.gif / data.json / image.png / archive.zip
    required String
    mime, // 예: image/gif, application/json, image/png, application/zip
  }) async {
    try {
      final uri = await saveBase64ToDownloads(
        base64: base64,
        filename: filename,
        mime: mime,
      );
      if (uri != null) {
        debugPrint('Saved to Downloads: $uri');
        // 원하면 바로 열기:
        openDownloadsFolder();
      } else {
        debugPrint('save returned null');
      }
    } catch (e) {
      debugPrint('save error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;

            if (await _controller.canGoBack()) {
              await _controller.goBack();
              return;
            }

            final now = DateTime.now();
            final shouldShowToast =
                currentBackPressTime == null ||
                now.difference(currentBackPressTime!) >
                    const Duration(seconds: 2);

            if (shouldShowToast) {
              setState(() => currentBackPressTime = now);
              return;
            }

            if (_exiting) return;
            _exiting = true;

            final shown = await _ads.show(onDismissed: () {
              SystemNavigator.pop(); // 광고 닫힌 뒤 종료
            });

            if (!shown) {
              // 광고가 준비 안되어 있으면 그냥 종료
              SystemNavigator.pop();
            }
          },
          child: Stack(
            children: [
              _webViewWidget,
              if (!_isWebPageLoaded)
                Container(
                  color: Colors.white,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/images/app_identify.png',
                        width: 80,
                        fit: BoxFit.cover,
                      ),
                      SizedBox(height: 12),
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.0,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
