// Copyright (c) 2024 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:nim_chatkit/services/message/nim_chat_cache.dart';
import 'package:nim_core_v2/nim_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunxin_alog/yunxin_alog.dart';

import '../models/room_model.dart';
import '../services/room_service.dart';
import 'room_detail_page.dart';
import 'room_kit_service.dart';

/// 群聊课堂置顶横幅
///
/// 置于群聊页面顶部（通过 ChatUIConfig.topWidgetBuilder 注入），
/// 自动轮询该群进行中的课堂：
///   - 无课堂时：不显示（高度为 0）
///   - 1 个课堂时：直接显示一条横幅
///   - 多个课堂时：PageView 自动滚动轮播 + 小圆点指示器
///
/// 点击横幅 → 调用 RoomKitService.joinRoom() 以 member 角色进入课堂（可接收音视频）
class GroupRoomBanner extends StatefulWidget {
  /// NIM 群组 teamId（字符串形式）
  final String groupId;

  /// 后端轮询间隔（默认 30 秒）
  final Duration pollInterval;

  /// 多课堂轮播切换间隔（默认 4 秒）
  final Duration carouselInterval;

  const GroupRoomBanner({
    Key? key,
    required this.groupId,
    this.pollInterval = const Duration(seconds: 30),
    this.carouselInterval = const Duration(seconds: 4),
  }) : super(key: key);

  @override
  State<GroupRoomBanner> createState() => _GroupRoomBannerState();
}

class _GroupRoomBannerState extends State<GroupRoomBanner> {
  static const String _tag = 'GroupRoomBanner';

  final RoomService _roomService = RoomService();
  List<RoomModel> _rooms = [];
  bool _loading = true;
  bool _joining = false; // 防止重复点击

