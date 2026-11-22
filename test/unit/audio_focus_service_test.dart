import 'dart:async';

import 'package:ani_dash/core/services/audio_focus_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'shonenx/audio_focus';
  const codec = StandardMethodCodec();

  Future<void> sendNativeFocusEvent(String method) async {
    final completed = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channelName,
          codec.encodeMethodCall(MethodCall(method)),
          (_) => completed.complete(),
        );
    await completed.future;
  }

  tearDown(() {
    AudioFocusService().reset();
  });

  test('focus gain keeps resume pending while app is backgrounded', () async {
    var pauseRequests = 0;
    var resumeRequests = 0;
    var isForeground = false;

    AudioFocusService().initialize(
      onPauseRequested: () async {
        pauseRequests++;
        return true;
      },
      onResumeRequested: () async {
        resumeRequests++;
        return isForeground;
      },
    );

    await sendNativeFocusEvent('onAudioFocusLossTransient');
    expect(pauseRequests, 1);
    expect(AudioFocusService().isPausedByInterruption, isTrue);

    await sendNativeFocusEvent('onAudioFocusGain');
    expect(resumeRequests, 1);
    expect(
      AudioFocusService().isPausedByInterruption,
      isTrue,
      reason: 'background focus gain must not restart playback',
    );

    isForeground = true;
    await sendNativeFocusEvent('onAudioFocusGain');
    expect(resumeRequests, 2);
    expect(AudioFocusService().isPausedByInterruption, isFalse);
  });

  test('duplicate transient losses preserve the pending resume', () async {
    var playerWasPlaying = true;

    AudioFocusService().initialize(
      onPauseRequested: () async {
        final shouldResume = playerWasPlaying;
        playerWasPlaying = false;
        return shouldResume;
      },
      onResumeRequested: () async => false,
    );

    await sendNativeFocusEvent('onAudioFocusLossTransient');
    await sendNativeFocusEvent('onAudioFocusLossTransient');

    expect(AudioFocusService().isPausedByInterruption, isTrue);
  });
}
