// Copyright (c) 2024 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:im_demo/src/group/create_group_page.dart';
import 'package:im_demo/src/group/group_detail_page.dart';
import 'package:netease_common_ui/utils/color_utils.dart';
import 'package:yunxin_alog/yunxin_alog.dart';
import '../services/group_service.dart';
import '../models/group_model.dart';
import '../api/api_response.dart';

/// 群组列表页面
class GroupListPage extends StatefulWidget {
  const GroupListPage({Key? key}) : super(key: key);

  @override
  State<GroupListPage> createState() => _GroupListPageState();
}

class _GroupListPageState extends State<GroupListPage> {
  final GroupService _groupService = GroupService();
  List<GroupModel> _groups = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadGroupList();
  }

  /// 加载群组列表
  Future<void> _loadGroupList() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _groupService.getGroupList();

      if (response.isSuccess && response.data != null) {
        setState(() {
          _groups = response.data!;
          _isLoading = false;
        });
        Alog.d(tag: 'GroupListPage', content: 'Load groups success: ${_groups.length}');
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
      Alog.e(tag: 'GroupListPage', content: 'Load groups failed: $e');
    }
  }

  /// 跳转到创建群组页面
  void _navigateToCreateGroup() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => const CreateGroupPage(),
      ),
    );

    // 如果创建成功，刷新列表
    if (result == true) {
      _loadGroupList();
    }
  }

  /// 跳转到群组详情页面
  void _navigateToGroupDetail(GroupModel group) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => GroupDetailPage(group: group),
      ),
    );

    // 如果有变化，刷新列表
    if (result == true) {
      _loadGroupList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的群组'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _navigateToCreateGroup,
            tooltip: '创建群组',
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
              onPressed: _loadGroupList,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.group_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              '暂无群组',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _navigateToCreateGroup,
              icon: const Icon(Icons.add),
              label: const Text('创建群组'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadGroupList,
      child: ListView.builder(
        itemCount: _groups.length,
        itemBuilder: (context, index) {
          final group = _groups[index];
          return _buildGroupItem(group);
        },
      ),
    );
  }

  Widget _buildGroupItem(GroupModel group) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: CommonColors.color_337eff,
        backgroundImage: group.groupAvatar != null && group.groupAvatar!.isNotEmpty
            ? NetworkImage(group.groupAvatar!)
            : null,
        child: group.groupAvatar == null || group.groupAvatar!.isEmpty
            ? const Icon(Icons.group, color: Colors.white)
            : null,
      ),
      title: Text(
        group.groupName,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        '${group.memberCount} 人 · ${group.intro ?? '暂无简介'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          color: Colors.grey.shade600,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _navigateToGroupDetail(group),
    );
  }
}
