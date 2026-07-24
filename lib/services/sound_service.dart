import 'package:audioplayers/audioplayers.dart';

/// 掃描成功音效（QR / NFC 共用同一段音檔）。
class SoundService {
  static final _player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);

  static Future<void> playScanSuccess() async {
    await _player.play(AssetSource('sounds/scan_success.mp3'));
  }
}
