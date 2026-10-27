/// The Android package channel embedded at build time.
///
/// Keeping this value in the binary prevents an ARM64 install from silently
/// switching to the universal channel (or vice versa) during an in-app update.
const String installedApkVariant = String.fromEnvironment(
  'ANIDASH_APK_VARIANT',
  defaultValue: 'universal',
);

dynamic selectAndroidApkAsset(List<dynamic> assets) {
  bool isApk(dynamic asset) =>
      asset is Map &&
      asset['name']?.toString().toLowerCase().endsWith('.apk') == true;

  bool matches(dynamic asset, String variant) {
    if (!isApk(asset)) return false;
    final name = asset['name'].toString().toLowerCase();
    return switch (variant) {
      'arm64-v8a' => name.contains('arm64-v8a') || name.contains('arm64'),
      'armeabi-v7a' => name.contains('armeabi-v7a') || name.contains('armv7'),
      'x86_64' => name.contains('x86_64'),
      _ => name.contains('universal'),
    };
  }

  for (final asset in assets) {
    if (matches(asset, installedApkVariant)) return asset;
  }

  // A matching architecture may safely fall back to the universal APK, but
  // never to a different architecture-specific package.
  for (final asset in assets) {
    if (matches(asset, 'universal')) return asset;
  }

  // General fallback: if neither variant nor universal is found, fallback to arm64 or any valid APK
  for (final asset in assets) {
    if (matches(asset, 'arm64-v8a')) return asset;
  }
  for (final asset in assets) {
    if (isApk(asset)) return asset;
  }
  return null;
}
