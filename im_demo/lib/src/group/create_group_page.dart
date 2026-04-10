// Copyright (c) 2024 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:netease_common_ui/utils/color_utils.dart';
import 'package:yunxin_alog/yunxin_alog.dart';
import '../services/group_service.dart';
import '../api/api_response.dart';

/// 创建群组页面
class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({Key? key}) : super(key: key);

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _introController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;

  final GroupService _groupService = GroupService();

  @override
  void dispose() {
    _groupNameController.dispose();
    _introController.dispose();
    super.dispose();
  }

  /// 创建群组
  Future<void> _handleCreateGroup() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final groupName = _groupNameController.text.trim();
    final intro = _introController.text.trim();

    try {
      Alog.d(tag: 'CreateGroupPage', content: '开始创建群组: $groupName');

      final response = await _groupService.createGroup(
        groupName: groupName,
        intro: intro.isNotEmpty ? intro : null,
      );

      if (response.isSuccess && response.data != null) {
        Alog.d(tag: 'CreateGroupPage', content: '创建群组成功: ${response.data!.groupId}');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('创建群组成功')),
          );
          // 返回 true 表示创建成功
          Navigator.of(context).pop(true);
        }
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
        _errorMessage = '创建失败: ${e.toString()}';
        _isLoading = false;
      });
      Alog.e(tag: 'CreateGroupPage', content: 'Create group failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('创建群组'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 群组名称
                TextFormField(
                  controller: _groupNameController,
                  enabled: !_isLoading,
                  decoration: InputDecoration(
                    labelText: '群组名称',
                    hintText: '请输入群组名称',
                    prefixIcon: const Icon(Icons.group),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                          color: CommonColors.color_337eff, width: 2),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入群组名称';
                    }
                    if (value.trim().length < 2) {
                      return '群组名称至少 2 个字符';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // 群组简介
                TextFormField(
                  controller: _introController,
                  enabled: !_isLoading,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: '群组简介（可选）',
                    hintText: '请输入群组简介',
                    prefixIcon: const Icon(Icons.description_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                          color: CommonColors.color_337eff, width: 2),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // 错误提示
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline,
                            color: Colors.red.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 32),

                // 创建按钮
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleCreateGroup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CommonColors.color_337eff,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          '创建群组',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),

                const SizedBox(height: 24),

                // 提示信息
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        '💡 提示',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: CommonColors.color_337eff,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '• 创建后您将成为群主\n'
                        '• 群组将同步到云信服务器\n'
                        '• 您可以邀请好友加入群组',
                        style: TextStyle(
                          fontSize: 12,
                          color: CommonColors.color_666666,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
