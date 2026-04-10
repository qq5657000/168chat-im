// Copyright (c) 2024 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:im_demo/src/config.dart';
import 'package:im_demo/src/home/home_page.dart';
import 'package:netease_common_ui/utils/color_utils.dart';
import 'package:nim_chatkit/im_kit_client.dart';
import 'package:nim_chatkit_callkit/nim_chatkit_callkit.dart';
import 'package:nim_core_v2/nim_core.dart';
import '../services/auth_service.dart';
import '../api/api_response.dart';
import '../room/room_kit_service.dart';

/// 注册页面
/// 调用服务端 API 进行注册，自动创建云信账号
class RegisterPage extends StatefulWidget {
  const RegisterPage({Key? key}) : super(key: key);

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _nicknameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  final AuthService _authService = AuthService();

  @override
  void dispose() {
    _mobileController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  /// 执行注册
  Future<void> _handleRegister() async {
    // 🔥 第一步：清除之前的错误信息
    setState(() {
      _errorMessage = null;
    });
    
    if (!_formKey.currentState!.validate()) {
      print('⚠️ 表单验证失败');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('表单验证失败，请检查输入'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final mobile = _mobileController.text.trim();
    final password = _passwordController.text.trim();
    final nickname = _nicknameController.text.trim();

    try {
      // 1. 调用服务端注册接口
      print('');
      print('🚀 ========== 注册页面：开始注册流程 ==========');
      print('手机号: $mobile');
      print('昵称: ${nickname.isNotEmpty ? nickname : '未设置'}');
      print('步骤 1: 调用服务端注册接口');
      
      Alog.d(tag: 'RegisterPage', content: '========== 开始注册流程 ==========');
      Alog.d(tag: 'RegisterPage', content: '手机号: $mobile, 昵称: $nickname');
      
      final response = await _authService.register(
        mobile: mobile,
        password: password,
        nickname: nickname.isNotEmpty ? nickname : null,
      );
      
      print('步骤 1 完成: 服务端响应 code=${response.code}, msg=${response.msg}');

      if (response.isSuccess && response.data != null) {
        final registerData = response.data!;
        final accid = registerData.user.accid;
        final nimToken = registerData.user.token;  // NIM IM SDK 专用 token
        // NERoomKit.authService.login() 底层使用 NIM IM 认证，
        // 所以 room_token = NIM IM token（两者相同），后端保持字段分离便于将来扩展
        final roomToken = registerData.user.roomToken ?? '';

        print('✅ 步骤 1 成功: 服务端注册成功');
        print('AccID: $accid');
        print('nimToken: ${nimToken.substring(0, nimToken.length.clamp(0, 8))}***');
        print('room_token: ${roomToken.isNotEmpty ? "${roomToken.substring(0, roomToken.length.clamp(0, 20))}..." : "（未获取，后端需配置 TokenServer）"}');
        
        Alog.d(tag: 'RegisterPage', content: '✅ 服务端注册成功: accid=$accid');

        // ⚠️ 重要：NERoomKit 必须在 nim_core_v2 之前登录（NIM SDK 单例冲突问题）
        // 2. 先登录 NERoomKit（使用 room_token，而非 NIM IM token）
        print('步骤 2: 先登录 NERoomKit（必须在 IM 前，使用 ${roomToken.isNotEmpty ? "room_token" : "nimToken(fallback)"}）');
        final roomLoginToken = roomToken.isNotEmpty ? roomToken : nimToken;
        final roomOk = await RoomKitService().login(accid, roomLoginToken);
        if (!roomOk) {
          print('⚠️ [RegisterPage] NERoomKit 登录失败（将继续登录 IM，房间功能可能不可用）');
        }
        print('NERoomKit 登录${roomOk ? "成功" : "失败"}: accid=$accid');

        // 3. 再使用 nimToken 登录云信 IM SDK
        print('步骤 3: 登录 nim_core_v2 IM SDK（使用 nimToken）');
        final imResult = await IMKitClient.loginIMWithResult(
          accid,
          nimToken,
          option: NIMLoginOption(
            syncLevel: NIMDataSyncLevel.dataSyncLevelBasic,
          ),
        );

        print('步骤 3 完成: 云信 SDK 响应 isSuccess=${imResult.isSuccess}');

        if (imResult.isSuccess) {
          print('✅ 步骤 3 成功: 云信 SDK 登录成功');
          print('步骤 4: 初始化 CallKit');
          
          // 4. 初始化 CallKit
          ChatKitCall.instance.init(
            appKey: IMDemoConfig.AppKey,
            accountId: accid,
          );

          print('✅ 步骤 4 成功: CallKit 初始化完成');
          print('步骤 5: 跳转到主页');
          print('========== 注册流程全部完成 ==========');
          print('');
          
          Alog.d(tag: 'RegisterPage', content: '✅ 云信 SDK 登录成功，跳转到主页');

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
          // 云信 SDK 登录失败
          print('❌ 步骤 3 失败: 云信 SDK 登录失败');
          print('错误码: ${imResult.code}');
          print('错误详情: ${imResult.errorDetails}');
          print('========== 注册流程失败 ==========');
          print('');
          
          setState(() {
            _errorMessage = '云信登录失败: ${imResult.errorDetails ?? '未知错误'} (code: ${imResult.code})';
            _isLoading = false;
          });
          Alog.e(tag: 'RegisterPage', content: '❌ 云信 SDK 登录失败: code=${imResult.code}');
        }
      } else {
        // 服务端注册失败
        print('❌ 步骤 1 失败: 服务端注册失败');
        print('错误信息: ${response.msg}');
        print('========== 注册流程失败 ==========');
        print('');
        
        setState(() {
          _errorMessage = response.msg;
          _isLoading = false;
        });
        Alog.e(tag: 'RegisterPage', content: '❌ 服务端注册失败: ${response.msg}');
      }
    } on ApiException catch (e) {
      print('❌ API 异常: ${e.message}');
      print('错误码: ${e.code}');
      print('========== 注册流程失败 ==========');
      print('');
      
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
      Alog.e(tag: 'RegisterPage', content: '❌ API 异常: ${e.message}');
    } catch (e) {
      print('❌ 未知异常: $e');
      print('异常类型: ${e.runtimeType}');
      print('========== 注册流程失败 ==========');
      print('');
      
      setState(() {
        _errorMessage = '注册异常: ${e.toString()}';
        _isLoading = false;
      });
      Alog.e(tag: 'RegisterPage', content: '❌ 注册异常: ${e.toString()}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('注册账号'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),

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

                const SizedBox(height: 16),

                // 昵称输入框
                TextFormField(
                  controller: _nicknameController,
                  enabled: !_isLoading,
                  decoration: InputDecoration(
                    labelText: '昵称（可选）',
                    hintText: '请输入昵称',
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
                      borderSide: const BorderSide(
                          color: CommonColors.color_337eff, width: 2),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // 密码输入框
                TextFormField(
                  controller: _passwordController,
                  enabled: !_isLoading,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: '密码',
                    hintText: '请输入密码（至少 6 位）',
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

                const SizedBox(height: 16),

                // 确认密码输入框
                TextFormField(
                  controller: _confirmPasswordController,
                  enabled: !_isLoading,
                  obscureText: _obscureConfirmPassword,
                  decoration: InputDecoration(
                    labelText: '确认密码',
                    hintText: '请再次输入密码',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
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
                      return '请再次输入密码';
                    }
                    if (value.trim() != _passwordController.text.trim()) {
                      return '两次输入的密码不一致';
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

                // 注册按钮
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleRegister,
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
                          '注册',
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
                          '💡 注册说明',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: CommonColors.color_337eff,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '• 注册后将自动登录并跳转到主页',
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
