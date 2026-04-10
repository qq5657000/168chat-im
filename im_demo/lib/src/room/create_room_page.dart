// Copyright (c) 2024 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunxin_alog/yunxin_alog.dart';

import '../services/room_service.dart';
import '../api/api_response.dart';
import 'room_detail_page.dart';
import 'room_kit_service.dart';

/// 生成防碰撞的房间 UUID
/// 格式：时间戳毫秒_4位随机数  例如 "1775481055996_7382"
String _generateRoomUuid() {
  final ts = DateTime.now().millisecondsSinceEpoch;
  final rand = Random().nextInt(9000) + 1000; // 1000~9999
  return '${ts}_$rand';
}

/// 群内创建课堂页面（简化版）
///
/// 新流程：群主/管理员点击"创建课堂"后直接进入此页面，
/// 页面自动执行创建逻辑（无表单），仅展示创建状态。
///
/// 参数说明：
///   [groupId] — NIM 群组 teamId（必填，用于后端权限校验和课堂绑定）
///
/// 房间配置（全部自动填入，不再让用户手动输入）：
///   room_name  = 创建者昵称（从 SharedPreferences 读取）
///   room_type  = 1（听课房间，固定）
///   max_members = 100（固定）
class CreateRoomPage extends StatefulWidget {
  /// NIM 群组 teamId（字符串形式）
  final String groupId;

  const CreateRoomPage({
    Key? key,
    required this.groupId,
  }) : super(key: key);

  @override
  State<CreateRoomPage> createState() => _CreateRoomPageState();
}

class _CreateRoomPageState extends State<CreateRoomPage> {
  final RoomService _roomService = RoomService();

  _Status _status = _Status.creating;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // 进入页面后立即创建
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleCreateRoom());
  }

  // ─── 核心创建流程 ───────────────────────────────────────────────────────────

  Future<void> _handleCreateRoom() async {
    setState(() {
      _status = _Status.creating;
      _errorMessage = null;
    });

    try {
      // Step 0: 读取本地缓存信息
      final prefs = await SharedPreferences.getInstance();
      final accid = prefs.getString('account') ?? '';
      final nimToken = prefs.getString('nim_im_token') ?? '';
      final roomToken = prefs.getString('room_token') ?? '';
      final nickname = (prefs.getString('nickname')?.isNotEmpty == true)
          ? prefs.getString('nickname')!
          : accid;

      if (accid.isEmpty || nimToken.isEmpty) {
        _setError('获取登录凭证失败，请重新登录');
        return;
      }

      Alog.d(
          tag: 'CreateRoomPage',
          content: '开始创建群课堂 groupId=${widget.groupId}, '
              'accid=$accid nickname=$nickname');

      // Step 1: 生成防碰撞 UUID
      final roomUuid = _generateRoomUuid();

      // Step 2: 后端存库（同时校验群主/管理员权限）
      final response = await _roomService.createRoom(
        roomName: nickname, // 课堂名称 = 创建者昵称
        roomUuid: roomUuid,
        groupId: widget.groupId,
        roomType: 1, // 固定 1=听课房间
        maxMembers: 100, // 固定 100 人
      );

      if (!response.isSuccess || response.data == null) {
        _setError(response.msg.isNotEmpty ? response.msg : '创建失败，请重试');
        return;
      }

      final room = response.data!;
      Alog.d(
          tag: 'CreateRoomPage', content: '后端存库成功 roomId=${room.roomId}');

      if (!mounted) return;

      // Step 3: 确保 NERoomKit 登录
      final roomLoginToken = roomToken.isNotEmpty ? roomToken : nimToken;
      final loginOk =
          await RoomKitService().ensureLogin(accid, roomLoginToken);
      if (!loginOk) {
        _setError('NERoomKit 登录失败，请重新打开 App');
        return;
      }

      if (!mounted) return;

      // Step 4: NERoomKit 创建房间（连接 NERoom 服务端）
      final roomContext = await RoomKitService().createRoom(
        roomUuid: room.roomId,
        roomName: nickname,
        userName: nickname,
      );

      if (roomContext == null) {
        _setError('连接课堂失败，请重试');
        return;
      }

      Alog.d(tag: 'CreateRoomPage', content: 'NERoomKit 创建成功，进入课堂');

      if (!mounted) return;

      // Step 5: 跳转课堂页面（替换当前页，返回时直接回到群聊）
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => RoomDetailPage(
            room: room.copyWith(ownerAccid: accid),
            isOwner: true,
            isTeacher: true,
            roomContext: roomContext,
          ),
        ),
      );
    } on ApiException catch (e) {
      _setError(e.message.isNotEmpty ? e.message : '创建失败');
    } catch (e) {
      Alog.e(tag: 'CreateRoomPage', content: '创建失败: $e');
      _setError('创建失败：${e.toString()}');
    }
  }

  void _setError(String msg) {
    if (mounted) {
      setState(() {
        _status = _Status.error;
        _errorMessage = msg;
      });
    }
  }

  // ─── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF333333)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '创建课堂',
          style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Color(0xFF333333)),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: _status == _Status.creating
              ? _buildCreating()
              : _buildError(),
        ),
      ),
    );
  }

  Widget _buildCreating() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor:
                AlwaysStoppedAnimation<Color>(Color(0xFF337EFF)),
          ),
        ),
        SizedBox(height: 24),
        Text(
          '正在创建课堂…',
          style: TextStyle(
              fontSize: 16,
              color: Color(0xFF333333),
              fontWeight: FontWeight.w500),
        ),
        SizedBox(height: 8),
        Text(
          '请稍候，正在连接到课堂服务',
          style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, size: 56, color: Color(0xFFFF4D4F)),
        const SizedBox(height: 16),
        const Text(
          '创建失败',
          style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Color(0xFF333333)),
        ),
        const SizedBox(height: 8),
        Text(
          _errorMessage ?? '未知错误，请重试',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Color(0xFF666666)),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _handleCreateRoom,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF337EFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            child: const Text('重新创建',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消',
              style: TextStyle(fontSize: 15, color: Color(0xFF999999))),
        ),
      ],
    );
  }
}

enum _Status { creating, error }
