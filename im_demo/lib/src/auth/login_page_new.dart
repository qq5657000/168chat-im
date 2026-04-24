// Copyright (c) 2024 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:im_demo/src/auth/register_page.dart';
import 'package:im_demo/src/config.dart';
import 'package:im_demo/src/home/home_page.dart';
import 'package:netease_common_ui/utils/color_utils.dart';
import 'package:nim_chatkit/im_kit_client.dart';
import 'package:nim_chatkit_callkit/nim_chatkit_callkit.dart';
import 'package:nim_core_v2/nim_core.dart';
import '../services/auth_service.dart';
import '../api/api_response.dart';
import '../room/room_kit_service.dart';

/// 新的登录页面
/// 调用服务端 API 进行登录，获取云信 accid 和 token
class LoginPageNew extends StatefulWidget {
  const LoginPageNew({Key? key}) : super(key: key);

  @override
  State<LoginPageNew> createState() => _LoginPageNewState();
}

class _LoginPageNewState extends State<LoginPageNew> {
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;

  final AuthService _authService = AuthService();

  @override
  void dispose() {
    _mobileController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// 执行登录
  Future<void> _handleLogin() async {
    setState(() {
      _errorMessage = null;
    });

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final mobile = _mobileController.text.trim();
    final password = _passwordController.text.trim();

    try {
      // 1. 调用服务端登录接口
      Alog.d(tag: 'LoginPageNew', content: '开始登录: $mobile');

      final response = await _authService.login(
        mobile: mobile,
        password: password,
      );

      if (response.isSuccess && response.data != null) {
        final loginData = response.data!;
        final accid = loginData.user.accid;

        // ─────────────────────────────────────────────────────────────────
        // Token 说明（重要，勿混淆）：
        //   data.user.token     → NIM IM SDK 登录专用 token（nim_core_v2）
        //   data.user.room_token → NERoomKit 登录专用 token
        //
        // ⚠️ 后端已修复：generateRoomToken() 不再二次调用 refreshToken，
        //   两个字段值相同，但语义分离便于将来扩展。
        //   绝对不要把 room_token 传给 NIM SDK，也不要把 nimToken 传给 NERoomKit。
        // ─────────────────────────────────────────────────────────────────
        final nimToken  = loginData.user.token;        // NIM IM SDK 专用
        final roomToken = loginData.user.roomToken ?? nimToken; // NERoomKit 专用，兜底用 nimToken

        Alog.d(tag: 'LoginPageNew', content: '✅ 服务端登录成功: accid=$accid');
        print('🔑 [LoginPageNew] nimToken   = ${nimToken.substring(0, nimToken.length.clamp(0, 8))}*** (用于 nim_core_v2)');
        print('🔑 [LoginPageNew] room_token = ${roomToken.substring(0, roomToken.length.clamp(0, 8))}*** (用于 NERoomKit)');
        if (nimToken == roomToken) {
          print('ℹ️  [LoginPageNew] nimToken 与 room_token 相同（后端正常，无二次刷新）');
        } else {
          print('⚠️  [LoginPageNew] nimToken ≠ room_token，后端可能存在二次刷新，请检查 generateRoomToken()');
        }

        // ⚠️ 重要：NERoomKit 必须在 nim_core_v2 (IMKitClient) 登录之前登录
        // 原因：两者共享 Android NIM SDK 单例；若 nim_core_v2 先登录，
        //       NERoomKit 的 NIM 认证会被阻断，返回 code=402 Token不正确。
        // 步骤2: 先登录 NERoomKit（在 IMKit 之前）—— 使用 room_token
        print('🔑 [LoginPageNew] 步骤2: 先登录 NERoomKit（使用 room_token）');
        final roomOk = await RoomKitService().login(accid, roomToken);
        if (roomOk) {
          print('✅ [LoginPageNew] NERoomKit 登录成功');
        } else {
          print('⚠️ [LoginPageNew] NERoomKit 登录失败（继续登录 IM，房间功能可能不可用）');
        }
        Alog.i(
          tag: 'LoginPageNew',
          content: 'NERoomKit 登录${roomOk ? "成功" : "失败"}: accid=$accid',
        );

        // 步骤3: 登录 nim_core_v2 IM SDK —— 使用 nimToken（data.user.token 字段）
        // ⛔ 严禁此处传 roomToken，否则将报 102302 invalid token
        print('🔑 [LoginPageNew] 步骤3: 登录 nim_core_v2 IM SDK（使用 nimToken = data.user.token）');
        final imResult = await IMKitClient.loginIMWithResult(
          accid,
          nimToken, // ← 必须是 data.user.token，不能是 room_token
          option: NIMLoginOption(
            syncLevel: NIMDataSyncLevel.dataSyncLevelBasic,
          ),
        );

        if (imResult.isSuccess) {
          // 4. 初始化 CallKit
          ChatKitCall.instance.init(
            appKey: IMDemoConfig.AppKey,
            accountId: accid,
          );

          Alog.d(tag: 'LoginPageNew', content: '✅ 云信 SDK 登录成功，跳转到主页');

          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (context) => const HomePage(),
              ),
              (route) => false,
            );
          }
        } else {
          setState(() {
            _errorMessage = '云信登录失败: ${imResult.errorDetails ?? '未知错误'} (code: ${imResult.code})';
            _isLoading = false;
          });
          Alog.e(tag: 'LoginPageNew', content: '❌ 云信 SDK 登录失败: code=${imResult.code}');
        }
      } else {
        setState(() {
          _errorMessage = response.msg;
          _isLoading = false;
        });
        Alog.e(tag: 'LoginPageNew', content: '❌ 服务端登录失败: ${response.msg}');
      }
    } on ApiException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
      Alog.e(tag: 'LoginPageNew', content: '❌ API 异常: ${e.message}');
    } catch (e) {
      setState(() {
        _errorMessage = '登录异常: ${e.toString()}';
        _isLoading = false;
      });
      Alog.e(tag: 'LoginPageNew', content: '❌ 登录异常: ${e.toString()}');
    }
  }

  /// 跳转到注册页面
  void _navigateToRegister() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const RegisterPage(),
      ),
    );
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
                    children: const [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 80,
                        color: CommonColors.color_337eff,
                      ),
                      SizedBox(height: 16),
                      Text(
                        '168 聊天',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: CommonColors.color_333333,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '欢迎回来，请登录您的账号',
                        style: TextStyle(
                          fontSize: 14,
                          color: CommonColors.color_999999,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 60),

                // 手机号输入框
                TextFormField(
                  controller: _mobileController,
                  enabled: !_isLoading,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: '手机号',
                    hintText: '请输入手机号',
                    prefixIcon: const Icon(Icons.phone_android),
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
                      return '请输入手机号';
                    }
                    if (value.trim().length != 11) {
                      return '请输入正确的手机号';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 20),

                // 密码输入框
                TextFormField(
                  controller: _passwordController,
                  enabled: !_isLoading,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: '密码',
                    hintText: '请输入密码',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
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
                      return '请输入密码';
                    }
                    if (value.trim().length < 6) {
                      return '密码长度不能少于 6 位';
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
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
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

                const SizedBox(height: 16),

                // 注册按钮
                // TextButton(
                //   onPressed: _isLoading ? null : _navigateToRegister,
                //   child: const Text(
                //     '还没有账号？立即注册',
                //     style: TextStyle(
                //       fontSize: 14,
                //       color: CommonColors.color_337eff,
                //     ),
                //   ),
                // ),

                const SizedBox(height: 24),

                // 提示信息
                // Center(
                //   child: Container(
                //     padding: const EdgeInsets.all(16),
                //     decoration: BoxDecoration(
                //       color: Colors.blue.shade50,
                //       borderRadius: BorderRadius.circular(8),
                //     ),
                //     child: Column(
                //       crossAxisAlignment: CrossAxisAlignment.start,
                //       children: const [
                //         Text(
                //           '💡 提示',
                //           style: TextStyle(
                //             fontSize: 14,
                //             fontWeight: FontWeight.bold,
                //             color: CommonColors.color_337eff,
                //           ),
                //         ),
                //         SizedBox(height: 8),
                //         Text(
                //           '• 所有账号信息由服务端统一管理\n'
                //           '• 请妥善保管您的账号和密码',
                //           style: TextStyle(
                //             fontSize: 12,
                //             color: CommonColors.color_666666,
                //             height: 1.5,
                //           ),
                //         ),
                //       ],
                //     ),
                //   ),
                // ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
