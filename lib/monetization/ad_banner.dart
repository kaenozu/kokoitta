import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../app_theme.dart';
import 'ad_config.dart';

/// A failure-safe banner: unavailable ads leave the free app usable.
class MonetizationBanner extends StatefulWidget {
  const MonetizationBanner({super.key});

  @override
  State<MonetizationBanner> createState() => _MonetizationBannerState();
}

class _MonetizationBannerState extends State<MonetizationBanner> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _disposed = false;

  bool get _supportsAds =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    if (_supportsAds) _loadAd();
  }

  void _loadAd() {
    final ad = BannerAd(
      adUnitId: AdConfig.bannerId,
      size: AdSize.banner,
      request: const AdRequest(nonPersonalizedAds: true),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted || _disposed) {
            _disposeAd(ad);
            return;
          }
          setState(() {
            _ad = ad as BannerAd;
            _loaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          _disposeAd(ad);
        },
      ),
    );
    ad.load().catchError((_) {
      // Plugin/network failures are an expected fallback path. The notice
      // remains visible and the map/photo flow is never blocked.
      _disposeAd(ad);
    });
  }

  void _disposeAd(Ad ad) {
    unawaited(ad.dispose().catchError((_) {}));
  }

  @override
  void dispose() {
    _disposed = true;
    final ad = _ad;
    if (ad != null) _disposeAd(ad);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      key: const ValueKey<String>('monetization-banner'),
      color: colors.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(KokoittaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '広告で無料提供を続けています',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: KokoittaSpacing.xs),
            const Text('写真の追加や地図の利用は無料です。広告が読み込めない場合もそのまま使えます。'),
            if (_loaded && _ad != null) ...<Widget>[
              const SizedBox(height: KokoittaSpacing.sm),
              Center(
                child: SizedBox(
                  width: _ad!.size.width.toDouble(),
                  height: _ad!.size.height.toDouble(),
                  child: AdWidget(ad: _ad!),
                ),
              ),
            ],
            const SizedBox(height: KokoittaSpacing.xs),
            Text(
              '個人に合わせた広告は使用せず、同意なく写真や位置情報を広告へ渡しません。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
