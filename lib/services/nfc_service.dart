import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nfc_manager/nfc_manager.dart';

/// NTAG / Type-2 tag 讀取。PoC 只取 UID，不寫卡。
class NfcService {
  /// 啟動一次 polling — 等學員把卡靠近，回傳 UID（hex string, uppercase, 冒號分隔）。
  /// 失敗 / cancel 回傳 null。
  static Future<String?> readUidOnce() async {
    final available = await NfcManager.instance.isAvailable();
    if (!available) {
      debugPrint('NFC not available on this device');
      return null;
    }

    final completer = Completer<String?>();

    await NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso14443}, // NTAG = ISO 14443 Type A
      onDiscovered: (NfcTag tag) async {
        try {
          final uid = _extractUid(tag);
          await NfcManager.instance.stopSession();
          if (!completer.isCompleted) completer.complete(uid);
        } catch (e) {
          await NfcManager.instance.stopSession(errorMessage: e.toString());
          if (!completer.isCompleted) completer.complete(null);
        }
      },
    );

    return completer.future;
  }

  /// 從 NfcTag 抓 UID。Android 走 nfca/mifareultralight；iOS 走 mifare。
  static String _extractUid(NfcTag tag) {
    final data = tag.data;

    // Android primary: NfcA tech 帶 identifier (NTAG = ISO 14443-3A)
    final nfca = data['nfca'] as Map?;
    if (nfca != null && nfca['identifier'] is List) {
      final bytes = (nfca['identifier'] as List).cast<int>();
      return _toHex(bytes);
    }

    // iOS Core NFC: NTAG21x 在 nfc_manager 對應 'mifare' (Mifare Ultralight family)
    // identifier 是 7-byte UID，欄位名同樣叫 identifier
    final mifare = data['mifare'] as Map?;
    if (mifare != null && mifare['identifier'] is List) {
      return _toHex((mifare['identifier'] as List).cast<int>());
    }

    // 其他常見 tech fallback (Android: mifareultralight/mifareclassic/ndef/isodep;
    //                       iOS:     iso7816/iso15693/feliCa)
    for (final k in [
      'mifareultralight', 'mifareclassic', 'ndef', 'isodep',
      'iso7816', 'iso15693', 'feliCa',
    ]) {
      final m = data[k] as Map?;
      if (m != null && m['identifier'] is List) {
        return _toHex((m['identifier'] as List).cast<int>());
      }
    }
    throw Exception('UID 抓不到，tag.data=$data');
  }

  static String _toHex(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(':');
}
