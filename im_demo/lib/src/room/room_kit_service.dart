// Copyright (c) 2024 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'package:netease_roomkit/netease_roomkit.dart';
import 'package:yunxin_alog/yunxin_alog.dart';

/// 云信 NERoomKit 服务封装
///
/// 初始化顺序：
///   1. [initialize] —— 应用启动时调用一次
///   2. [login]      —— IM 登录成功后调用
///   3. [createRoom] / [joinRoom] —— 创建或加入房间
///
/// templateId 说明：
///   登录云信控制台 → 应用管理 → 你的应用 → 房间/互动直播 → 场景模板
///   找到模板 ID 填入 [_defaultTemplateId]。
///   默认值 76 是官方通用模板，若你的 AppKey 下没有该模板会报错，请修改。
class RoomKitService {
  static final RoomKitService _instance = RoomKitService._internal();
  factory RoomKitService() => _instance;
  RoomKitService._internal();

  bool _initialized = false;

  /// 最近一次 joinRoom / createRoom 失败的错误码（成功时为 0）。
  /// 供外部在 joinRoom 返回 null 后查询具体失败原因（如 1004=房间不存在）。
  int _lastJoinErrorCode = 0;
  int get lastJoinErrorCode => _lastJoinErrorCode;

  /// RTC 状态脏标记：退出房间后置 true，下次 ensureLogin() 时先 logout + login，
  /// 彻底重置 NERtc 引擎的 channel 会话，避免 joinRtcChannel() 返回 30004。
  /// ⚠️ 不在退出房间时立即 logout，以免断开底层 NIM IM 连接（影响群聊等 IM 功能）。
  bool _rtcNeedsReset = false;

  /// 标记 RTC 状态需要重置（在 leaveRoom / endRoom 完成后调用）
  void markRtcDirty() {
    _rtcNeedsReset = true;
    print('🔔 [RoomKitService] RTC 状态已标记为脏（下次加入房间前将重新登录以重置 NERtc 引擎）');
  }

  /// ⚠️ 模板 ID：来自控制台 → 房间组件模板管理
  /// 当前配置：13752 = 线上会议（在线办公/教学互动/音视频会议）
  ///   角色：host（主持人，全权限）、cohost（联席主持人）、member（成员）
  ///   创建房间者默认 host 角色，普通加入者使用 member 角色。
  /// 其他可选：语聊房=13695, 互动直播=13691
  static const int _defaultTemplateId = 13752;

  // ─── 初始化 ─────────────────────────────────────────────────────────────────

  /// 初始化 NERoomKit（应用启动时调用一次）
  Future<bool> initialize(String appKey) async {
    if (_initialized) {
      print('✅ [RoomKitService] NERoomKit 已初始化，跳过');
      return true;
    }
    print('🔧 [RoomKitService] 开始初始化 NERoomKit, appKey=${appKey.substring(0, 4)}...');
    try {
      final result = await NERoomKit.instance.initialize(
        NERoomKitOptions(appKey: appKey),
      );
      _initialized = result.isSuccess();
      print('${_initialized ? "✅" : "❌"} [RoomKitService] NERoomKit 初始化'
          '${_initialized ? "成功" : "失败"}: code=${result.code}, msg=${result.msg}');
      Alog.i(
        tag: 'RoomKitService',
        content: 'NERoomKit 初始化${_initialized ? "成功" : "失败"}: '
            'code=${result.code}, msg=${result.msg}',
      );
      return _initialized;
    } catch (e) {
      print('❌ [RoomKitService] NERoomKit 初始化异常: $e');
      Alog.e(tag: 'RoomKitService', content: 'NERoomKit 初始化异常: $e');
      return false;
    }
  }

  // ─── 认证 ────────────────────────────────────────────────────────────────────

