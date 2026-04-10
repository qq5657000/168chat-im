// Copyright (c) 2024 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:netease_common_ui/utils/color_utils.dart';
import 'package:yunxin_alog/yunxin_alog.dart';
import '../services/group_service.dart';
import '../services/auth_service.dart';
import '../models/group_model.dart';
import '../api/api_response.dart';

/// 群组详情页面
class GroupDetailPage extends StatefulWidget {
  final GroupModel group;

  const GroupDetailPage({Key? key, required this.group}) : super(key: key);

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<GroupDetailPage> {
  final GroupService _groupService = GroupService();
  final AuthService _authService = AuthService();

  late GroupModel _group;
  List<GroupMemberModel> _members = [];
  bool _isLoadingMembers = false;
  bool _isDisbanding = false;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _loadGroupMembers();
  }

  /// 加载群成员列表
  Future<void> _loadGroupMembers() async {
    setState(() {
      _isLoadingMembers = true;
    });

    try {
      final response = await _groupService.getGroupMembers(_group.groupId);

      if (response.isSuccess && response.data != null) {
        setState(() {
          _members = response.data!;
          _isLoadingMembers = false;
        });
        Alog.d(tag: 'GroupDetailPage', content: 'Load members success: ${_members.length}');
      } else {
        setState(() {
          _isLoadingMembers = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoadingMembers = false;
      });
      Alog.e(tag: 'GroupDetailPage', content: 'Load members failed: $e');
    }
  }

  /// 解散群组
  Future<void> _handleDisbandGroup() async {
    // 检查是否是群主
    final currentUser = _authService.currentUser;
    if (currentUser == null || currentUser.accid != _group.ownerAccid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('只有群主可以解散群组')),
      );
      return;
    }

    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认解散'),
        content: Text('确定要解散群组「${_group.groupName}」吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('解散'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isDisbanding = true;
    });

    try {
      Alog.d(tag: 'GroupDetailPage', content: '开始解散群组: ${_group.groupId}');

      final response = await _groupService.disbandGroup(_group.groupId);

      if (response.isSuccess) {
        Alog.d(tag: 'GroupDetailPage', content: '解散群组成功');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('解散群组成功')),
          );
          // 返回 true 表示有变化
          Navigator.of(context).pop(true);
        }
      } else {
        setState(() {
          _isDisbanding = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('解散失败: ${response.msg}')),
          );
        }
      }
    } on ApiException catch (e) {
      setState(() {
        _isDisbanding = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('解散失败: ${e.message}')),
        );
      }
    } catch (e) {
      setState(() {
        _isDisbanding = false;
      });
      Alog.e(tag: 'GroupDetailPage', content: 'Disband group failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('解散失败: ${e.toString()}')),
        );
      }
    }
  }

  /// 是否是群主
  bool get _isOwner {
    final currentUser = _authService.currentUser;
    return currentUser != null && currentUser.accid == _group.ownerAccid;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('群组详情'),
        actions: [
          if (_isOwner)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _isDisbanding ? null : _handleDisbandGroup,
              tooltip: '解散群组',
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 群组信息
            Container(
              padding: const EdgeInsets.all(24),
              color: Colors.white,
              child: Column(
                children: [
                  // 群头像
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: CommonColors.color_337eff,
                    backgroundImage: _group.groupAvatar != null &&
                            _group.groupAvatar!.isNotEmpty
                        ? NetworkImage(_group.groupAvatar!)
                        : null,
                    child: _group.groupAvatar == null ||
                            _group.groupAvatar!.isEmpty
                        ? const Icon(Icons.group, size: 40, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(height: 16),
                  // 群名称
                  Text(
                    _group.groupName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 群 ID
                  Text(
                    'ID: ${_group.groupId}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  if (_group.intro != null && _group.intro!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      _group.intro!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 8),

            // 群成员
            Container(
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '群成员 (${_group.memberCount})',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (_isLoadingMembers)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                  ),
                  if (_members.isNotEmpty)
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _members.length,
                      itemBuilder: (context, index) {
                        final member = _members[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: CommonColors.color_337eff,
                            backgroundImage: member.avatar != null &&
                                    member.avatar!.isNotEmpty
                                ? NetworkImage(member.avatar!)
                                : null,
                            child: member.avatar == null ||
                                    member.avatar!.isEmpty
                                ? const Icon(Icons.person, color: Colors.white)
                                : null,
                          ),
                          title: Text(
                            member.nickname ?? member.accid,
                            style: const TextStyle(fontSize: 15),
                          ),
                          subtitle: Text(
                            member.accid,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          trailing: member.isOwner
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '群主',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.orange.shade700,
                                    ),
                                  ),
                                )
                              : member.isAdmin
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '管理员',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.blue.shade700,
                                        ),
                                      ),
                                    )
                                  : null,
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
