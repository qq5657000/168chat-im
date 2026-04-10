// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:im_demo/src/config.dart';
import 'package:im_demo/src/home/home_page.dart';
import 'package:netease_common_ui/utils/color_utils.dart';
import 'package:nim_chatkit/im_kit_client.dart';
import 'package:nim_chatkit_callkit/nim_chatkit_callkit.dart';
import 'package:nim_core_v2/nim_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSavedAccount();
  }

  // 加载上次保存的账号
  Future<void> _loadSavedAccount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedAccount = prefs.getString('last_account') ?? '';
      if (savedAccount.isNotEmpty) {
        setState(() {
          _accountController.text = savedAccount;
        });
      }
    } catch (e) {
      Alog.d(content: 'Load saved account failed: $e');
    }
  }

  // 保存账号信息
  Future<void> _saveLoginInfo(String account, String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_account', account);
      await prefs.setString('account', account);
      await prefs.setString('token', token);
      await prefs.setBool('is_logged_in', true);
    } catch (e) {
      Alog.e(content: 'Save login info failed: $e');
    }
  }

  // 执行登录
  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final account = _accountController.text.trim();
    final token = _tokenController.text.trim();

    try {
      final result = await IMKitClient.loginIMWithResult(
        account,
        token,
        option: NIMLoginOption(
          syncLevel: NIMDataSyncLevel.dataSyncLevelBasic,
        ),
      );

      if (result.isSuccess) {
        // 登录成功，保存信息
        await _saveLoginInfo(account, token);
        
        // 初始化 CallKit
        ChatKitCall.instance.init(
          appKey: IMDemoConfig.AppKey,
          accountId: account,
        );
        
        Alog.d(content: "登录成功，跳转到主页: $account");
        
        if (mounted) {
          // 跳转到主页，清除所有导航栈
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => const HomePage(),
            ),
            (route) => false,
          );
        }
      } else {
        // 登录失败
        setState(() {
          _errorMessage = '登录失败: ${result.errorDetails ?? '未知错误'} (code: ${result.code})';
          _isLoading = false;
        });
        Alog.e(content: "登录失败: code=${result.code}, details=${result.errorDetails}");
      }
    } catch (e) {
      setState(() {
        _errorMessage = '登录异常: ${e.toString()}';
        _isLoading = false;
      });
      Alog.e(content: "登录异常: ${e.toString()}");
    }
  }

  @override
  void dispose() {
    _accountController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 60),
                
                // Logo 或标题
                Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 80,
                        color: CommonColors.color_337eff,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '云信 IM',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: CommonColors.color_333333,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '请登录您的账号',
                        style: TextStyle(
                          fontSize: 14,
                          color: CommonColors.color_999999,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 60),
                
                // 账号输入框
                TextFormField(
                  controller: _accountController,
                  enabled: !_isLoading,
                  decoration: InputDecoration(
                    labelText: '账号',
                    hintText: '请输入云信 IM 账号',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: CommonColors.color_337eff, width: 2),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入账号';
                    }
                    return null;
                  },
                ),
                
                const SizedBox(height: 20),
                
                // Token 输入框
                TextFormField(
                  controller: _tokenController,
                  enabled: !_isLoading,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Token',
                    hintText: '请输入 Token',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: CommonColors.color_337eff, width: 2),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入 Token';
                    }
                    return null;
                  },
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
                        Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
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
                
                // 登录按钮
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleLogin,
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
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          '登录',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
                
                const SizedBox(height: 24),
                
                // 提示信息
                Center(
                  child: Container(
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
                          '• 账号和 Token 需要从云信控制台获取\n'
                          '• 访问 https://app.yunxin.163.com/\n'
                          '• 在用户管理中创建测试账号',
                          style: TextStyle(
                            fontSize: 12,
                            color: CommonColors.color_666666,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
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
