// Copyright (c) 2024 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

/// API 配置类
/// 用于管理 API 基础地址和相关配置
class ApiConfig {
  // 开发环境 API 地址
  // static const String devBaseUrl = 'http://192.168.137.203:8168';
  static const String devBaseUrl = 'http://192.168.1.5:8168';
  
  // 生产环境 API 地址
  //static const String prodBaseUrl = 'https://q168api.witherelax.com';
  static const String prodBaseUrl = 'http://156.241.138.47';
  
  // 当前环境（默认开发环境）
  static bool isProduction = true;
  
  // 获取当前基础 URL
  static String get baseUrl => isProduction ? prodBaseUrl : devBaseUrl;
  
  // API 路径
  static const String apiPrefix = '/api';
  
  // 完整 API 地址
  static String get apiBaseUrl => '$baseUrl$apiPrefix';
  
  // 超时配置（秒）
  static const int connectTimeout = 30;
  static const int receiveTimeout = 30;
  static const int sendTimeout = 30;
  
  // Token 存储 Key
  static const String tokenKey = 'b1dc48289af25dca056352d0e34fad09';
  static const String accidKey = 'yunxin_accid';
  static const String userInfoKey = 'yunxin_user_info';
  
  
  /// 切换到生产环境
  static void switchToProduction() {
    isProduction = true;
  }
  
  /// 切换到开发环境
  static void switchToDevelopment() {
    isProduction = false;
  }
}

/// API 端点
class ApiEndpoints {
  // 认证相关
  static const String register = '/yunxinauth/register';
  static const String login = '/yunxinauth/login';
  static const String getUserInfo = '/yunxinauth/userinfo';
  static const String refreshToken = '/yunxinauth/refreshtoken';
  static const String updateProfile = '/yunxinauth/updateprofile';
  // 获取最新云信 IM token（公开接口，无需 Authorization，仅返回 NIM token）
  static const String getNimToken = '/yunxinauth/nimtoken';
  // 获取最新云信 IM token + NERoom room_token（需登录态，每次刷新双 token）
  static const String getImToken = '/yunxinauth/imtoken';
  
  // 群组相关
  static const String createGroup = '/yxgroup/create';
  static const String disbandGroup = '/yxgroup/disband';
  static const String getGroupList = '/yxgroup/lists';
  static const String getGroupInfo = '/yxgroup/info';
  static const String getGroupMembers = '/yxgroup/members';
  static const String addGroupMember = '/yxgroup/addmember';
  static const String removeGroupMember = '/yxgroup/removemember';
  static const String updateGroupInfo = '/yxgroup/update';
  // 群组同步（Flutter NIM SDK 事件触发，后端拉 NIM API 更新本地库）
  static const String syncGroup = '/yxgroup/sync';
  // 管理员角色同步（AddManager / RemoveManager 通知触发）
  static const String setGroupAdmin = '/yxgroup/setadmin';
  
  // 房间相关（如果需要）
  static const String createRoom = '/yxroom/create';
  static const String joinRoom = '/yxroom/join';
  static const String leaveRoom = '/yxroom/leave';
  static const String closeRoom = '/yxroom/close';
  static const String getRoomList = '/yxroom/lists';
  static const String getRoomInfo = '/yxroom/info';
}
