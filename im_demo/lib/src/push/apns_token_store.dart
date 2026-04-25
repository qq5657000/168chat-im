import 'dart:typed_data';

/// iOS APNs device token，由 [MainApp] 从原生 MethodChannel 写入。
/// 任意登录路径成功后需调用 [NimCore.instance.apnsService.updateApnsToken] 上报云信。
class ApnsTokenStore {
  static Uint8List? value;
}
