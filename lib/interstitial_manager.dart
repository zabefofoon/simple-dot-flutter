import 'dart:io';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/foundation.dart';

class InterstitialManager {
  InterstitialAd? _ad;
  bool _isLoading = false;
  VoidCallback? _onDismissed;

  // 테스트 전면 광고 단위 (Android/iOS)
  static String? get _unitId {
    if (Platform.isAndroid) {
      if (kDebugMode) {
        return 'ca-app-pub-3940256099942544/1033173712';
      } else {
        return 'ca-app-pub-5005353607231126/3229679789';
      }
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/4411468910';
    }
    return null;
  }

  bool get isReady => _ad != null;

  void load() {
    if (_isLoading || _ad != null) return;
    _isLoading = true;

    InterstitialAd.load(
      adUnitId: _unitId!,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _isLoading = false;
          _ad = ad;

          ad.setImmersiveMode(true);
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (_) {
              if (kDebugMode) debugPrint('Interstitial: shown');
            },
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _ad = null;
              // 다음 광고 미리 로드
              load();
              _onDismissed?.call();
              _onDismissed = null;
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _ad = null;
              load();
              _onDismissed?.call();
              _onDismissed = null;
            },
          );
        },
        onAdFailedToLoad: (err) {
          _isLoading = false;
          _ad = null;
          if (kDebugMode) {
            debugPrint('Interstitial load failed: ${err.code} ${err.message}');
          }
          // 잠시 후 재시도 로직을 직접 넣어도 좋습니다.
        },
      ),
    );
  }

  /// 광고가 있으면 보여주고 true, 없으면 false
  Future<bool> show({VoidCallback? onDismissed}) async {
    if (_ad == null) return false;
    _onDismissed = onDismissed;
    _ad!.show(); // fullScreenContentCallback에서 정리 & preload
    return true;
  }

  void dispose() => _ad?.dispose();
}
