// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:im_demo/src/config.dart';
import 'package:im_demo/src/home/home_page.dart';
import 'package:im_demo/src/auth/login_page_new.dart';
import 'package:im_demo/src/room/room_kit_service.dart';
import 'package:nim_chatkit/im_kit_client.dart';
import 'package:nim_chatkit_callkit/nim_chatkit_callkit.dart';
import 'package:nim_core_v2/nim_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashPage extends StatefulWidget {
  final Uint8List? deviceToken;

  const SplashPage({Key? key, this.deviceToken}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _SplashState();
}

class _SplashState extends State<SplashPage> {
  bool haveLogin = false;

  @override
  Widget build(BuildContext context) {
    if (haveLogin) {
      return const HomePage();
    }
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _doInit(IMDemoConfig.AppKey);
  }

  void updateAPNsToken() {
    if (NimCore.instance.isInitialized &&
        Platform.isIOS &&
        widget.deviceToken != null) {
      NimCore.instance.apnsService.updateApnsToken(widget.deviceToken!);
    }
  }

  /// init depends package for app
  void _doInit(String appKey) async {
    print('SplashPage: 开始初始化 SDK');
    try {
      var options = await NIMSDKOptionsConfig.getSDKOptions(appKey);

      final initFuture = IMKitClient.init(appKey, options);
      final timeoutFuture = Future.delayed(const Duration(seconds: 15), () => false);
      final success = await Future.any([initFuture, timeoutFuture]);

      if (success) {
        print('SplashPage: IM SDK 初始化成功');
        // 同步初始化 NERoomKit（使用互动直播专属 AppKey，非 IM AppKey）
        final roomAppKey = IMDemoConfig.RoomAppKey.isNotEmpty
            ? IMDemoConfig.RoomAppKey
            : appKey; // 若未配置互动直播 AppKey，回退用 IM AppKey（会导致 402）
        await RoomKitService().initialize(roomAppKey);
        print('SplashPage: NERoomKit 初始化完成');
        await startLogin();
      } else {
        print('SplashPage: SDK 初始化超时');
        _navigateToLoginPage();
      }
    } catch (e) {
      print('SplashPage: SDK 初始化异常: $e');
      _navigateToLoginPage();
    }
  }

  // 检查并执行自动登录
  Future<void> startLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool('is_logged_in') ?? false;
      final account = prefs.getString('account') ?? '';
      // 读取 NIM IM token（独立 key，避免与 FastAdmin JWT 冲突）
      final nimToken = prefs.getString('nim_im_token') ?? '';
      // 读取 NERoomKit 专用 room_token（动态签名 token，TTL 24h）
      final roomToken = prefs.getString('room_token') ?? '';

      if (isLoggedIn && account.isNotEmpty && nimToken.isNotEmpty) {
        print('SplashPage: 自动登录: $account');
        print('SplashPage: nimToken=${nimToken.substring(0, nimToken.length.clamp(0, 8))}***, room_token=${roomToken.isNotEmpty ? "${roomToken.substring(0, roomToken.length.clamp(0, 20))}..." : "（未保存）"}');
        await _performLogin(account, nimToken, roomToken);
      } else {
        print('SplashPage: 无登录信息，跳转登录页');
        _navigateToLoginPage();
      }
    } catch (e) {
      print('SplashPage: 检查登录状态异常: $e');
      _navigateToLoginPage();
    }
  }

  // 执行自动登录
  Future<void> _performLogin(String account, String nimToken, String roomToken) async {
    try {
      // ⚠️ 重要：NERoomKit 必须在 nim_core_v2 之前登录（NIM SDK 单例冲突问题）
      // 若 nim_core_v2 先调用 loginIMWithResult，会占用 NIM SDK 单例，
      // 导致 NERoomKit 认证被阻断，返回 code=402 Token不正确。
      // NERoomKit 使用 room_token（动态签名），不是 NIM IM 静态 token
      final roomLoginToken = roomToken.isNotEmpty ? roomToken : nimToken;
      print('SplashPage: 步骤1 先登录 NERoomKit（使用 ${roomToken.isNotEmpty ? "room_token" : "nimToken(fallback)"}）');
      final roomOk = await RoomKitService().login(account, roomLoginToken);
      print('SplashPage: NERoomKit 自动登录${roomOk ? "成功" : "失败"}');

      // 步骤2：再登录 nim_core_v2 IM SDK（使用 nimToken）
      print('SplashPage: 步骤2 登录 nim_core_v2 IM SDK（使用 nimToken）');
      final result = await IMKitClient.loginIMWithResult(
        account,
        nimToken,
        option: NIMLoginOption(
          syncLevel: NIMDataSyncLevel.dataSyncLevelBasic,
        ),
      );

      if (result.isSuccess) {
        print('SplashPage: 自动登录成功');
        updateAPNsToken();
        // 初始化 CallKit
        ChatKitCall.instance.init(
          appKey: IMDemoConfig.AppKey,
          accountId: account,
        );
        if (mounted) {
          setState(() {
            haveLogin = true;
          });
        }
      } else {
        print('SplashPage: 自动登录失败: code=${result.code}');
        await _clearLoginInfo();
        _navigateToLoginPage();
      }
    } catch (e) {
      print('SplashPage: 登录异常: $e');
      await _clearLoginInfo();
      _navigateToLoginPage();
    }
  }

  // 清除登录信息
  Future<void> _clearLoginInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('is_logged_in');
      await prefs.remove('account');
      await prefs.remove('token');
    } catch (_) {}
  }

  // 跳转到登录页面
  void _navigateToLoginPage() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => const LoginPageNew(),
      ),
    );
  }
}