  /// 登录 NERoomKit
  /// ⚠️ 必须在 IMKitClient.loginIMWithResult() 之前调用，否则 NIM SDK 单例被 nim_core_v2
  ///    占用后，NERoomKit 无法再建立独立认证，会返回 code=402 Token不正确。
  Future<bool> login(String account, String token) async {
    print('🔑 [RoomKitService] 开始登录 NERoomKit, account=$account');
    try {
      // 先退出旧会话（清理残留状态，避免 stale session 导致 402）
      try {
        final alreadyLoggedIn = await NERoomKit.instance.authService.isLoggedIn;
        if (alreadyLoggedIn) {
          print('🔄 [RoomKitService] 检测到已有 NERoomKit 会话，先退出再重新登录');
          await NERoomKit.instance.authService.logout();
        }
      } catch (_) {}

      final result =
          await NERoomKit.instance.authService.login(account, token);
      final ok = result.isSuccess();
      print('${ok ? "✅" : "❌"} [RoomKitService] NERoomKit 登录'
          '${ok ? "成功" : "失败"}: code=${result.code}, msg=${result.msg}');
      Alog.i(
        tag: 'RoomKitService',
        content: 'NERoomKit 登录${ok ? "成功" : "失败"}: '
            'account=$account, code=${result.code}, msg=${result.msg}',
      );
      return ok;
    } catch (e) {
      print('❌ [RoomKitService] NERoomKit 登录异常: $e');
      Alog.e(tag: 'RoomKitService', content: 'NERoomKit 登录异常: $e');
      return false;
    }
  }

  /// 退出登录 NERoomKit
  Future<void> logout() async {
    print('🚪 [RoomKitService] 退出 NERoomKit 登录');
    try {
      await NERoomKit.instance.authService.logout();
      Alog.i(tag: 'RoomKitService', content: 'NERoomKit 已退出登录');
    } catch (e) {
      print('❌ [RoomKitService] NERoomKit 退出登录异常: $e');
      Alog.e(tag: 'RoomKitService', content: 'NERoomKit 退出登录异常: $e');
    }
  }

  /// 当前是否已登录
  Future<bool> get isLoggedIn async {
    try {
      return await NERoomKit.instance.authService.isLoggedIn;
    } catch (_) {
      return false;
    }
  }

  /// 确保 NERoomKit 已登录。
  ///
  /// 若当前已登录且 RTC 状态干净，直接返回 true。
  /// 若 [_rtcNeedsReset]=true（上次退出房间后标记），先 logout 再 login，
  ///   彻底重置 NERtc 引擎 channel 会话（避免 joinRtcChannel 返回 30004）。
  ///   ⚠️ 此处 logout 在"进入新房间前"执行，不会影响 NIM IM 连接的正常使用。
  /// 若未登录，使用传入的 [account] 和 [token] 调用 [login] 并返回结果。
  ///
  /// 在调用 [createRoom] / [joinRoom] 前应先调用此方法。
  Future<bool> ensureLogin(String account, String token) async {
    final loggedIn = await isLoggedIn;

    // ── RTC 脏状态重置路径 ─────────────────────────────────────────────────────
    // 上次退出房间时调用了 markRtcDirty()，这里在进入新房间前执行 logout + login，
    // 彻底重置 NERtc 引擎内部 channel 状态（NIM IM 连接保持不变，因为 logout 是
    // NERoomKit 层面的操作，NIM SDK 的 IM 连接由 nim_core_v2 独立维护）。
    if (_rtcNeedsReset && loggedIn) {
      print('🔄 [RoomKitService] RTC 需要重置，执行 logout + login 清理 NERtc 引擎状态...');
      _rtcNeedsReset = false;
      try {
        await NERoomKit.instance.authService.logout();
        print('✅ [RoomKitService] NERoomKit logout 完成，重新登录中...');
      } catch (e) {
        print('⚠️ [RoomKitService] NERoomKit logout 异常（继续登录）: $e');
      }
      final ok = await login(account, token);
      if (ok) {
        print('✅ [RoomKitService] ensureLogin (RTC 重置) 成功');
      } else {
        print('❌ [RoomKitService] ensureLogin (RTC 重置) 失败，房间操作将无法进行');
      }
      return ok;
    }

    // ── 正常路径 ──────────────────────────────────────────────────────────────
    if (loggedIn) {
      print('✅ [RoomKitService] NERoomKit 已处于登录状态，跳过重新登录');
      return true;
    }
    print('🔑 [RoomKitService] NERoomKit 未登录，开始登录: account=$account');
    final ok = await login(account, token);
    if (ok) {
      print('✅ [RoomKitService] ensureLogin 成功');
    } else {
      print('❌ [RoomKitService] ensureLogin 失败，房间操作将无法进行');
    }
    return ok;
  }

  // ─── 房间操作 ─────────────────────────────────────────────────────────────────

