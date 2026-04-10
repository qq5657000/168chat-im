// Copyright (c) 2024 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:nim_chatkit/repo/team_repo.dart';
import 'package:nim_chatkit/services/message/nim_chat_cache.dart';
import 'package:nim_core_v2/nim_core.dart';
import 'package:yunxin_alog/yunxin_alog.dart';

import 'group_service.dart';

/// 群组同步服务
///
/// 监听 NIM SDK 的群组相关事件，在事件发生时调用后端 `/api/yxgroup/sync`
/// 将最新的群信息和成员列表同步到 `fa_im_group` / `fa_im_group_member` 表。
///
/// 解决问题：群通过 NIM SDK 客户端直接创建/操作，未经过我们的 PHP 后端，
/// 导致 `fa_im_group` 和 `fa_im_group_member` 表为空，权限校验失败。
///
/// 策略：Flutter 端 NIM SDK 已有完整群信息，直接传给后端存库，
///       后端无需再调用 NIM 服务端 API，彻底避免 ope/权限 等 API 问题。
///
/// 使用方式：在 `home_page.dart` 的 `initState()` 中调用 `GroupSyncService().init()`
class GroupSyncService {
  static final GroupSyncService _instance = GroupSyncService._internal();
  factory GroupSyncService() => _instance;
  GroupSyncService._internal();

  static const String _tag = 'GroupSyncService';

  final GroupService _groupService = GroupService();
  final List<StreamSubscription> _subscriptions = [];
  bool _initialized = false;

  // ── 初始化入口 ────────────────────────────────────────────────────────────

  /// 启动群组同步服务（幂等，多次调用安全）
  void init() {
    if (_initialized) return;
    _initialized = true;

    Alog.d(tag: _tag, content: '群组同步服务启动');

    _listenTeamEvents();
    _doInitialSync();
  }

