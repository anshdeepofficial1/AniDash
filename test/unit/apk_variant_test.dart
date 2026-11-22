import 'package:ani_dash/core/utils/apk_variant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default channel keeps universal updates on universal installs', () {
    final assets = <Map<String, String>>[
      {'name': 'AniDash-v2-arm64-v8a.apk', 'browser_download_url': 'arm64'},
      {'name': 'AniDash-v2-Universal.apk', 'browser_download_url': 'universal'},
    ];

    final selected = selectAndroidApkAsset(assets) as Map;
    expect(installedApkVariant, 'universal');
    expect(selected['browser_download_url'], 'universal');
  });

  test('never falls back to an incompatible architecture', () {
    final assets = <Map<String, String>>[
      {'name': 'AniDash-v2-arm64-v8a.apk', 'browser_download_url': 'arm64'},
      {'name': 'AniDash-v2-x86_64.apk', 'browser_download_url': 'x86'},
    ];

    expect(selectAndroidApkAsset(assets), isNull);
  });

  test('universal channel waits when a release has only ABI APKs', () {
    final assets = <Map<String, String>>[
      {'name': 'AniDash-v2-arm64-v8a.apk', 'browser_download_url': 'arm64'},
      {'name': 'AniDash-v2-armeabi-v7a.apk', 'browser_download_url': 'armv7'},
      {'name': 'AniDash-v2-x86_64.apk', 'browser_download_url': 'x86'},
    ];

    expect(installedApkVariant, 'universal');
    expect(selectAndroidApkAsset(assets), isNull);
  });
}
