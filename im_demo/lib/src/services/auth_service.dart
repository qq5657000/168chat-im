// Copyright (c) 2024 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunxin_alog/yunxin_alog.dart';
import '../api/api_client.dart';
import '../api/api_config.dart';
import '../api/api_response.dart';
import '../models/user_model.dart';

/// 认证服务
/// 处理用户注册、登录、获取用户信息等
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();
  
  final ApiClient _apiClient = ApiClient();
  
  // 当前用户信息缓存
  UserModel? _currentUser;
  
  /// 获取当前用户
  UserModel? get currentUser => _currentUser;
  
  /// 是否已登录
  bool get isLoggedIn => _currentUser != null;
  
  /// 用户注册
  /// 
  /// [mobile] 手机号
  /// [password] 密码
  /// [nickname] 昵称（可选）
  /// [avatar] 头像（可选）
  /// 
  /// 返回：包含用户信息和 Token 的响应
  Future<ApiResponse<LoginResponse>> register({
    required String mobile,
    required String password,
    String? nickname,
    String? avatar,
  }) async {
    try {
      print('');
      print('📝 ========== 开始注册 ==========');
      print('手机号: $mobile');
      print('密码: ${password.replaceAll(RegExp(r'.'), '*')}');
      print('昵称: ${nickname ?? '未设置'}');
      
      Alog.d(tag: 'AuthService', content: '========== 开始注册 ==========');
      Alog.d(tag: 'AuthService', content: 'Mobile: $mobile, Nickname: $nickname');
      
      final requestData = {
        'username': mobile,  // 🔥 修改：后端需要 username 字段,使用手机号作为用户名
        'mobile': mobile,
        'password': password,
        if (nickname != null) 'nickname': nickname,
        if (avatar != null) 'avatar': avatar,
      };
      
      print('请求数据: $requestData');
      
      final response = await _apiClient.post<LoginResponse>(
        ApiEndpoints.register,
        data: requestData,
        needAuth: false,
        fromJsonT: (json) => LoginResponse.fromJson(json as Map<String, dynamic>),
      );
      
      if (response.isSuccess && response.data != null) {
        // 保存用户信息和 Token
        await _saveUserInfo(response.data!);
        
        print('✅ 注册成功！');
        print('AccID: ${response.data!.user.accid}');
        print('Token: ${response.data!.user.token.substring(0, 20)}...');
        print('========== 注册完成 ==========');
        print('');
        
        Alog.d(tag: 'AuthService', content: '✅ Register success: ${response.data!.user.accid}');
      } else {
        print('❌ 注册失败: ${response.msg}');
        print('========== 注册完成 ==========');
        print('');
        
        Alog.e(tag: 'AuthService', content: '❌ Register failed: ${response.msg}');
      }
      
      return response;
    } catch (e) {
      print('❌ 注册异常: $e');
      print('异常类型: ${e.runtimeType}');
      print('========== 注册完成 ==========');
      print('');
      
      Alog.e(tag: 'AuthService', content: 'Register exception: $e');
      rethrow;
    }
  }
  
  /// 用户登录
  /// 
  /// [mobile] 手机号
  /// [password] 密码
  /// 
  /// 返回：包含用户信息和 Token 的响应
  Future<ApiResponse<LoginResponse>> login({
    required String mobile,
    required String password,
  }) async {
    try {
      print('');
      print('🔐 ========== 开始登录 ==========');
      print('手机号: $mobile');
      print('密码: ${password.replaceAll(RegExp(r'.'), '*')}');
      
      Alog.d(tag: 'AuthService', content: '========== 开始登录 ==========');
      Alog.d(tag: 'AuthService', content: 'Mobile: $mobile');
      
      final response = await _apiClient.post<LoginResponse>(
        ApiEndpoints.login,
        data: {
          'account': mobile,  // 🔥 修改：后端接收的字段名是 account,不是 mobile
          'password': password,
        },
        needAuth: false,
        fromJsonT: (json) => LoginResponse.fromJson(json as Map<String, dynamic>),
      );
      
      if (response.isSuccess && response.data != null) {
        // 保存用户信息和 Token
        await _saveUserInfo(response.data!);
        
        print('✅ 登录成功！');
        print('AccID: ${response.data!.user.accid}');
        print('Token: ${response.data!.user.token.substring(0, 20)}...');
        print('========== 登录完成 ==========');
        print('');
        
        Alog.d(tag: 'AuthService', content: '✅ Login success: ${response.data!.user.accid}');
      } else {
        print('❌ 登录失败: ${response.msg}');
        print('========== 登录完成 ==========');
        print('');
        
        Alog.e(tag: 'AuthService', content: '❌ Login failed: ${response.msg}');
      }
      
      return response;
    } catch (e) {
      print('❌ 登录异常: $e');
      print('异常类型: ${e.runtimeType}');
      print('========== 登录完成 ==========');
      print('');
      
      Alog.e(tag: 'AuthService', content: 'Login exception: $e');
      rethrow;
    }
  }
  
  /// 获取当前用户信息
  /// 
  /// 返回：用户信息
  Future<ApiResponse<UserModel>> getUserInfo() async {
    try {
      Alog.d(tag: 'AuthService', content: 'Get user info');
      
      final response = await _apiClient.get<UserModel>(
        ApiEndpoints.getUserInfo,
        needAuth: true,
        fromJsonT: (json) => UserModel.fromJson(json as Map<String, dynamic>),
      );
      
      if (response.isSuccess && response.data != null) {
        _currentUser = response.data;
        // 更新本地存储
        await _saveUserInfoToLocal(response.data!);
        Alog.d(tag: 'AuthService', content: 'Get user info success: ${response.data!.accid}');
      }
      
      return response;
    } catch (e) {
      Alog.e(tag: 'AuthService', content: 'Get user info failed: $e');
      rethrow;
    }
  }
  
  /// 更新用户资料
  /// 
  /// [nickname] 昵称
  /// [avatar] 头像
  /// [gender] 性别
  /// [sign] 个性签名
  /// 
  /// 返回：更新后的用户信息
  Future<ApiResponse<UserModel>> updateProfile({
    String? nickname,
    String? avatar,
    int? gender,
    String? sign,
  }) async {
    try {
      Alog.d(tag: 'AuthService', content: 'Update profile');
      
      final data = <String, dynamic>{};
      if (nickname != null) data['nickname'] = nickname;
      if (avatar != null) data['avatar'] = avatar;
      if (gender != null) data['gender'] = gender;
      if (sign != null) data['sign'] = sign;
      
      final response = await _apiClient.post<UserModel>(
        ApiEndpoints.updateProfile,
        data: data,
        needAuth: true,
        fromJsonT: (json) => UserModel.fromJson(json as Map<String, dynamic>),
      );
      
      if (response.isSuccess && response.data != null) {
        _currentUser = response.data;
        await _saveUserInfoToLocal(response.data!);
        Alog.d(tag: 'AuthService', content: 'Update profile success');
      }
      
      return response;
    } catch (e) {
      Alog.e(tag: 'AuthService', content: 'Update profile failed: $e');
      rethrow;
    }
  }
  
  /// 刷新 Token
  Future<ApiResponse<LoginResponse>> refreshToken() async {
    try {
      Alog.d(tag: 'AuthService', content: 'Refresh token');
      
      final response = await _apiClient.post<LoginResponse>(
        ApiEndpoints.refreshToken,
        needAuth: true,
        fromJsonT: (json) => LoginResponse.fromJson(json as Map<String, dynamic>),
      );
      
      if (response.isSuccess && response.data != null) {
        await _saveUserInfo(response.data!);
        Alog.d(tag: 'AuthService', content: 'Refresh token success');
      }
      
      return response;
    } catch (e) {
      Alog.e(tag: 'AuthService', content: 'Refresh token failed: $e');
      rethrow;
    }
  }
  
  /// 退出登录
  Future<void> logout() async {
    try {
      Alog.d(tag: 'AuthService', content: 'Logout');
      
      // 清除本地数据
      _currentUser = null;
      await _apiClient.clearToken();
      
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(ApiConfig.userInfoKey);
    await prefs.remove('account');
    await prefs.remove('nim_im_token');
    await prefs.remove('room_token');
    await prefs.remove('is_logged_in');
      
      Alog.d(tag: 'AuthService', content: 'Logout success');
    } catch (e) {
      Alog.e(tag: 'AuthService', content: 'Logout failed: $e');
      rethrow;
    }
  }
  
  /// 从本地加载用户信息
  Future<void> loadUserInfoFromLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userInfoJson = prefs.getString(ApiConfig.userInfoKey);
      
      if (userInfoJson != null && userInfoJson.isNotEmpty) {
        final json = jsonDecode(userInfoJson) as Map<String, dynamic>;
        _currentUser = UserModel.fromJson(json);
        Alog.d(tag: 'AuthService', content: 'Load user info from local: ${_currentUser!.accid}');
      }
    } catch (e) {
      Alog.e(tag: 'AuthService', content: 'Load user info from local failed: $e');
    }
  }
  
  /// 保存用户信息（包括 Token）
  Future<void> _saveUserInfo(LoginResponse loginResponse) async {
    _currentUser = loginResponse.user;
    
    // 保存 Token
    await _apiClient.saveToken(loginResponse.token);
    
    // 保存用户信息
    await _saveUserInfoToLocal(loginResponse.user);
    
    // 保存云信相关信息
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(ApiConfig.accidKey, loginResponse.user.accid);
    await prefs.setString('account', loginResponse.user.accid);
    // ⚠️ 使用独立 key 'nim_im_token' 存 NIM IM token，避免与 FastAdmin JWT ('token') 冲突
    await prefs.setString('nim_im_token', loginResponse.user.token);
    await prefs.setBool('is_logged_in', true);
    // 保存昵称（供 NERoomKit joinRoom/createRoom 的 userName 字段使用）
    final nickname = loginResponse.user.nickname ?? loginResponse.user.accid;
    if (nickname.isNotEmpty) {
      await prefs.setString('nickname', nickname);
    }

    // 保存 NERoomKit 专用 room_token（NERTC token，非 NIM IM token）
    final roomToken = loginResponse.user.roomToken ?? '';
    if (roomToken.isNotEmpty) {
      await prefs.setString('room_token', roomToken);
      print('✅ [AuthService] 已保存 room_token (${roomToken.substring(0, roomToken.length.clamp(0, 20))}...)');
    } else {
      print('⚠️ [AuthService] room_token 为空，NERoomKit 将使用 NIM IM token（可能导致 402）');
    }
  }

  /// 读取 NERoomKit 专用 room_token（从本地存储）
  Future<String> getRoomToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('room_token') ?? '';
  }

  /// 向后端请求最新云信 IM Token + NERoom room_token（双 token 刷新）
  ///
  /// 调用需要登录态的接口 /yunxinauth/imtoken：
  ///   1. 后端刷新 NIM IM token（refreshToken）
  ///   2. 后端调用 roomkit.netease.im/roomkit/v1/login 获取 NERoom room_token
  ///   3. 返回 { accid, token(NIM), room_token(NERoom) }
  ///
  /// 返回 Map 包含：
  ///   accid      : 用户 accid
  ///   token      : 最新 NIM IM token（供 nim_core_v2 使用）
  ///   room_token : 最新 NERoom room_token（供 NERoomKit.authService.login 使用）
  Future<Map<String, String>> getImToken() async {
    final prefs = await SharedPreferences.getInstance();
    final localAccid = prefs.getString('account') ?? '';

    print('🔑 [AuthService] 向后端刷新双 token（NIM + NERoom room_token）: accid=$localAccid');

    try {
      // needAuth=true：携带 FastAdmin Bearer token（用户必须已登录）
      final response = await _apiClient.get<Map<String, dynamic>>(
        ApiEndpoints.getImToken,
        needAuth: true,
        fromJsonT: (json) => (json as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, v?.toString() ?? ''),
        ),
      );

      if (response.isSuccess && response.data != null) {
        final accid     = response.data!['accid']      ?? '';
        final nimToken  = response.data!['token']      ?? '';
        final roomToken = response.data!['room_token'] ?? '';

        print('✅ [AuthService] 双 token 刷新成功:');
        print('   accid      = $accid');
        print('   nimToken   = ${nimToken.length > 8 ? "${nimToken.substring(0, 8)}***" : "(空)"}');
        print('   room_token = ${roomToken.isNotEmpty ? "${roomToken.substring(0, roomToken.length.clamp(0, 20))}..." : "(空，NERoom 接口失败)"}');

        // 更新本地缓存
        if (nimToken.isNotEmpty) {
          await prefs.setString('nim_im_token', nimToken);
        }
        if (roomToken.isNotEmpty) {
          await prefs.setString('room_token', roomToken);
          print('✅ [AuthService] room_token 已更新到本地缓存');
        } else {
          print('⚠️ [AuthService] room_token 为空，保留本地缓存旧值');
        }

        return {
          'accid':      accid,
          'token':      nimToken,
          'room_token': roomToken,
        };
      } else {
        print('❌ [AuthService] 双 token 刷新失败: ${response.msg}，回退使用本地缓存');
        return {
          'accid':      localAccid,
          'token':      prefs.getString('nim_im_token') ?? '',
          'room_token': prefs.getString('room_token')   ?? '',
        };
      }
    } catch (e) {
      print('❌ [AuthService] 双 token 刷新异常: $e，回退使用本地缓存');
      return {
        'accid':      localAccid,
        'token':      prefs.getString('nim_im_token') ?? '',
        'room_token': prefs.getString('room_token')   ?? '',
      };
    }
  }
  
  /// 保存用户信息到本地
  Future<void> _saveUserInfoToLocal(UserModel user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userInfoJson = jsonEncode(user.toJson());
      await prefs.setString(ApiConfig.userInfoKey, userInfoJson);
    } catch (e) {
      Alog.e(tag: 'AuthService', content: 'Save user info to local failed: $e');
    }
  }
}
