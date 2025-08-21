import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:justpixelstudio/cookie_service.dart';
import 'package:justpixelstudio/download_service.dart';
import 'package:justpixelstudio/firebase_message_service.dart';
import 'package:justpixelstudio/spinner_overlay.dart';
import 'package:justpixelstudio/uuid_manager_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'firebase_options.dart';
import 'interstitial_manager.dart';
import 'notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await MobileAds.instance.initialize();
  await LocalPush.init();
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
  CookieService cookieService = CookieService();
  bool _isWebPageLoaded = false;
  DownloaderService downloaderService = DownloaderService();
  UuidManagerService uuidManagerService = UuidManagerService();
  FirebaseMessageService firebaseMessageService = FirebaseMessageService();

  @override
  void initState() {
    super.initState();
    firebaseMessageService.init(
      onDeepLink: (url) async {
        // 알림 탭으로 들어온 URL을 WebView에서 열기
        await _controller.loadRequest(Uri.parse(url));
      },
    );

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
                cookieService.saveCookie(raw);
                break;
              case 'download': // ✅ 한 번에 받는 케이스
                await downloaderService.saveBase64File(
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

    () async {
      _setWebViewWidget();
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final appVersion = '${packageInfo.version}_${packageInfo.buildNumber}';
      await cookieService.applyCookies(cookieManager);
      String uuid = await uuidManagerService.getOrCreateGaUserId();
      _controller.loadRequest(
        Uri.parse(
          'https://justpixelstudio.netlify.app/canvas?platform=$os&uid=$uuid&appVersion=$appVersion',
        ),
      );
    }();
  }

  void _setWebViewWidget() {
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

            final shown = await _ads.show(
              onDismissed: () {
                SystemNavigator.pop(); // 광고 닫힌 뒤 종료
              },
            );

            // 광고가 준비 안되어 있으면 그냥 종료
            if (!shown) SystemNavigator.pop();
          },
          child: Stack(
            children: [_webViewWidget, if (!_isWebPageLoaded) SpinnerOverlay()],
          ),
        ),
      ),
    );
  }
}
