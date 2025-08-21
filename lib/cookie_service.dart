import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

class CookieService {
  Future<void> saveCookie(String jsCookieString) async {
    final cookieHeader = jsCookieString.replaceAll(
      RegExp(r'^"|"$'),
      '',
    ); // 양끝 " 제거
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('appCookies', cookieHeader);
  }

  Future<List<Map<String, String>>> loadCookie() async {
    final prefs = await SharedPreferences.getInstance();
    final String cookies = prefs.getString('appCookies') ?? '';
    return cookies.split(';').fold<List<Map<String, String>>>([], (
      acc,
      current,
    ) {
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
    });
  }

  applyCookies(WebViewCookieManager cookieManager) async {
    List<Map<String, String>> cookies = await loadCookie();
    for (var map in cookies) {
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
    }
  }
}
