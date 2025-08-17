import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

Future<String> _getOrCreateGaUserId() async {
  final prefs = await SharedPreferences.getInstance();
  const key = 'ga_user_id';

  // 이미 저장돼 있으면 재사용
  final existing = prefs.getString(key);
  if (existing != null) return existing;

  // 없으면 새로 만들고 저장
  final newId = const Uuid().v4(); // 예) e4c1c7fd-1d15-4e2a-a9e7-a9b9e1…
  await prefs.setString(key, newId);
  return newId;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

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
  DateTime? currentBackPressTime;
  final WebViewCookieManager cookieManager = WebViewCookieManager();
  bool _isWebPageLoaded = false;

  @override
  void initState() {
    super.initState();

    String os = Platform.isAndroid ? "android" : "ios";
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted) // JS 허용
      ..setBackgroundColor(const Color(0x000000ff)) // 투명 배경
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
                final jsResult = await _controller.runJavaScriptReturningResult('document.cookie');
                final raw = jsResult is String ? jsResult : jsResult.toString();
                final cookieHeader = raw.replaceAll(RegExp(r'^"|"$'), ''); // 양끝 " 제거
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('appCookies', cookieHeader);
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

        cookies.split(';').fold<List<Map<String, String>>>([], (acc,current) {
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
        }).forEach((map) {
          final key = map['key'];
          final value = map['value'];
          if (key != null && value != null) {
            cookieManager.setCookie(WebViewCookie(name: key, value: value, domain: '192.168.219.107'));
          }
        });

        _getOrCreateGaUserId().then((uuid) {
          _controller.loadRequest(
            Uri.parse(
              'http://192.168.219.107:3000/canvas?platform=$os&uid=$uuid&appVersion=$appVersion',
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
    } else {
      _webViewWidget = WebViewWidget(controller: _controller);
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

            SystemNavigator.pop();
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
