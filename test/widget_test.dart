import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ani_dash/main.dart' as app;

void main() {
  testWidgets('AniDash application root renders', (tester) async {
    SharedPreferences.setMockInitialValues({'is_onboarded': false});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({'is_onboarded': false});
    app.sharedPrefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    await tester.pumpWidget(const ProviderScope(child: app.MyApp()));
    await tester.pump();

    expect(find.bySemanticsLabel('AniDash application'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The onboarding source-health probe has a nine-second network timeout.
    // Advance fake time so its defensive timer is settled before disposal.
    await tester.pump(const Duration(seconds: 10));
  });
}
