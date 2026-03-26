import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Global sound service — call SoundService.init() once in main()
/// then SoundService.play('cart_add') or SoundService.play('beep') anywhere.
class SoundService {
  SoundService._();

  static final AudioPlayer _player = AudioPlayer();
  static bool _enabled = true;

  /// Call once in main() before runApp()
  static Future<void> init() async {
    // Ensure the player looks into the correct 'asset/' folder (not default 'assets/')
    AudioCache.instance.prefix = 'asset/';

    await AudioPlayer.global.setAudioContext(
      AudioContext(
        android: AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake:        false,
          contentType:      AndroidContentType.music,
          usageType:        AndroidUsageType.media,
          audioFocus:       AndroidAudioFocus.gainTransientMayDuck,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options:  const {AVAudioSessionOptions.mixWithOthers},
        ),
      ),
    );
  }

  static void setEnabled(bool val) => _enabled = val;

  static Future<void> play(String name) async {
    if (!_enabled) return;
    try {
      // No need to call stop() manually, play() handles it. 
      // This avoids potential race conditions where stop() might interfere with a quick play() call.
      await _player.play(AssetSource('sounds/$name.mp3'), volume: 1.0);
    } catch (e) {
      debugPrint('[SoundService] play error: $e');
    }
  }

  static Future<void> dispose() async => _player.dispose();
}