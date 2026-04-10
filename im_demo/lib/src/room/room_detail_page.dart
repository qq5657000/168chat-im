// Copyright (c) 2024 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:netease_common_ui/utils/color_utils.dart';
import 'package:netease_roomkit/netease_roomkit.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:yunxin_alog/yunxin_alog.dart';
import '../models/room_model.dart';
import '../services/room_service.dart';
import 'room_kit_service.dart';

/// 课堂内页面 —— 集成 NERoomKit
///
/// 接收父页面传入的 [NERoomContext]，使用 [NERoomContextProvider] 包裹
/// 子树，使 [NERoomUserVideoView] 可自动订阅/取消订阅视频流。
class RoomDetailPage extends StatefulWidget {
  final RoomModel room;

  /// 是否为课堂创建者（房主）。
  /// 只有 isOwner=true 才能调用 endRoom()，其他人只能 leaveRoom()。
  final bool isOwner;

  /// 是否拥有音视频控制权限（老师侧）。
  /// true  → 显示麦克风/摄像头/翻转按钮（群主/管理员，无论是否为课堂创建者）。
  /// false → 不显示音视频按钮（普通学生）。
  /// 注意：isOwner=true 时 isTeacher 自动等效为 true。
  final bool isTeacher;

  /// 由 CreateRoomPage / RoomListPage 传入的已建立的房间上下文
  final NERoomContext? roomContext;

  const RoomDetailPage({
    Key? key,
    required this.room,
    this.isOwner = false,
    this.isTeacher = false,
    this.roomContext,
  }) : super(key: key);

  @override
  State<RoomDetailPage> createState() => _RoomDetailPageState();
}

class _RoomDetailPageState extends State<RoomDetailPage> {
  NERoomContext? _roomContext;

  // 本地 A/V 状态
  bool _isMicOn = true;
  bool _isCameraOn = false; // 默认关摄像头节省流量
  bool _isSwitchingCamera = false; // 切换摄像头防抖标志

  // 远端成员列表
  List<NERoomMember> _remoteMembers = [];

  bool _isLeaving = false;


  // ─── GlobalKey 缓存：保持视频 View 状态跨布局切换 ──────────────────────────────
  // 使用 GlobalKey 而非 ValueKey，确保布局从单列变双列（或反之）时，
  // _RemoteVideoView / _LocalVideoView 的内部状态（渲染器、订阅）不因
  // 父级 Widget 树结构变化而被销毁重建。
  final Map<String, GlobalKey<_RemoteVideoViewState>> _remoteVideoGlobalKeys = {};
  GlobalKey<_LocalVideoViewState>? _localVideoGlobalKey;

  GlobalKey<_LocalVideoViewState> _getLocalVideoGlobalKey() {
    _localVideoGlobalKey ??= GlobalKey<_LocalVideoViewState>();
    return _localVideoGlobalKey!;
  }

  GlobalKey<_RemoteVideoViewState> _getRemoteVideoGlobalKey(int rtcUid) {
    return _remoteVideoGlobalKeys.putIfAbsent(
      rtcUid.toString(),
      () => GlobalKey<_RemoteVideoViewState>(),
    );
  }

  // ─── 聊天状态 ──────────────────────────────────────────────────────────────────
  final List<Map<String, dynamic>> _chatMessages = [];
  bool _isChatOpen = true; // 默认展开聊天覆盖层
  bool _isChatroomJoined = false; // 聊天室连接是否就绪
  final TextEditingController _chatInputController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  // ─── 事件回调 ─────────────────────────────────────────────────────────────────
  late final NERoomEventCallback _eventCallback;

  @override
  void initState() {
    super.initState();
    _roomContext = widget.roomContext;

    _eventCallback = NERoomEventCallback(
      // 成员加入房间
      memberJoinRoom: (List<NERoomMember> members) {
        if (mounted) setState(() => _refreshMembers());
      },
      // 成员离开房间
      memberLeaveRoom: (List<NERoomMember> members) {
        if (mounted) setState(() => _refreshMembers());
      },
      // 成员音频状态变化
      memberAudioMuteChanged: (NERoomMember member, bool mute, _) {
        if (mounted) setState(() => _refreshMembers());
      },
      // 成员视频状态变化
      memberVideoMuteChanged: (NERoomMember member, bool mute, _) {
        if (mounted) setState(() => _refreshMembers());
      },
      // 成员加入 RTC 频道（此时才能订阅其视频流）
      memberJoinRtcChannel: (List<NERoomMember> members) {
        if (mounted) setState(() => _refreshMembers());
      },
      // 成员离开 RTC 频道
      memberLeaveRtcChannel: (List<NERoomMember> members) {
        // 释放离开成员的 GlobalKey，避免内存泄漏
        for (final m in members) {
          final uid = m.rtcUid;
          if (uid != null) _remoteVideoGlobalKeys.remove(uid.toString());
        }
        if (mounted) setState(() => _refreshMembers());
      },
      // 成员加入聊天室（SDK 自动或手动加入后触发）
      memberJoinChatroom: (List<NERoomMember> members) {
        final uuids = members.map((m) => m.uuid).join(', ');
        print('💬 [RoomDetailPage] memberJoinChatroom 事件: [${uuids}]');
        final selfUuid = _roomContext?.localMember.uuid;
        if (!mounted) return;
        setState(() {
          for (final member in members) {
            if (member.uuid == selfUuid) {
              _isChatroomJoined = true;
              print('✅ [RoomDetailPage] 自己加入聊天室成功 (uuid=$selfUuid)');
            } else {
              // 其他成员入室 → 添加入室通知气泡
              _chatMessages.add({
                'type': 'join',
                'nick': member.name.isNotEmpty ? member.name : member.uuid,
              });
            }
          }
        });
        _scrollChatToBottom();
      },
      // 接收聊天室消息
      chatroomMessagesReceived: (List<NERoomChatMessage> messages) {
        if (!mounted) return;
        setState(() {
          for (final msg in messages) {
            // 跳过自己发送的消息（本地发送时已立即添加）
            if (msg.fromUserUuid == _roomContext?.localMember.uuid) continue;
            if (msg is NERoomChatTextMessage) {
              _chatMessages.add({
                'type': 'text',
                'nick': msg.fromNick.isNotEmpty
                    ? msg.fromNick
                    : msg.fromUserUuid,
                'text': msg.text,
                'isMe': false,
              });
            }
          }
        });
        _scrollChatToBottom();
      },
      // 房间结束（老师结束课堂 / 超时）
      // ⚠️ 当 host 自己调用 endRoom() 时，SDK 也会触发此事件。
      //    此时 _isLeaving=true，不再弹"课堂已结束"对话框，
      //    否则会与 _handleLeaveRoom 的 Navigator.pop 冲突导致页面无法退出。
      roomEnd: (NERoomEndReason reason, _) {
        Alog.w(tag: 'RoomDetailPage', content: '房间结束: ${reason.name}');
        if (_isLeaving) return; // 自己主动结束，跳过弹窗
        if (mounted) _showRoomEndedDialog();
      },
    );

    if (_roomContext != null) {
      _roomContext!.addEventCallback(_eventCallback);
      _syncInitialState();
      _joinChatroom();
    }

    Alog.i(
      tag: 'RoomDetailPage',
      content: '进入课堂: ${widget.room.roomId}, '
          '是否房主: ${widget.isOwner}, '
          'context: ${_roomContext != null ? "已连接" : "未连接"}',
    );
  }

