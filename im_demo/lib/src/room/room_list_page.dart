// Copyright (c) 2024 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:im_demo/src/room/create_room_page.dart';
import 'package:im_demo/src/room/room_detail_page.dart';
import 'package:im_demo/src/room/room_kit_service.dart';
import 'package:netease_common_ui/utils/color_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunxin_alog/yunxin_alog.dart';
import '../services/room_service.dart';
import '../models/room_model.dart';
import '../api/api_response.dart';

/// 房间列表页面
class RoomListPage extends StatefulWidget {
  const RoomListPage({Key? key}) : super(key: key);

  @override
  State<RoomListPage> createState() => _RoomListPageState();
}

class _RoomListPageState extends State<RoomListPage> {
  final RoomService _roomService = RoomService();
  List<RoomModel> _rooms = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRoomList();
  }

  /// 加载房间列表
  Future<void> _loadRoomList() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _roomService.getRoomList(status: 1); // 只加载进行中的房间

      if (response.isSuccess && response.data != null) {
        setState(() {
          _rooms = response.data!;
          _isLoading = false;
        });
        Alog.d(tag: 'RoomListPage', content: 'Load rooms success: ${_rooms.length}');
      } else {
        setState(() {
          _errorMessage = response.msg;
          _isLoading = false;
        });
      }
    } on ApiException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '加载失败: ${e.toString()}';
        _isLoading = false;
      });
      Alog.e(tag: 'RoomListPage', content: 'Load rooms failed: $e');
    }
  }

  /// 跳转到创建房间页面
  void _navigateToCreateRoom() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => const CreateRoomPage(groupId: ''),
      ),
    );

    // 如果创建成功，刷新列表
    if (result == true) {
      _loadRoomList();
    }
  }

  /// 加入房间并跳转到课堂详情页
  Future<void> _handleJoinRoom(RoomModel room) async {
    // 防止重复点击
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('正在进入课堂...'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      Alog.d(tag: 'RoomListPage', content: '开始加入课堂: ${room.roomId}');

      // 1. 后端验证加入资格
      final response = await _roomService.joinRoom(room.roomId);

      if (!response.isSuccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('加入失败: ${response.msg}')),
          );
        }
        return;
      }

      Alog.d(tag: 'RoomListPage', content: '后端验证通过，准备连接 NERoomKit');

      // 2. 读取本地缓存 token（⚠️ 不再调用 getImToken()！）
      // 原因：getImToken() 调用 NIM refreshToken.action 生成新 nimToken，
      //       会导致 NERoomKit 内部 NIM session 失效（token rotation），
      //       使 joinChatroom 返回 302 鉴权失败。
      // 解决方案：直接读本地缓存（与 NERoomKit 当前 session 一致），chatroom 可正常加入。
      final prefs = await SharedPreferences.getInstance();
      final accid     = prefs.getString('account')       ?? '';
      final nimToken  = prefs.getString('nim_im_token')  ?? '';
      final roomToken = prefs.getString('room_token')    ?? '';

      // 读取昵称，以 accid 为兜底（确保 NERoomKit userName 不为空）
      final nickname = prefs.getString('nickname')?.isNotEmpty == true
          ? prefs.getString('nickname')!
          : accid;

      print('🔑 [RoomListPage] accid=$accid, nickname=$nickname, nimToken=${nimToken.length > 8 ? nimToken.substring(0, 8) : nimToken}***');
      print('🔑 [RoomListPage] room_token=${roomToken.isNotEmpty ? "${roomToken.substring(0, roomToken.length.clamp(0, 20))}..." : "（为空，将使用 nimToken fallback）"}');

      final isOwner = room.ownerAccid == accid;

      if (accid.isEmpty || nimToken.isEmpty) {
        print('❌ [RoomListPage] 无法获取云信 token，请重新登录');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('获取登录凭证失败，请重新登录')),
          );
        }
        return;
      }

      // 3. 确保 NERoomKit 已登录（若已登录则跳过，避免重复 logout/login）
      // 使用 room_token（动态签名），若为空则回退 nimToken（静态 token，可能导致 402）
      final roomLoginToken = roomToken.isNotEmpty ? roomToken : nimToken;
      print('🔑 [RoomListPage] 确认 NERoomKit 登录状态: account=$accid，使用 ${roomToken.isNotEmpty ? "room_token" : "nimToken(fallback)"}');
      final loginOk = await RoomKitService().ensureLogin(accid, roomLoginToken);
      if (!loginOk) {
        print('❌ [RoomListPage] NERoomKit 登录失败，无法加入房间');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('NERoomKit 登录失败 (402=互动直播未开通或 token 无效)')),
          );
        }
        return;
      }
      print('✅ [RoomListPage] NERoomKit 登录成功，开始加入房间');

      // 3. 调用 NERoomKit 加入云信房间
      // 模板 13818（线上会议）有效角色：host（主持人）、cohost（联席主持人）、member（成员）
      // 加入已有房间的用户统一使用 'member' 角色，即可开启音视频
      final roomContext = await RoomKitService().joinRoom(
        roomUuid: room.roomId,
        userName: nickname,
        role: 'member',
      );

      if (roomContext == null) {
        if (mounted) {
          // 检查是否是 1004（房间不存在/已结束）
          // RoomKitService.joinRoom 返回 null 时无法直接取 code，
          // 但此时日志已打印；给用户友好提示并刷新列表（移除失效房间）
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('课堂已结束或不存在，列表已刷新'),
              duration: const Duration(seconds: 3),
              action: SnackBarAction(
                label: '刷新',
                onPressed: _loadRoomList,
              ),
            ),
          );
          // 自动刷新列表，让已结束的房间从列表消失
          _loadRoomList();
        }
        return;
      }

      Alog.d(tag: 'RoomListPage', content: 'NERoomKit 加入成功，跳转课堂页面');

      // 5. 跳转到课堂内页面，携带 NERoomContext
      if (mounted) {
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (context) => RoomDetailPage(
              room: room,
              isOwner: isOwner,
              isTeacher: isOwner, // 课堂列表页仅房主可进入自己的房间，默认老师权限
              roomContext: roomContext,
            ),
          ),
        );
        if (mounted) _loadRoomList();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加入失败: ${e.message}')),
        );
      }
    } catch (e) {
      Alog.e(tag: 'RoomListPage', content: 'Join room failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加入失败: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('在线课堂'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _navigateToCreateRoom,
            tooltip: '创建课堂',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadRoomList,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_rooms.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.video_call_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              '暂无进行中的课堂',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _navigateToCreateRoom,
              icon: const Icon(Icons.add),
              label: const Text('创建课堂'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRoomList,
      child: ListView.builder(
        itemCount: _rooms.length,
        itemBuilder: (context, index) {
          final room = _rooms[index];
          return _buildRoomItem(room);
        },
      ),
    );
  }

  Widget _buildRoomItem(RoomModel room) {
    final isFull = room.isFull;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: CommonColors.color_337eff,
          child: const Icon(Icons.video_call, color: Colors.white),
        ),
        title: Text(
          room.roomName,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '${room.subject ?? '暂无主题'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.people, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  '${room.currentMembers}/${room.maxMembers}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '进行中',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.green.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: ElevatedButton(
          onPressed: isFull ? null : () => _handleJoinRoom(room),
          style: ElevatedButton.styleFrom(
            backgroundColor: CommonColors.color_337eff,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          child: Text(isFull ? '已满' : '加入'),
        ),
      ),
    );
  }
}
