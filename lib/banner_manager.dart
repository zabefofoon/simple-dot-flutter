import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class BannerManager {
  BannerAd? _ad;

  /// 배너가 로드되어 렌더링 가능한지
  final ValueNotifier<bool> isReady = ValueNotifier(false);

  /// 배너를 화면에 보일지(표시/숨김)
  final ValueNotifier<bool> visible = ValueNotifier(false);

  /// 로드된 배너의 높이(px). bottom bar 높이 지정 용도
  final ValueNotifier<double> height = ValueNotifier(0);

  bool get _hasAd => _ad != null;

  /// 배너 로드 (Adaptive 권장)
  Future<void> load(BuildContext context, {bool useAdaptive = true}) async {
    // 이미 있으면 정리 후 재로드
    await dispose();

    String? adUnitId = 'ca-app-pub-5005353607231126/7829354058';
    if (Platform.isAndroid) {
      if (kDebugMode) {
        adUnitId = 'ca-app-pub-3940256099942544/6300978111';
      } else {
        adUnitId = 'ca-app-pub-5005353607231126/7829354058';
      }
    } else if (Platform.isIOS) {
      adUnitId = 'ca-app-pub-3940256099942544/2934735716';
    }

    AdSize size = AdSize.banner;

    if (useAdaptive) {
      // 화면 폭 기반 Anchored Adaptive
      final width = MediaQuery.of(context).size.width.truncate();
      final anchored =
          await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
      if (anchored != null) {
        size = anchored;
      }
    }

    _ad = BannerAd(
      adUnitId: adUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          height.value = size.height.toDouble();
          isReady.value = true;
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('Banner failed to load: $error');
          isReady.value = false;
          height.value = 0;
          ad.dispose();
          _ad = null;
        },
      ),
    );

    await _ad!.load();
  }

  /// 화면에 보이기
  void show() {
    visible.value = true;
  }

  /// 화면에서 숨기기
  void hide() {
    visible.value = false;
  }

  /// bottomNavigationBar에 바로 넣을 수 있는 위젯을 제공
  /// - isReady && visible 일 때만 AdWidget을 보여줌
  Widget buildBottomBar() {
    return ValueListenableBuilder<bool>(
      valueListenable: isReady,
      builder: (_, ready, __) {
        if (!ready || !_hasAd) return const SizedBox.shrink();
        return ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (_, v, __) {
            if (!v) return const SizedBox.shrink();
            return ValueListenableBuilder<double>(
              valueListenable: height,
              builder: (_, h, __) {
                if (h <= 0) return const SizedBox.shrink();
                return SizedBox(
                  height: h,
                  child: AdWidget(ad: _ad!),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> dispose() async {
    isReady.value = false;
    visible.value = false;
    height.value = 0;
    await _ad?.dispose();
    _ad = null;
  }
}