  @override
  void dispose() {
    _roomContext?.removeEventCallback(_eventCallback);
    // ignore: unawaited_futures
    _roomContext?.chatController.leaveChatroom();
    _chatInputController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _syncInitialState() {
    setState(() {
      _refreshMembers();
      _isMicOn = _roomContext!.localMember.isAudioOn;
      _isCameraOn = _roomContext!.localMember.isVideoOn;
      // 如果 SDK 已自动加入聊天室，直接标记为就绪
      _isChatroomJoined = _roomContext!.localMember.isInChatroom;
      if (_isChatroomJoined) {
        print('✅ [RoomDetailPage] 初始化时聊天室已就绪 (isInChatroom=true)');
      }
      // isTeacher 由调用方（create_room_page / group_room_banner）直接传入，
      // 无需从 SDK role.name 推断（SDK 有时不能正确反映 cohost 角色）。
      if (widget.isTeacher && !widget.isOwner) {
        print('✅ [RoomDetailPage] 当前用户为协同老师（群管理员，非课堂创建者）');
      }
    });

    // ⚠️ SDK 在 joinRoom() 后可能异步填充远端成员的 rtcUid（已在 RTC 频道的成员）。
    //    延迟刷新确保 rtcUid 就绪后 _RemoteVideoView 能被正确创建并订阅视频流。
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _refreshMembers());
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _refreshMembers());
    });
  }

  void _refreshMembers() {
    _remoteMembers = List.from(_roomContext?.remoteMembers ?? []);
  }

  // ─── 聊天室 ────────────────────────────────────────────────────────────────────

  Future<void> _joinChatroom() async {
    if (_roomContext == null) return;

    // 诊断：聊天室是否被模板支持
    final isSupported = _roomContext!.chatController.isSupported;
    print('💬 [RoomDetailPage] chatController.isSupported=$isSupported');
    if (!isSupported) {
      print('⚠️ [RoomDetailPage] 聊天室功能未开启！创建房间时需设置 enableChatroom: true。');
      if (mounted) setState(() => _isChatOpen = false);
      return;
    }

    // ① 轮询等待 SDK 自动加入（最多 3 秒，每 500ms 检查一次）
    //    joinRoom 后 SDK 会异步建立聊天室连接；直接手动 join 会干扰这个过程
    print('💬 [RoomDetailPage] 等待 SDK 自动加入聊天室（最多 3s）...');
    for (int i = 0; i < 6; i++) {
      if (_roomContext!.localMember.isInChatroom) break;
      await Future.delayed(const Duration(milliseconds: 500));
    }

    final alreadyIn = _roomContext!.localMember.isInChatroom;
    print('💬 [RoomDetailPage] localMember.isInChatroom=$alreadyIn (等待结束后)');
    if (alreadyIn) {
      print('✅ [RoomDetailPage] SDK 已自动加入聊天室，跳过手动 joinChatroom()');
      if (mounted) setState(() => _isChatroomJoined = true);
      return;
    }

    // ② 3 秒后仍未自动加入，手动加入（最多重试 2 次）
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        print('💬 [RoomDetailPage] 手动加入聊天室（第 $attempt 次）...');
        final result = await _roomContext!.chatController.joinChatroom();
        print('💬 [RoomDetailPage] joinChatroom 第$attempt次: isSuccess=${result.isSuccess()}, code=${result.code}, msg=${result.msg}');

        if (result.isSuccess()) {
          if (mounted) setState(() => _isChatroomJoined = true);
          print('✅ [RoomDetailPage] 聊天室加入成功（第$attempt次）');
          return;
        } else {
          // 302 = NIM 鉴权失败 (token rotation 导致)；不视为成功，需等待 memberJoinChatroom 事件
          // 408 = 连接超时；等待后重试
          print('⚠️ [RoomDetailPage] joinChatroom 第$attempt次失败: code=${result.code}');
          if (attempt < 2) {
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      } catch (e) {
        print('⚠️ [RoomDetailPage] joinChatroom 第$attempt次异常: $e');
      }
    }
    print('⚠️ [RoomDetailPage] 聊天室手动加入失败，等待 memberJoinChatroom 事件...');
    // 不设 _isChatroomJoined=true；依赖 memberJoinChatroom 事件来标记就绪
  }

  Future<void> _sendChatMessage() async {
    final text = _chatInputController.text.trim();
    if (text.isEmpty || _roomContext == null) return;
    if (!_roomContext!.chatController.isSupported) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('聊天室未开启，请联系管理员在云信控制台开启模板聊天室功能')),
        );
      }
      return;
    }
    _chatInputController.clear();

    // 立即在本地显示（不等待服务器回调）
    final myNick = _roomContext!.localMember.name.isNotEmpty
        ? _roomContext!.localMember.name
        : _roomContext!.localMember.uuid;
    if (mounted) {
      setState(() {
        _chatMessages.add({'type': 'text', 'nick': myNick, 'text': text, 'isMe': true});
      });
      _scrollChatToBottom();
    }

    // 如果聊天室还未就绪（可能 memberJoinChatroom 事件还没到），等待最多 3 秒
    if (!_isChatroomJoined) {
      // 先检查本地属性
      if (_roomContext!.localMember.isInChatroom) {
        if (mounted) setState(() => _isChatroomJoined = true);
      } else {
        print('⏳ [RoomDetailPage] 聊天室未就绪，等待最多 3s...');
        for (int i = 0; i < 6 && !_isChatroomJoined; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (_roomContext!.localMember.isInChatroom && mounted) {
            setState(() => _isChatroomJoined = true);
          }
        }
      }
    }

    var result = await _roomContext!.chatController.sendBroadcastTextMessage(text);
    print('💬 [RoomDetailPage] sendMessage: isSuccess=${result.isSuccess()}, code=${result.code}, msg=${result.msg}');

    if (!result.isSuccess() && mounted) {
      // 从本地消息列表中移除刚才乐观添加的消息（发送真正失败）
      setState(() => _chatMessages.removeWhere(
        (m) => m['isMe'] == true && m['text'] == text,
      ));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败 (code=${result.code})，请稍后重试')),
      );
    }
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ─── 音视频控制 ───────────────────────────────────────────────────────────────

  /// 请求麦克风权限，返回是否已授权
  Future<bool> _ensureMicPermission() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;
    final result = await Permission.microphone.request();
    if (!result.isGranted) {
      print('❌ [RoomDetailPage] 麦克风权限被拒绝: $result');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('请授予麦克风权限以使用语音'),
            action: SnackBarAction(
              label: '去设置',
              onPressed: () => openAppSettings(),
            ),
          ),
        );
      }
      return false;
    }
    return true;
  }

  /// 请求摄像头权限，返回是否已授权
  Future<bool> _ensureCameraPermission() async {
    final status = await Permission.camera.status;
    if (status.isGranted) return true;
    final result = await Permission.camera.request();
    if (!result.isGranted) {
      print('❌ [RoomDetailPage] 摄像头权限被拒绝: $result');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('请授予摄像头权限以开启视频'),
            action: SnackBarAction(
              label: '去设置',
              onPressed: () => openAppSettings(),
            ),
          ),
        );
      }
      return false;
    }
    return true;
  }

  Future<void> _toggleMic() async {
    if (_roomContext == null) return;

    // 开麦时先确保有麦克风权限
    if (!_isMicOn) {
      final hasPermission = await _ensureMicPermission();
      if (!hasPermission) return;
    }

    var result = _isMicOn
        ? await _roomContext!.rtcController.muteMyAudio()
        : await _roomContext!.rtcController.unmuteMyAudio();

    print('🎤 [RoomDetailPage] toggleMic: '
        '${_isMicOn ? "静音" : "取消静音"} → '
        'isSuccess=${result.isSuccess()}, code=${result.code}, msg=${result.msg}');

    // 兜底：若 muteMyAudio/unmuteMyAudio 因角色权限返回 403，
    // 则尝试 muteMemberAudio/unmuteMemberAudio(自己UUID)
    if (result.code == 403) {
      final selfUuid = _roomContext!.localMember.uuid;
      print('⚠️ [RoomDetailPage] toggleMic 403，尝试 muteMemberAudio/unmuteMemberAudio(uuid=$selfUuid)');
      result = _isMicOn
          ? await _roomContext!.rtcController.muteMemberAudio(selfUuid)
          : await _roomContext!.rtcController.unmuteMemberAudio(selfUuid);
      print('🎤 [RoomDetailPage] 兜底结果: isSuccess=${result.isSuccess()}, code=${result.code}, msg=${result.msg}');
    }

    if (result.isSuccess()) {
      setState(() => _isMicOn = !_isMicOn);
    } else {
      Alog.e(
        tag: 'RoomDetailPage',
        content: 'toggleMic 失败: code=${result.code}, msg=${result.msg}',
      );
      if (mounted) {
        String hint;
        if (result.code == 403 || result.code == 1002) {
          hint = '无麦克风控制权限\n'
              '请到云信控制台→房间组件→场景模板→13756→编辑角色权限→开启"音视频控制"';
        } else {
          hint = '操作失败 (code=${result.code}): ${result.msg ?? ""}';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(hint),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// 切换前后摄像头（仅在摄像头已开启时有效）
  Future<void> _switchCamera() async {
    if (_roomContext == null || !_isCameraOn || _isSwitchingCamera) return;

    setState(() => _isSwitchingCamera = true);
    try {
      final result = await _roomContext!.rtcController.switchCamera();
      print('🔄 [RoomDetailPage] switchCamera: '
          'isSuccess=${result.isSuccess()}, code=${result.code}, msg=${result.msg}');
      if (!result.isSuccess() && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('切换摄像头失败 (code=${result.code})'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('⚠️ [RoomDetailPage] switchCamera 异常: $e');
    } finally {
      if (mounted) setState(() => _isSwitchingCamera = false);
    }
  }

  Future<void> _toggleCamera() async {
    if (_roomContext == null) return;

    // 开摄像头时先确保有相机权限，并检查上麦人数上限
    if (!_isCameraOn) {
      final hasPermission = await _ensureCameraPermission();
      if (!hasPermission) return;

      // 老师（isOwner）或 cohost 受最多 4 人上麦限制
      if (widget.isOwner || widget.isTeacher) {
        // 统计远端已开视频的人数（不依赖 role.name，见 _buildVideoArea 注释）
        final remoteTeachersOnVideo = _remoteMembers
            .where((m) => m.isVideoOn)
            .length;
        // 再加上自己（即将开启），总共会是 remoteTeachersOnVideo+1
        if (remoteTeachersOnVideo >= 4) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('最多 4 人同时上麦'),
                duration: Duration(seconds: 2),
              ),
            );
          }
          return;
        }
      }
    }

    var result = _isCameraOn
        ? await _roomContext!.rtcController.muteMyVideo()
        : await _roomContext!.rtcController.unmuteMyVideo();

    print('📷 [RoomDetailPage] toggleCamera: '
        '${_isCameraOn ? "关闭视频" : "开启视频"} → '
        'isSuccess=${result.isSuccess()}, code=${result.code}, msg=${result.msg}');

    // 兜底：若 muteMyVideo/unmuteMyVideo 因角色权限返回 403，
    // 则尝试 muteMemberVideo/unmuteMemberVideo(自己UUID)
    if (result.code == 403) {
      final selfUuid = _roomContext!.localMember.uuid;
      print('⚠️ [RoomDetailPage] toggleCamera 403，尝试 muteMemberVideo/unmuteMemberVideo(uuid=$selfUuid)');
      result = _isCameraOn
          ? await _roomContext!.rtcController.muteMemberVideo(selfUuid)
          : await _roomContext!.rtcController.unmuteMemberVideo(selfUuid);
      print('📷 [RoomDetailPage] 兜底结果: isSuccess=${result.isSuccess()}, code=${result.code}, msg=${result.msg}');
    }

    if (result.isSuccess()) {
      setState(() => _isCameraOn = !_isCameraOn);
    } else {
      Alog.e(
        tag: 'RoomDetailPage',
        content: 'toggleCamera 失败: code=${result.code}, msg=${result.msg}',
      );
      if (mounted) {
        String hint;
        if (result.code == 403 || result.code == 1002) {
          hint = '无摄像头控制权限\n'
              '请到云信控制台→房间组件→场景模板→13756→编辑角色权限→开启"音视频控制"';
        } else {
          hint = '操作失败 (code=${result.code}): ${result.msg ?? ""}';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(hint),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // ─── 离开/结束房间 ────────────────────────────────────────────────────────────

  Future<void> _handleLeaveRoom() async {
    // 防止重复点击（_isLeaving 已为 true 时跳过）
    if (_isLeaving) return;

    final action = widget.isOwner ? '结束课堂' : '离开课堂';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(action),
        content: Text(
          widget.isOwner
              ? '确认结束本次课堂？所有成员将退出。'
              : '确认离开本次课堂？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              action,
              style: TextStyle(
                color: widget.isOwner ? Colors.red : Colors.orange,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    // 标记正在离开，避免 roomEnd 事件再次弹窗，同时显示 AppBar 菊花
    setState(() => _isLeaving = true);

    try {
      if (_roomContext != null) {
        // ── 先关闭本地音视频流 ─────────────────────────────────────────────────
        // 防止退出后其他参与者仍能看到/听到本地流（硬件摄像头/麦克风未释放问题）
        try {
          if (_isCameraOn) {
            await _roomContext!.rtcController.muteMyVideo();
            print('✅ [RoomDetailPage] 已关闭本地视频');
          }
          if (_isMicOn) {
            await _roomContext!.rtcController.muteMyAudio();
            print('✅ [RoomDetailPage] 已关闭本地麦克风');
          }
        } catch (e) {
          print('⚠️ [RoomDetailPage] 关闭音视频失败（不影响退出）: $e');
        }

        if (widget.isOwner) {
          // 1. 通知 NERoom SDK 结束房间（会触发 roomEnd 事件，已被 _isLeaving 拦截）
          await _roomContext!.endRoom();
          // 2. 通知后端将 fa_im_room.status 更新为 0，避免房间一直出现在列表
          try {
            await RoomService().closeRoom(widget.room.roomId);
            print('✅ [RoomDetailPage] 后端房间状态已更新为已关闭');
          } catch (e) {
            print('⚠️ [RoomDetailPage] 后端 closeRoom 失败（不影响退出）: $e');
          }
        } else {
          // 成员离开：通知 SDK 并更新后端在线人数
          await _roomContext!.leaveRoom();
          try {
            await RoomService().leaveRoom(widget.room.roomId);
          } catch (_) {}
        }
      }

      // ⚠️ 关键：leaveRoom/endRoom 后标记 RTC 状态为"脏"，
      //    下次进入课堂时 ensureLogin() 会在"进入前"执行 logout + login，
      //    彻底重置 NERtc 引擎 channel 会话（避免 joinRtcChannel 返回 30004）。
      //    此处不立即 logout，以免断开底层 NIM SDK 的 IM 连接，影响群聊等功能。
      RoomKitService().markRtcDirty();
      print('🔔 [RoomDetailPage] 已标记 RTC 为脏状态，下次进入课堂将重置 NERtc 引擎');
    } catch (e) {
      Alog.e(tag: 'RoomDetailPage', content: '离开房间异常: $e');
    } finally {
      // 确保无论如何都退出页面
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  void _showRoomEndedDialog() {
    // 防止重复触发（_isLeaving 已为 true 时说明本端已主动离开，跳过）
    if (_isLeaving) return;
    if (mounted) setState(() => _isLeaving = true);

    // 房间被外部（老师）结束时，标记 RTC 状态为脏，
    // 原因与 _handleLeaveRoom 相同：下次进入课堂前重置 NERtc 引擎。
    RoomKitService().markRtcDirty();
    print('🔔 [RoomDetailPage] 房间已结束，已标记 RTC 为脏状态');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('课堂已结束'),
        content: const Text('老师已结束本次课堂。'),
        actions: [
          TextButton(
            onPressed: () {
              // 1. 关闭弹窗（对话框在根 Navigator 上，用 ctx 精确定位）
              Navigator.of(ctx).pop();
              // 2. 下一帧再关闭 RoomDetailPage，避免与弹窗关闭动画冲突
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) Navigator.of(context).pop(true);
              });
            },
            child: const Text('返回'),
          ),
        ],
      ),
    );
  }

  // ─── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _handleLeaveRoom();
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        appBar: _buildAppBar(),
        // 使用 NERoomContextProvider 包裹，使 NERoomUserVideoView 可正常工作
        body: _roomContext != null
            ? _buildBody()
            : _buildNoContextBody(),
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        _buildRoomInfoBar(),
        // 视频区 + 聊天气泡覆盖层（Stack：视频全高，气泡悬浮底部，互不挤压）
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: _buildVideoArea()),
              // 聊天气泡悬浮层：最大占屏幕高度 30%，背景渐变透明→半深
              if (_isChatOpen)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildChatBubbleOverlay(),
                ),
            ],
          ),
        ),
        // 输入框行（在视频区外，键盘弹起时自动上移）
        if (_isChatOpen) _buildChatInputRow(),
        _buildMemberList(),
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildNoContextBody() {
    return const Center(
      child: Text('未连接到课堂', style: TextStyle(color: Colors.white60)),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF16213E),
      foregroundColor: Colors.white,
      automaticallyImplyLeading: false,
      title: Text(
        widget.room.roomName,
        style:
            const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      actions: [
        if (_isLeaving)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            ),
          )
        else
          TextButton.icon(
            onPressed: _handleLeaveRoom,
            icon: Icon(
              widget.isOwner
                  ? Icons.stop_circle_outlined
                  : Icons.exit_to_app,
              color: widget.isOwner
                  ? Colors.red.shade300
                  : Colors.orange.shade300,
              size: 18,
            ),
            label: Text(
              widget.isOwner ? '结束' : '离开',
              style: TextStyle(
                color: widget.isOwner
                    ? Colors.red.shade300
                    : Colors.orange.shade300,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRoomInfoBar() {
    final memberCount = _remoteMembers.length + 1; // +1 = 自己
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF0F3460),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            '直播中',
            style: TextStyle(color: Colors.green, fontSize: 12),
          ),
          const SizedBox(width: 16),
          Icon(Icons.people, size: 14, color: Colors.grey.shade400),
          const SizedBox(width: 4),
          Text(
            '$memberCount 人',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: widget.isOwner || widget.isTeacher
                  ? Colors.orange.withOpacity(0.2)
                  : Colors.blue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
              child: Text(
              widget.isOwner || widget.isTeacher ? '🎓 老师' : '📚 学生',
              style: TextStyle(
                fontSize: 11,
                color: widget.isOwner || widget.isTeacher
                    ? Colors.orange.shade300
                    : Colors.blue.shade300,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 辅助：判断成员是否为老师（host 角色）────────────────────────────────────
  //
  // ⚠️ NERoomKit 可能仅允许一个真正的 'host'（房间创建者），其他以 'host' 加入
  //    的成员在 SDK 内部可能被降为 'member'。此方法仅保留用于上限判断，布局计算
  //    改为直接检测 isVideoOn（见 _buildVideoArea）。
  bool _isMemberHost(NERoomMember m) {
    if (_roomContext == null) return false;
    // 本机成员：isOwner 或 cohost 均算教师端
    if (m.uuid == _roomContext!.localMember.uuid) return widget.isOwner || widget.isTeacher;
    // 远端成员：role.name == 'host' 或者 role.name == 'coHost'（NIM 双主播场景）
    final rn = m.role.name.toLowerCase();
    return rn == 'host' || rn == 'cohost';
  }

  // ─── 辅助：学生端自拍小画面 PiP（右上角） ───────────────────────────────────

  Positioned _buildStudentPiP() {
    return Positioned(
      top: 12,
      right: 12,
      child: SizedBox(
        width: 100,
        height: 140,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: _buildVideoView(_roomContext!.localMember, isMain: false),
        ),
      ),
    );
  }

  // ─── 视频区域：根据开摄像头人数动态选择布局 ─────────────────────────────────
  //
  //   0 人开摄像头  →  单人占位（显示首位老师信息卡）
  //   1 人开摄像头  →  全屏单人视频
  //   2 人开摄像头  →  左右并列 1:1
  //   3 / 4 人开摄像头 →  田字格 2×2
  //
  // ⚠️ NERoomKit 对多 host 的支持有限，不能依赖 role.name 来判断"老师"。
  //    由于学生端 UI 上没有摄像头按钮，实际能出现在视频流里的只有老师，
  //    因此改为：只要有人开了摄像头，就纳入多视频布局。
  //
  // 学生端的自拍始终以右上角小画面叠加显示。
  Widget _buildVideoArea() {
    if (_roomContext == null) return const SizedBox.shrink();

    // 收集所有成员（本地 + 远端）
    final allMembers = [_roomContext!.localMember, ..._remoteMembers];

    // 正在开摄像头的成员列表（本地用 _isCameraOn，远端用 isVideoOn）
    // ⚠️ 不再过滤 role.name，原因见上方注释
    final teachersOnVideo = allMembers.where((m) {
      return m.uuid == _roomContext!.localMember.uuid
          ? _isCameraOn
          : m.isVideoOn;
    }).toList();

    // Debug：打印布局决策（便于排查多老师场景问题）
    print('📹 [VideoLayout] members=${allMembers.length}, '
        'onVideo=${teachersOnVideo.length} '
        '[${teachersOnVideo.map((m) => '${m.name}(role=${m.role.name})').join(', ')}]');

    // 学生端自拍 PiP（叠加在所有布局的右上角）
    // cohost 属于教师侧，视频直接显示在主布局中，不用小画面 PiP
    // cohost/协同老师的视频直接显示在主布局中，不用小画面 PiP
    final showStudentPiP = !widget.isOwner && !widget.isTeacher && _isCameraOn;

    // ── 0 位老师开视频 → 显示房主信息占位 ──────────────────────────────────────
    if (teachersOnVideo.isEmpty) {
      final hostMember = widget.isOwner
          ? _roomContext!.localMember
          : _remoteMembers.firstWhere(
              (m) => _isMemberHost(m),
              orElse: () => _roomContext!.localMember,
            );
      return Stack(
        children: [
          Positioned.fill(child: _buildVideoView(hostMember, isMain: true)),
          if (showStudentPiP) _buildStudentPiP(),
        ],
      );
    }

    // ── 1 位老师开视频 → 全屏 ─────────────────────────────────────────────────
    if (teachersOnVideo.length == 1) {
      return Stack(
        children: [
          Positioned.fill(
            child: _buildVideoView(teachersOnVideo[0], isMain: true),
          ),
          if (showStudentPiP) _buildStudentPiP(),
        ],
      );
    }

    // ── 2 位老师开视频 → 左右并列 ─────────────────────────────────────────────
    if (teachersOnVideo.length == 2) {
      return Stack(
        children: [
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: _buildVideoView(teachersOnVideo[0], isMain: false),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: _buildVideoView(teachersOnVideo[1], isMain: false),
                ),
              ],
            ),
          ),
          if (showStudentPiP) _buildStudentPiP(),
        ],
      );
    }

    // ── 3 或 4 位老师开视频 → 田字格 2×2 ─────────────────────────────────────
    final items = teachersOnVideo.take(4).toList();
    Widget cell(int idx) => items.length > idx
        ? _buildVideoView(items[idx], isMain: false)
        : Container(color: const Color(0xFF16213E));

    return Stack(
      children: [
        Positioned.fill(
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: cell(0)),
                    const SizedBox(width: 2),
                    Expanded(child: cell(1)),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: cell(2)),
                    const SizedBox(width: 2),
                    Expanded(child: cell(3)),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showStudentPiP) _buildStudentPiP(),
      ],
    );
  }

  Widget _buildVideoView(NERoomMember member, {required bool isMain}) {
    final uuid = member.uuid;

    if (!member.isVideoOn) {
      // 摄像头关闭：显示头像占位
      return Container(
        color: const Color(0xFF16213E),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: isMain ? 40 : 20,
              backgroundColor:
                  CommonColors.color_337eff.withOpacity(0.3),
              child: Text(
                (member.name.isNotEmpty ? member.name[0] : '?')
                    .toUpperCase(),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isMain ? 32 : 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (isMain) ...[
              const SizedBox(height: 12),
              Text(
                member.name.isNotEmpty ? member.name : uuid,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                member.isAudioOn ? '🎤 麦克风已开' : '🔇 静音中',
                style: TextStyle(
                  color: member.isAudioOn ? Colors.green : Colors.grey,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      );
    }

    // 摄像头开启：使用底层 NERtcVideoRendererFactory 渲染真实视频流
    // ⚠️ 不使用 NERoomUserVideoView：SDK 1.43.0 中该 Widget 的
    //    MERoomVideoStrategyContext.strategy late 字段存在 null 问题，
    //    会在 didChangeDependencies 中抛出未处理异常导致画面变灰。
    // ⚠️ 使用 GlobalKey 而非 ValueKey：布局从单列切换到双列（或反之）时，
    //    GlobalKey 可跨父级保持 _RemoteVideoView / _LocalVideoView 的内部状态，
    //    避免因父级 Widget 树结构变化导致视频订阅被销毁重建。
    final isLocal = member.uuid == _roomContext!.localMember.uuid;
    if (isLocal) {
      return _LocalVideoView(
        key: _getLocalVideoGlobalKey(),
        roomContext: _roomContext!,
      );
    } else {
      final rtcUid = member.rtcUid;
      if (rtcUid == null) {
        // rtcUid 未就绪：显示占位，延迟刷新由 _syncInitialState 保障
        print('⏳ [RoomDetailPage] 远端成员 ${member.name} rtcUid 未就绪，显示占位');
        return Container(
          color: const Color(0xFF16213E),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: isMain ? 40 : 20,
                backgroundColor: const Color(0xFF337EFF).withOpacity(0.3),
                child: Text(
                  (member.name.isNotEmpty ? member.name[0] : '?').toUpperCase(),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isMain ? 32 : 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '视频连接中...',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        );
      }
      return _RemoteVideoView(
        key: _getRemoteVideoGlobalKey(rtcUid),
        roomContext: _roomContext!,
        rtcUid: rtcUid,
      );
    }
  }

  Widget _buildMemberList() {
    if (_remoteMembers.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 72,
      color: const Color(0xFF16213E),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _remoteMembers.length,
        itemBuilder: (_, i) {
          final m = _remoteMembers[i];
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Column(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor:
                          CommonColors.color_337eff.withOpacity(0.3),
                      child: Text(
                        (m.name.isNotEmpty ? m.name[0] : '?')
                            .toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (!m.isAudioOn)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.red.shade400,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.mic_off,
                            size: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  m.name.isNotEmpty
                      ? (m.name.length > 4
                          ? '${m.name.substring(0, 4)}..'
                          : m.name)
                      : m.uuid.substring(
                          0, m.uuid.length > 6 ? 6 : m.uuid.length),
                  style: const TextStyle(
                      color: Colors.white60, fontSize: 10),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── 聊天气泡覆盖层 ────────────────────────────────────────────────────────────

  /// 悬浮于视频底部的气泡列表
  ///
  /// - 最大高度 = 屏幕高度 × 30%（约 5-6 行消息），超出时可向上滚动
  /// - 背景：上透明 → 下半深灰渐变，不遮挡视频主体
  /// - 无标题栏；关闭按钮在下方输入行
  Widget _buildChatBubbleOverlay() {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.30,
      ),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Color(0xBB000000)],
            stops: [0.0, 1.0],
          ),
        ),
        child: _chatMessages.isEmpty
            ? const SizedBox.shrink()
            : ListView.builder(
                controller: _chatScrollController,
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 8, 52, 8),
                itemCount: _chatMessages.length,
                itemBuilder: (_, i) => _buildBubbleItem(_chatMessages[i]),
              ),
      ),
    );
  }

  /// 单条消息气泡 —— 普通文字 or 入室通知
  Widget _buildBubbleItem(Map<String, dynamic> msg) {
    final type = msg['type'] as String? ?? 'text';
    final nick = msg['nick'] as String? ?? '';

    // ── 入室通知：轻量小字提示 ─────────────────────────────────────────────────
    if (type == 'join') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.45),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '👋 $nick 加入',
                style:
                    const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ),
          ],
        ),
      );
    }

    // ── 普通文字气泡 ──────────────────────────────────────────────────────────
    final text = msg['text'] as String? ?? '';
    final isMe = msg['isMe'] as bool? ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '$nick: ',
                      style: TextStyle(
                        // 自己发的昵称用蓝色，他人用金色
                        color: isMe
                            ? const Color(0xFF7EC8FF)
                            : const Color(0xFFFFD580),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextSpan(
                      text: text,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 聊天输入行（视频区下方，键盘自动上移）─────────────────────────────────────

  /// 包含：关闭按钮 | 文字输入框 | 发送按钮
  Widget _buildChatInputRow() {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      color: const Color(0xFF0D0D1A),
      child: Row(
        children: [
          // ↓ 关闭聊天覆盖层
          GestureDetector(
            onTap: () => setState(() => _isChatOpen = false),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Icon(Icons.keyboard_arrow_down,
                  color: Colors.white54, size: 20),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _chatInputController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: '发送消息...',
                hintStyle:
                    const TextStyle(color: Colors.white38, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFF2A2A3E),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _sendChatMessage(),
              textInputAction: TextInputAction.send,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sendChatMessage,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.blue.shade600,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: const Color(0xFF16213E),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // ─── 老师（isOwner）或协同老师（isTeacher，群主/管理员）可见的音视频控制按钮 ───
            if (widget.isOwner || widget.isTeacher) ...[
              _ToolButton(
                icon: _isMicOn ? Icons.mic : Icons.mic_off,
                label: _isMicOn ? '静音' : '取消静音',
                color: _isMicOn ? Colors.white70 : Colors.red.shade400,
                onTap: _toggleMic,
              ),
              _ToolButton(
                icon: _isCameraOn ? Icons.videocam : Icons.videocam_off,
                label: _isCameraOn ? '关闭视频' : '开启视频',
                color: _isCameraOn ? Colors.white70 : Colors.grey.shade500,
                onTap: _toggleCamera,
              ),
              // 翻转摄像头按钮：仅摄像头开启时可用
              _ToolButton(
                icon: Icons.flip_camera_ios,
                label: '翻转',
                color: _isCameraOn
                    ? (_isSwitchingCamera ? Colors.white38 : Colors.white70)
                    : Colors.grey.shade700,
                onTap: _isCameraOn ? _switchCamera : null,
              ),
            ],
            // ─── 所有角色可用的按钮 ───
            _ToolButton(
              icon: _isChatOpen ? Icons.chat_bubble : Icons.chat_bubble_outline,
              label: '聊天',
              color: _isChatOpen ? Colors.blue.shade300 : Colors.white70,
              onTap: () => setState(() => _isChatOpen = !_isChatOpen),
            ),
            _ToolButton(
              icon: Icons.people_outline,
              label: '成员 ${_remoteMembers.length + 1}',
              onTap: _showMembersSheet,
            ),
          ],
        ),
      ),
    );
  }

  void _showMembersSheet() {
    final ctx = _roomContext;
    if (ctx == null) return;

    final allMembers = [ctx.localMember, ..._remoteMembers];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16213E),
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white30,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '课堂成员 (${allMembers.length})',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Divider(color: Colors.white12),
          Expanded(
            child: ListView.builder(
              itemCount: allMembers.length,
              itemBuilder: (_, i) {
                final m = allMembers[i];
                final isMe = m.uuid == ctx.localMember.uuid;
                final isHost =
                    m.uuid == widget.room.ownerAccid;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isHost
                        ? Colors.orange.withOpacity(0.3)
                        : CommonColors.color_337eff
                            .withOpacity(0.2),
                    child: Text(
                      (m.name.isNotEmpty ? m.name[0] : '?')
                          .toUpperCase(),
                      style:
                          const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(
                    '${m.name.isNotEmpty ? m.name : m.uuid}'
                    '${isMe ? " (我)" : ""}'
                    '${isHost ? " 👑" : ""}',
                    style:
                        const TextStyle(color: Colors.white),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        m.isAudioOn ? Icons.mic : Icons.mic_off,
                        color: m.isAudioOn
                            ? Colors.green
                            : Colors.red,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        m.isVideoOn
                            ? Icons.videocam
                            : Icons.videocam_off,
                        color: m.isVideoOn
                            ? Colors.green
                            : Colors.grey,
                        size: 18,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 本地视频视图 ──────────────────────────────────────────────────────────────
/// 用底层 NERtcVideoRendererFactory 渲染本地摄像头，绕过 NERoomUserVideoView 的
/// MERoomVideoStrategyContext.strategy 空指针 Bug（netease_roomkit 1.43.0）。
class _LocalVideoView extends StatefulWidget {
  final NERoomContext roomContext;
  const _LocalVideoView({required this.roomContext, Key? key}) : super(key: key);

  @override
  State<_LocalVideoView> createState() => _LocalVideoViewState();
}

class _LocalVideoViewState extends State<_LocalVideoView> {
  NERtcVideoRenderer? _renderer;

  @override
  void initState() {
    super.initState();
    _setupRenderer();
  }

  Future<void> _setupRenderer() async {
    try {
      final r = await NERtcVideoRendererFactory.createVideoRenderer(
        widget.roomContext.roomUuid,
      );
      await r.attachToLocalVideo();
      if (mounted) setState(() => _renderer = r);
      print('✅ [LocalVideoView] 本地视频渲染器已初始化');
    } catch (e) {
      print('⚠️ [LocalVideoView] 初始化失败: $e');
    }
  }

  @override
  void dispose() {
    _renderer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = _renderer;
    if (r == null) {
      return const ColoredBox(color: Color(0xFF16213E));
    }
    return NERtcVideoView(r);
  }
}

// ─── 远端视频视图 ──────────────────────────────────────────────────────────────
/// 用底层 API 订阅并渲染远端用户视频流，绕过 NERoomUserVideoView 的 SDK Bug。
class _RemoteVideoView extends StatefulWidget {
  final NERoomContext roomContext;
  final int rtcUid;
  const _RemoteVideoView({
    required this.roomContext,
    required this.rtcUid,
    Key? key,
  }) : super(key: key);

  @override
  State<_RemoteVideoView> createState() => _RemoteVideoViewState();
}

class _RemoteVideoViewState extends State<_RemoteVideoView> {
  NERtcVideoRenderer? _renderer;

  @override
  void initState() {
    super.initState();
    _setupRenderer();
  }

  @override
  void didUpdateWidget(_RemoteVideoView old) {
    super.didUpdateWidget(old);
    if (old.rtcUid != widget.rtcUid) {
      _disposeRenderer(old.rtcUid).then((_) => _setupRenderer());
    }
  }

  Future<void> _setupRenderer() async {
    try {
      // 1. 订阅远端视频流（kLow = 默认低延迟主流，与 NERoomUserVideoView 默认一致）
      await widget.roomContext.rtcController.subscribeRemoteVideoStreamByRtcUid(
        widget.rtcUid,
        NEVideoStreamType.kLow,
        true,
      );

      // 2. 创建渲染器并绑定远端 RTC UID
      final r = await NERtcVideoRendererFactory.createVideoRenderer(
        widget.roomContext.roomUuid,
      );
      await r.attachToRemoteVideo(widget.rtcUid);

      if (mounted) setState(() => _renderer = r);
      print('✅ [RemoteVideoView] 远端视频已初始化: rtcUid=${widget.rtcUid}');
    } catch (e) {
      print('⚠️ [RemoteVideoView] 初始化失败: rtcUid=${widget.rtcUid}, error=$e');
    }
  }

  Future<void> _disposeRenderer(int rtcUid) async {
    final r = _renderer;
    if (mounted) setState(() => _renderer = null);
    if (r != null) {
      try {
        await widget.roomContext.rtcController.subscribeRemoteVideoStreamByRtcUid(
          rtcUid,
          NEVideoStreamType.kLow,
          false,
        );
      } catch (_) {}
      await r.dispose();
    }
  }

  @override
  void dispose() {
    // dispose() 同步，异步清理不等待
    final r = _renderer;
    _renderer = null;
    if (r != null) {
      widget.roomContext.rtcController
          .subscribeRemoteVideoStreamByRtcUid(widget.rtcUid, NEVideoStreamType.kLow, false)
          .then((_) {}, onError: (_) {});
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = _renderer;
    if (r == null) {
      return const ColoredBox(color: Color(0xFF16213E));
    }
    return NERtcVideoView(r);
  }
}

// ─── 工具按钮 ─────────────────────────────────────────────────────────────────

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap; // nullable：为 null 时按钮不可点击
  final Color? color;

  const _ToolButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Icon(
              icon,
              color: color ?? Colors.white70,
              size: 24,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: color ?? Colors.white70,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