  /// 创建并加入房间（房主身份）
  ///
  /// 内部流程：
  ///   1. 检查登录状态
  ///   2. 调用 [NERoomService.createRoom]（在 NERoom 侧开启房间会话）
  ///      ⚠️ 此时后端数据库已存有该 roomUuid（由 Flutter 生成并先写入后端）
  ///         SDK createRoom() 是唯一的 NERoom 资源创建来源，避免双重冲突→30005
  ///   3. 调用 [_joinRoomInternal] 以 host 角色加入并等待 RTC 自动建立
  Future<NERoomContext?> createRoom({
    required String roomUuid,
    required String roomName,
    required String userName,
  }) async {
    print('\n🏠 ========== NERoomKit 创建房间 ==========');
    print('🏠 [RoomKitService] roomUuid=$roomUuid, roomName=$roomName, userName=$userName');
    print('🏠 [RoomKitService] templateId=$_defaultTemplateId');

    // ⚠️ 同 joinRoom：以 isLoggedIn 为唯一门卫，兼容 Dart _initialized 陈旧的情况
    final loggedIn = await isLoggedIn;
    if (loggedIn && !_initialized) {
      print('⚠️ [RoomKitService] Dart 侧 _initialized=false 但原生 NERoomKit 已登录，自动修正');
      _initialized = true;
    }
    print('🔑 [RoomKitService] NERoomKit 登录状态: $loggedIn');
    if (!loggedIn) {
      print('❌ [RoomKitService] NERoomKit 未登录，无法创建房间');
      return null;
    }

    try {
      // ── 步骤1：SDK createRoom() → 在 NERoom 侧开启房间会话 ─────────────────
      // ⚠️ 后端不再调用 POST /neroom/v3/rooms，此 SDK 调用是唯一的 NERoom 创建入口
      //    只有 SDK createRoom() 后，其他人才能通过 joinRoom() 进入此房间
      print('📡 [RoomKitService] 调用 NERoomKit.createRoom...');
      final createResult = await NERoomKit.instance.roomService.createRoom(
        NECreateRoomParams(
          roomUuid: roomUuid,
          roomName: roomName,
          templateId: _defaultTemplateId,
        ),
        NECreateRoomOptions(
          enableChatroom: true, // 开启聊天室，isChatroomSupported 才为 true
          enableRtc: true,      // 确保 RTC 音视频可用
        ),
      );
      print('📡 [RoomKitService] createRoom 结果: '
          'isSuccess=${createResult.isSuccess()}, '
          'code=${createResult.code}, msg=${createResult.msg}');

      if (!createResult.isSuccess()) {
        print('❌ [RoomKitService] createRoom 失败: code=${createResult.code}, msg=${createResult.msg}');
        Alog.e(tag: 'RoomKitService', content: 'createRoom 失败: code=${createResult.code}');
        return null;
      }

      // ── 步骤2：joinRoom + 显式建立 RTC 连接 ────────────────────────────────
      // createRoom() 只是"开启房间会话"，并不自动加入 RTC。
      // joinRoom() 之后需要显式调用 joinRtcChannel() 才能建立音视频连接。
      // ⚠️ 旧版 30005 是因为后端 server API 与 SDK createRoom() 双重创建冲突；
      //    现在后端不再调 NERoom API，冲突消除，显式 joinRtcChannel() 正常工作。
      print('✅ [RoomKitService] 云信房间已开启，开始以 host 身份加入');
      return await _joinRoomInternal(
        roomUuid: roomUuid,
        userName: userName,
        role: 'host',
      );
    } catch (e, stack) {
      print('❌ [RoomKitService] 创建房间异常: $e');
      print('   StackTrace: $stack');
      Alog.e(tag: 'RoomKitService', content: '创建房间异常: $e');
      return null;
    }
  }