  /// 停止所有监听（通常不需要调用，服务生命周期与 App 相同）
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _initialized = false;
    Alog.d(tag: _tag, content: '群组同步服务已停止');
  }

  // ── NIM 事件监听 ──────────────────────────────────────────────────────────

  void _listenTeamEvents() {
    // 1. 我创建了群（或本地发现新群）
    _subscriptions.add(
      NimCore.instance.teamService.onTeamCreated.listen((NIMTeam team) {
        Alog.d(tag: _tag, content: 'onTeamCreated: ${team.teamId}');
        _syncTeamWithInfo(team);
      }),
    );

    // 2. 我被邀请加入了群
    _subscriptions.add(
      NimCore.instance.teamService.onTeamJoined.listen((NIMTeam team) {
        Alog.d(tag: _tag, content: 'onTeamJoined: ${team.teamId}');
        _syncTeamWithInfo(team);
      }),
    );

    // 3. 群信息有变化（名称/公告/头像/权限等）
    _subscriptions.add(
      NimCore.instance.teamService.onTeamInfoUpdated.listen((NIMTeam team) {
        Alog.d(tag: _tag, content: 'onTeamInfoUpdated: ${team.teamId}');
        _syncTeamWithInfo(team);
      }),
    );

    // 4. 群被解散
    _subscriptions.add(
      NimCore.instance.teamService.onTeamDismissed.listen((NIMTeam team) {
        Alog.d(tag: _tag, content: 'onTeamDismissed: ${team.teamId}');
        _syncDismissed(team.teamId);
      }),
    );

    // 5. 我退出或被踢出群
    _subscriptions.add(
      NimCore.instance.teamService.onTeamLeft.listen((teamLeft) {
        final teamId = teamLeft.team.teamId;
        Alog.d(tag: _tag, content: 'onTeamLeft: $teamId，同步最新状态');
        _syncTeamWithInfo(teamLeft.team);
      }),
    );

    // 6. 群通知消息：监听管理员增减（AddManager / RemoveManager）
    //
    // NIM 在群主设置/取消管理员时会推送一条 messageType=notification 的消息，
    // attachment.type = NIMMessageNotificationType.teamAddManager (增)
    //                  或 teamRemoveManager (减)
    // attachment.targetIds 为被修改角色的 accid 列表。
    _subscriptions.add(
      NimCore.instance.messageService.onReceiveMessages.listen((messages) {
        for (final msg in messages) {
          _handleManagerChangeNotification(msg);
        }
      }),
    );
  }

  /// 处理 AddManager / RemoveManager 群通知消息
  void _handleManagerChangeNotification(NIMMessage message) {
    final attachment = message.attachment;
    if (attachment is! NIMMessageNotificationAttachment) return;

    final isAdd =
        attachment.type == NIMMessageNotificationType.teamAddManager;
    final isRemove =
        attachment.type == NIMMessageNotificationType.teamRemoveManager;
    if (!isAdd && !isRemove) return;

    final targetIds = attachment.targetIds;
    if (targetIds == null || targetIds.isEmpty) return;

    final conversationId = message.conversationId;
    if (conversationId == null) return;

    // 从 conversationId 中提取群组 ID（格式：teamId|TEAM）
    NimCore.instance.conversationIdUtil
        .conversationTargetId(conversationId)
        .then((result) {
      if (!result.isSuccess || result.data == null) return;
      final teamId = result.data!;
      Alog.d(
        tag: _tag,
        content: 'admin change: team=$teamId '
            '${isAdd ? "ADD" : "REMOVE"} targetIds=$targetIds',
      );
      for (final accid in targetIds) {
        _groupService.setMemberAdmin(teamId, accid, isAdmin: isAdd);
      }
    });
  }

  // ── 初始同步（App 启动时同步所有已加入的群）────────────────────────────────

  void _doInitialSync() async {
    try {
      final result = await TeamRepo.getJoinedTeamList();
      if (!result.isSuccess || result.data == null) {
        Alog.w(tag: _tag, content: '初始同步：获取已加入群列表失败');
        return;
      }

      final teams = result.data!;
      Alog.d(tag: _tag, content: '初始同步：共 ${teams.length} 个群，开始逐一同步');

      for (final team in teams) {
        await _syncTeamWithInfo(team);
        await Future.delayed(const Duration(milliseconds: 200));
      }

      Alog.d(tag: _tag, content: '初始同步完成');
    } catch (e) {
      Alog.e(tag: _tag, content: '初始同步异常（已忽略）: $e');
    }
  }

  // ── 同步操作 ──────────────────────────────────────────────────────────────

  /// 同步单个群（携带 NIMTeam 完整信息，直接传给后端，无需后端再调 NIM API）
  ///
  /// 角色映射：
  ///   NIMTeamMemberRole.memberRoleOwner   → member_type=2 (群主)
  ///   NIMTeamMemberRole.memberRoleManager → member_type=1 (管理员)
  ///   其他                                → member_type=0 (普通成员)
  Future<void> _syncTeamWithInfo(NIMTeam team) async {
    try {
      final teamId = team.teamId;

      // 从 NIM SDK 本地缓存获取当前用户在该群的角色（无网络请求，极快）
      // member_type: 0=普通 1=管理员 2=群主
      int memberType = 0;
      try {
        final teamMember =
            await NIMChatCache.instance.getMyTeamMember(teamId);
        if (teamMember != null) {
          final role = teamMember.teamInfo.memberRole;
          if (role == NIMTeamMemberRole.memberRoleOwner) {
            memberType = 2;
          } else if (role == NIMTeamMemberRole.memberRoleManager) {
            memberType = 1;
          }
        }
      } catch (e) {
        // 获取角色失败时默认普通成员，不影响群信息同步
        Alog.w(tag: _tag, content: 'getMyTeamMember 失败，使用默认角色 0: $e');
      }

      await _groupService.syncGroup(
        teamId,
        ownerAccid: team.ownerAccountId,
        groupName: team.name,
        memberCount: team.memberCount,
        callerMemberType: memberType,
      );
    } catch (e) {
      Alog.w(tag: _tag, content: 'syncTeamWithInfo 失败（已忽略）: $e');
    }
  }

  /// 同步群解散事件
  Future<void> _syncDismissed(String teamId) async {
    try {
      await _groupService.syncGroupDismissed(teamId);
    } catch (e) {
      Alog.w(tag: _tag, content: 'syncDismissed 失败（已忽略）: $e');
    }
  }

  /// 手动触发单个群的同步（供外部调用，例如打开群聊时刷新）
  Future<void> syncTeamNow(String teamId) async {
    try {
      // 从本地缓存获取群信息（NIMTeamType.typeNormal = 高级群）
      final result = await TeamRepo.getTeamInfo(teamId, NIMTeamType.typeNormal);
      if (result != null) {
        await _syncTeamWithInfo(result);
      } else {
        // 降级：仅传 tid，让后端尝试其他方式
        await _groupService.syncGroup(teamId);
      }
    } catch (e) {
      Alog.w(tag: _tag, content: 'syncTeamNow 失败（已忽略）: $e');
    }
  }
}