  Timer? _pollTimer;
  Timer? _carouselTimer;
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _fetchRooms();
    _pollTimer = Timer.periodic(widget.pollInterval, (_) => _fetchRooms());
  }

  @override
  void didUpdateWidget(covariant GroupRoomBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 群组 ID 发生变化时（从一个群聊切换到另一个），重新拉取课堂列表
    if (oldWidget.groupId != widget.groupId) {
      _pollTimer?.cancel();
      _carouselTimer?.cancel();
      setState(() {
        _rooms = [];
        _loading = true;
        _currentPage = 0;
      });
      _fetchRooms();
      _pollTimer = Timer.periodic(widget.pollInterval, (_) => _fetchRooms());
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _carouselTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _fetchRooms() async {
    try {
      final resp = await _roomService.getRoomsByGroupId(widget.groupId);
      if (!mounted) return;
      final rooms =
          resp.isSuccess ? (resp.data ?? <RoomModel>[]) : <RoomModel>[];
      setState(() {
        _rooms = rooms;
        _loading = false;
      });
      _updateCarouselTimer();
    } catch (e) {
      Alog.w(tag: 'GroupRoomBanner', content: 'fetchRooms error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _updateCarouselTimer() {
    _carouselTimer?.cancel();
    if (_rooms.length > 1) {
      _carouselTimer =
          Timer.periodic(widget.carouselInterval, (_) => _nextPage());
    }
  }

  void _nextPage() {
    if (!mounted || _rooms.isEmpty) return;
    final next = (_currentPage + 1) % _rooms.length;
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  /// 以学生（member）身份加入课堂
  ///
  /// 全程使用 State.mounted / State.context，避免 BuildContext 失效问题。
  Future<void> _joinRoom(RoomModel room) async {
    if (_joining) return; // 防止重复点击
    _joining = true;
    try {
      // 1. 后端原子性人数校验（+1）
      final joinResp = await _roomService.joinRoom(room.roomId);
      if (!joinResp.isSuccess) {
        Fluttertoast.showToast(msg: joinResp.msg);
        return;
      }

      // 2. 读取本地账号信息
      final prefs = await SharedPreferences.getInstance();
      final accid = prefs.getString('account') ?? '';
      final nickname =
          (prefs.getString('nickname')?.isNotEmpty == true)
              ? prefs.getString('nickname')!
              : '同学';
      final nimToken = prefs.getString('nim_im_token') ?? '';
      final roomToken = prefs.getString('room_token') ?? '';

      if (accid.isEmpty) {
        Fluttertoast.showToast(msg: '账号信息异常，请重新登录');
        await _roomService.leaveRoom(room.roomId); // 回滚人数
        return;
      }

      if (!mounted) return;

      // 3. 展示加载中 Dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            const Center(child: CircularProgressIndicator()),
      );

      // 4. 确保 NERoomKit 已登录
      final loginToken = roomToken.isNotEmpty ? roomToken : nimToken;
      final loginOk = await RoomKitService().ensureLogin(accid, loginToken);
      if (!loginOk) {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        await _roomService.leaveRoom(room.roomId);
        Fluttertoast.showToast(msg: 'NERoomKit 登录失败，请重试');
        return;
      }

      // 5. 判断当前用户在该群的角色：群主/管理员 → host（老师），其他 → member（学生）
      //
      // ⚠️ isOwner（控制是否调用 endRoom vs leaveRoom）与 joinRole（控制 NERoomKit 角色）要分开：
      //   • isOwner  = 当前用户是否为课堂的"房间创建者"（owner_accid），
      //               只有真正的房间创建者才能 endRoom()；群管理员非房间创建者时应 leaveRoom()。
      //   • joinRole = 基于群角色决定音视频权限（群主/管理员 → host，其他 → member）。
      bool isGroupOwnerOrAdmin = false;
      final groupId = room.groupId;
      if (groupId.isNotEmpty && groupId != '0') {
        try {
          final teamMember =
              await NIMChatCache.instance.getMyTeamMember(groupId);
          if (teamMember != null) {
            final role = teamMember.teamInfo.memberRole;
            isGroupOwnerOrAdmin =
                role == NIMTeamMemberRole.memberRoleOwner ||
                role == NIMTeamMemberRole.memberRoleManager;
          }
        } catch (e) {
          Alog.w(tag: 'GroupRoomBanner', content: 'getMyTeamMember 失败，默认 member: $e');
        }
      }

      // 是否为房间创建者（决定是否可以 endRoom()）
      final isRoomOwner = room.ownerAccid == accid;

      // NERoomKit 加入角色（决定音视频发布权限）
      // • 课堂创建者（isRoomOwner）→ 'host'（主持人，可 endRoom）
      // • 群主/管理员但非课堂创建者 → 'cohost'（联席主持人：有音视频权限，但不能 endRoom）
      // • 普通成员 → 'member'（仅听课）
      final String joinRole;
      if (isRoomOwner) {
        joinRole = 'host';
      } else if (isGroupOwnerOrAdmin) {
        joinRole = 'cohost';
      } else {
        joinRole = 'member';
      }

      Alog.d(
        tag: 'GroupRoomBanner',
        content: '进入课堂: groupId=$groupId joinRole=$joinRole '
            'isRoomOwner=$isRoomOwner ownerAccid=${room.ownerAccid} myAccid=$accid',
      );

      // 6. 加入 NERoom
      //
      // ⚠️ 不能用 'audience' 角色：
      //    audience 是直播 CDN 观看者，不进入 RTC 频道，joinRtcChannel() 会返回 code=30005，
      //    导致听不到/看不到老师音视频。
      //    'member'/'host' 角色才会正常加入 RTC 频道，并接收/发布音视频流。
      final roomContext = await RoomKitService().joinRoom(
        roomUuid: room.roomId,
        userName: nickname,
        role: joinRole,
      );

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // 关闭 loading

      if (roomContext == null) {
        final errCode = RoomKitService().lastJoinErrorCode;
        if (errCode == 1004) {
          // NERoom 侧该房间已不存在（可能已过期/被删除），通知后端将其标记为关闭
          try {
            await _roomService.notifyRoomGone(room.roomId);
            Alog.d(
                tag: _tag,
                content: '已通知后端关闭失效房间: ${room.roomId}');
          } catch (e) {
            Alog.e(
                tag: _tag,
                content: '通知后端关闭失效房间失败: $e');
          }
          if (mounted) {
            Fluttertoast.showToast(msg: '课堂已失效，老师需要重新创建课堂');
          }
          // 立即刷新横幅，移除已失效课堂
          _fetchRooms();
        } else {
          // 其他失败（网络/满员等），回滚人数后提示重试
          try {
            await _roomService.leaveRoom(room.roomId);
          } catch (_) {}
          if (mounted) {
            Fluttertoast.showToast(msg: '加入课堂失败，请重试');
          }
        }
        return;
      }

      // 7. 跳转到课堂页面
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RoomDetailPage(
            room: joinResp.data ?? room,
            isOwner: isRoomOwner,          // ✅ 只有课堂创建者才能 endRoom
            isTeacher: isGroupOwnerOrAdmin, // ✅ 群主/管理员（含创建者）显示音视频控制按钮
            roomContext: roomContext,
          ),
        ),
      );
    } catch (e) {
      Alog.e(tag: 'GroupRoomBanner', content: 'joinRoom error: $e');
      if (mounted) Fluttertoast.showToast(msg: '网络异常，请重试');
    } finally {
      _joining = false;
    }
  }

  // ─── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // 加载中或无课堂时不占空间
    if (_loading || _rooms.isEmpty) return const SizedBox.shrink();

    return Material(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 44,
            child: PageView.builder(
              controller: _pageController,
              itemCount: _rooms.length,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (_, i) => _BannerItem(
                room: _rooms[i],
                onTap: () => _joinRoom(_rooms[i]),
              ),
            ),
          ),
          // 多课堂时显示小圆点指示器
          if (_rooms.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _rooms.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _currentPage ? 12 : 6,
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: i == _currentPage
                          ? const Color(0xFF337EFF)
                          : const Color(0xFFD9D9D9),
                    ),
                  ),
                ),
              ),
            ),
          const Divider(height: 1, thickness: 0.5, color: Color(0xFFE8E8E8)),
        ],
      ),
    );
  }
}

/// 单条横幅 Item（纯展示，无业务逻辑）
class _BannerItem extends StatelessWidget {
  final RoomModel room;
  final VoidCallback onTap;

  const _BannerItem({Key? key, required this.room, required this.onTap})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final displayName = room.ownerNickname.isNotEmpty
        ? room.ownerNickname
        : room.roomName;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: const Color(0xFFFFF8E6), // 淡黄背景，醒目但不刺眼
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            const Icon(Icons.cast_for_education,
                size: 18, color: Color(0xFFFF8C00)),
            const SizedBox(width: 8),
            Expanded(
              child: RichText(
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF333333)),
                  children: [
                    const TextSpan(
                      text: '课堂：',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextSpan(text: displayName),
                    TextSpan(
                      text: '  ${room.currentMembers}人',
                      style: const TextStyle(color: Color(0xFF888888)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF337EFF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '进入',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