  /// 加入房间
  ///
  /// [roomUuid]  房间唯一标识（对应后端 room_id）
  /// [userName]  用户昵称（不能为空）
  /// [role]      加入角色，必须是模板中实际存在的角色名称。
  ///             模板 13756 的已知有效角色：'host'（主持人）、'audience'（参与者）
  ///             ⚠️ 'participant' 在模板 13756 中不存在，会报 code=1003 角色未定义
  ///             默认 'host'。
  Future<NERoomContext?> joinRoom({
    required String roomUuid,
    required String userName,
    String role = 'host',
  }) async {
    print('\n🚪 ========== NERoomKit 加入房间 ==========');
    print('🚪 [RoomKitService] roomUuid=$roomUuid, userName=$userName, role=$role');

    // ⚠️ 不单独用 _initialized 标志做门卫：App 重启后原生 NERoomKit 可能已在运行，
    //    但 Dart 侧单例的 _initialized 被重置为 false，导致误判"未初始化"。
    //    改为以 isLoggedIn（反映原生 SDK 真实状态）为唯一判断依据，
    //    若原生已运行则同时修正 Dart 侧标志。
    final loggedIn = await isLoggedIn;
    if (loggedIn && !_initialized) {
      print('⚠️ [RoomKitService] Dart 侧 _initialized=false 但原生 NERoomKit 已登录，自动修正');
      _initialized = true;
    }
    print('🔑 [RoomKitService] NERoomKit 登录状态: $loggedIn');
    if (!loggedIn) {
      print('❌ [RoomKitService] NERoomKit 未登录，无法加入房间（请检查登录流程）');
      return null;
    }

    try {
      return await _joinRoomInternal(
        roomUuid: roomUuid,
        userName: userName,
        role: role,
      );
    } catch (e, stack) {
      print('❌ [RoomKitService] 加入房间异常: $e');
      print('   StackTrace: $stack');
      Alog.e(tag: 'RoomKitService', content: '加入房间异常: $e');
      return null;
    }
  }

  /// 底层 joinRoom 调用
  ///
  /// 流程：
  ///   1. 调用 [NERoomService.joinRoom] 建立信令连接（获取 NERoomContext）
  ///   2. 若 [isInRtcChannel]=false，显式调用 [joinRtcChannel] 建立 RTC 音视频连接
  ///      ⚠️ 必须完成步骤2，否则 unmuteMyAudio/unmuteMyVideo 会返回 code=-1 "Not in rtc channel"
  Future<NERoomContext?> _joinRoomInternal({
    required String roomUuid,
    required String userName,
    required String role,
  }) async {
    print('📡 [RoomKitService] 调用 NERoomKit.joinRoom: role=$role, uuid=$roomUuid');

    // ── 步骤1：建立信令连接 ────────────────────────────────────────────────────
    final result = await NERoomKit.instance.roomService.joinRoom(
      NEJoinRoomParams(
        roomUuid: roomUuid,
        userName: userName,
        role: role,
      ),
      NEJoinRoomOptions(
        // 加入 RTC 时提前初始化音频设备（不发流，方便后续快速 unmute）
        enableMyAudioDeviceOnJoinRtc: true,
        autoSubscribeAudio: true,
      ),
    );

    print('📡 [RoomKitService] joinRoom 结果: '
        'isSuccess=${result.isSuccess()}, '
        'code=${result.code}, msg=${result.msg}');

    if (!result.isSuccess() || result.data == null) {
      _lastJoinErrorCode = result.code; // 记录错误码，供调用方判断
      print('❌ [RoomKitService] joinRoom 失败！');
      print('   code: ${result.code}');
      print('   msg:  ${result.msg}');
      _printJoinRoomErrorHint(result.code, result.msg);
      print('🏠 =========================================\n');
      Alog.e(
        tag: 'RoomKitService',
        content: '加入房间失败: code=${result.code}, msg=${result.msg}',
      );
      return null;
    }
    _lastJoinErrorCode = 0; // 成功时清零

    final roomContext = result.data!;

    // ── 诊断日志：打印房间属性和本端成员状态（帮助排查权限/静音问题）──────────────
    print('🔍 [RoomKitService] ===== 加入后诊断 =====');
    print('🔍 roomProperties   : ${roomContext.roomProperties}');
    print('🔍 localMember.role : ${roomContext.localMember.role.toJson()}');
    print('🔍 isAudioOn        : ${roomContext.localMember.isAudioOn}');
    print('🔍 isVideoOn        : ${roomContext.localMember.isVideoOn}');
    print('🔍 isInRtcChannel   : ${roomContext.localMember.isInRtcChannel}');
    print('🔍 ===================================');

    // ── 步骤2：等待 RTC 音视频连接建立 ──────────────────────────────────────────
    //
    // ⚠️ 对于 member 角色，直接调用 joinRtcChannel() 会返回 30004，
    //    且可能阻断 SDK 内部的自动 RTC 连接机制，导致音视频永久不可用。
    //    NERoomKit 会在 joinRoom() 之后异步自动建立 RTC 连接（不需要显式调用）。
    //
    // 策略：
    //   ① 轮询 isInRtcChannel，最多等待 4 秒（20 × 200ms）
    //   ② 若 4s 内 SDK 自动建立成功 → 直接使用
    //   ③ 若 4s 后仍未就绪（通常只有 host 角色需要显式加入）→ 显式调用一次
    //
    // ✅ 实测：member/cohost 角色由 SDK 自动处理，host 角色在 createRoom 后
    //    通常也在数百毫秒内自动就绪；极少数场景才需要显式 joinRtcChannel()。
    print('📡 [RoomKitService] joinRoom 后 isInRtcChannel=${roomContext.localMember.isInRtcChannel}');
    print('📡 [RoomKitService] 步骤2: 等待 SDK 建立 RTC 连接（轮询最多 4s）...');

    bool rtcJoined = roomContext.localMember.isInRtcChannel;
    for (int i = 0; i < 20 && !rtcJoined; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      rtcJoined = roomContext.localMember.isInRtcChannel;
      if (rtcJoined) {
        print('✅ [RoomKitService] RTC 频道已自动建立 (${(i + 1) * 200}ms)');
      }
    }

    if (!rtcJoined) {
      // 超时兜底：显式调用 joinRtcChannel()（对 host 角色有效）
      print('⏳ [RoomKitService] RTC 未自动建立，尝试显式 joinRtcChannel() 兜底...');
      try {
        final rtcResult = await roomContext.rtcController.joinRtcChannel();
        print('📡 [RoomKitService] 显式 joinRtcChannel: '
            'isSuccess=${rtcResult.isSuccess()}, '
            'code=${rtcResult.code}, msg=${rtcResult.msg}');
        if (rtcResult.isSuccess() || rtcResult.code == 30003) {
          print('✅ [RoomKitService] RTC 频道已建立（显式加入）');
          rtcJoined = true;
        } else {
          print('⚠️ [RoomKitService] 显式 joinRtcChannel 失败: code=${rtcResult.code}，音视频功能可能不可用');
          Alog.w(
            tag: 'RoomKitService',
            content: 'joinRtcChannel 显式失败: code=${rtcResult.code}, msg=${rtcResult.msg}',
          );
        }
      } catch (e) {
        print('⚠️ [RoomKitService] joinRtcChannel 异常: $e');
        Alog.w(tag: 'RoomKitService', content: 'joinRtcChannel 异常: $e');
      }
    }

    if (!rtcJoined) {
      print('❌ [RoomKitService] RTC 频道未能建立（4s 超时 + 显式调用均失败），音视频不可用');
    }

    print('✅ [RoomKitService] 加入房间成功: uuid=$roomUuid, role=$role');
    print('🏠 =========================================\n');
    Alog.i(
      tag: 'RoomKitService',
      content: '加入房间成功: uuid=$roomUuid, role=$role',
    );
    return roomContext;
  }


