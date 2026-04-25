// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:nim_chatkit/repo/config_repo.dart';
import 'package:nim_core_v2/nim_core.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nim_chatkit/im_kit_client.dart';

class IMDemoConfig {
  //云信IM appKey（通信云产品）
  static const AppKey = '2ac83f8ceec56302bec3d1fc6ec28a4a';

  /// 云信互动直播（NERoom/netease_roomkit）AppKey
  /// ⚠️ 与 IM AppKey 不同！需要在云信控制台「互动直播」产品中单独获取
  /// 控制台地址：https://app.netease.im → 互动直播 → 应用管理 → AppKey
  static const RoomAppKey = '2ac83f8ceec56302bec3d1fc6ec28a4a';

  //高德Android Key
  static const AMapAndroid = 'your amap android key';

  //高德IOS Key
  static const AMapIOS = 'your amap ios key';

  //高德Web服务端 Key，用于生成静态图
  static const AMapWeb = 'your amap web key';
}

class NIMSDKOptionsConfig {
  static Future<NIMSDKOptions?> getSDKOptions(String appKey,
      {NIMLoginInfo? loginInfo}) async {
    NIMSDKOptions? options;
    final enableCloudConversation = await IMKitClient.enableCloudConversation;
    if (Platform.isAndroid) {
      final directory = await getExternalStorageDirectory();
      NIMStatusBarNotificationConfig config =
          await loadStatusBarNotificationConfig();
      options = NIMAndroidSDKOptions(
        appKey: appKey,
        shouldSyncStickTopSessionInfos: true,
        enableTeamMessageReadReceipt: true,
        enableFcs: false,
        sdkRootDir: directory != null ? '${directory.path}/NIMFlutter' : null,
        notificationConfig: config,
        preLoadServers: true,
        shouldConsiderRevokedMessageUnreadCount: true,
        shouldSyncUnreadCount: true,
        enablePreloadMessageAttachment: true,
        enableV2CloudConversation: enableCloudConversation,
        mixPushConfig: _buildMixPushConfig(),
      );
      ConfigRepo.saveStatusBarNotificationConfig(config, saveToNative: false);
    } else if (Platform.isIOS) {
      final directory = await getApplicationDocumentsDirectory();
      options = NIMIOSSDKOptions(
        appKey: appKey,
        shouldSyncStickTopSessionInfos: true,
        enableTeamMessageReadReceipt: true,
        sdkRootDir: '${directory.path}/NIMFlutter',
        // 与云信控制台「iOS APNS P12推送证书」中的证书名称一致（例如 apns）
        apnsCername: 'apns',
        pkCername: '',
        shouldConsiderRevokedMessageUnreadCount: true,
        shouldSyncUnreadCount: true,
        enableTeamReceipt: true,
        enablePreloadMessageAttachment: true,
        enableV2CloudConversation: enableCloudConversation,
      );
    }
    return options;
  }

  static Future<NIMStatusBarNotificationConfig>
  //todo 设置Android通知栏点击跳转类
      loadStatusBarNotificationConfig() async {
    final config = await ConfigRepo.getStatusBarNotificationConfig();
    if (config == null) {
      return NIMStatusBarNotificationConfig(
          notificationEntranceClassName:
              'com.hestia.n168chat.app.flutter.im.MainActivity',
          notificationExtraType: NIMNotificationExtraType.jsonArrStr);
    } else {
      config.notificationEntranceClassName =
          'com.hestia.n168chat.app.flutter.im.MainActivity';
      config.notificationExtraType = NIMNotificationExtraType.jsonArrStr;
      return config;
    }
  }

  static NIMMixPushConfig? _buildMixPushConfig() {
    //todo Android推送配置，请这是自己的信息
    return NIMMixPushConfig(
      // xiaomi
      xmAppId: 'xmAppId',
      xmAppKey: 'xmAppKey',
      xmCertificateName: 'xmCertificateName',
      // huawei
      hwAppId: 'hwAppId',
      hwCertificateName: 'hwCertificateName',
      // meizu
      mzAppId: 'mzAppId',
      mzAppKey: 'mzAppKey',
      mzCertificateName: 'mzCertificateName',
      // fcm
      // fcmCertificateName: 'DEMO_FCM_PUSH',
      // vivo
      vivoCertificateName: 'vivoCertificateName',
      // oppo
      oppoAppId: 'oppoAppId',
      oppoAppKey: 'oppoAppKey',
      oppoAppSecret: 'oppoAppSecret',
      oppoCertificateName: 'oppoCertificateName',
    );
  }
}
