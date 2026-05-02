import 'dart:typed_data';

/// iOS APNs device token，由 [MainApp] 从原生 MethodChannel 写入。
/// 任意登录路径成功后需调用 [NimCore.instance.apnsService.updateApnsToken] 上报云信。
///
/// [lastUpdateSummary] 供「关于」页展示，无 Xcode 时也可截图发给支持人员。
class ApnsTokenStore {
  static Uint8List? value;

  /// 最近一次上报云信的结果摘要（成功/失败 + code）。
  static String lastUpdateSummary = '尚未上报';

  /// 设备 token 十六进制预览（前 24 字符 + …）。
  static String get tokenPreview {
    final v = value;
    if (v == null || v.isEmpty) return '（未收到）';
    final hex =
        v.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
    if (hex.length <= 24) return hex;
    return '${hex.substring(0, 24)}…';
  }

  static String get fullTokenHex {
    final v = value;
    if (v == null || v.isEmpty) return '';
    return v.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
  }

  static void recordUpdateResult(
      {required bool success, int? code, String? details}) {
    lastUpdateSummary =
        success ? '成功 code=${code ?? 0}' : '失败 code=$code ${details ?? ''}';
  }
}