  /// 打印加入房间失败的排查提示
  void _printJoinRoomErrorHint(int code, String? msg) {
    switch (code) {
      case 404:
        print('   👉 房间不存在：该房间未在 NERoomKit 创建。'
            '请先由老师创建房间，学生再加入。');
        break;
      case 401:
      case 1000:
        print('   👉 未登录：NERoomKit 未成功登录。请检查登录流程中 login() 是否成功。');
        break;
      case 403:
        print('   👉 无权限：当前账号没有加入该房间的权限。');
        break;
      case 1004:
        print('   👉 房间不存在：该 roomUuid 在 NERoom 中未找到。'
            '可能原因：\n'
            '      a) 房间由旧模板创建，新模板 ID=$_defaultTemplateId 不匹配\n'
            '      b) 房间已过期或被删除\n'
            '      c) 请重新创建一个新房间');
        break;
      case 1019:
        print('   👉 房间已满员。');
        break;
      case 1020:
        print('   👉 房间已结束。');
        break;
      default:
        print('   👉 错误码 $code，msg: $msg');
        break;
    }
  }

  /// 错误码转中文（供 UI 展示）
  static String errorMessage(int code, String? msg) {
    switch (code) {
      case 404:
        return '房间不存在，请等待老师创建课堂';
      case 401:
      case 1000:
        return '登录状态异常，请重新登录';
      case 403:
        return '无权限进入该房间';
      case 1004:
        return '房间模板配置错误，请联系管理员';
      case 1019:
        return '房间人数已满';
      case 1020:
        return '房间已结束';
      default:
        return msg ?? '操作失败 (code: $code)';
    }
  }
}
