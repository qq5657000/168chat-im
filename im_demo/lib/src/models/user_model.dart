// Copyright (c) 2024 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

/// 用户模型
class UserModel {
  final int id;
  final String accid;
  final String token;
  /// NERoomKit (NERTC/互动直播) 专用 token
  /// 由后端使用 NERTC TokenServer 动态签名生成，与 NIM IM token 格式不同
  final String? roomToken;
  final String? nickname;
  final String? avatar;
  final String? mobile;
  final String? email;
  final int? gender; // 0-未知 1-男 2-女
  final String? sign; // 个性签名
  final String? ex; // 扩展字段
  final int status; // 状态：1-正常 0-禁用
  final String? createdAt;
  final String? updatedAt;
  
  UserModel({
    required this.id,
    required this.accid,
    required this.token,
    this.roomToken,
    this.nickname,
    this.avatar,
    this.mobile,
    this.email,
    this.gender,
    this.sign,
    this.ex,
    this.status = 1,
    this.createdAt,
    this.updatedAt,
  });
  
  /// 从 JSON 创建
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as int? ?? 0,
      accid: json['accid'] as String? ?? '',
      token: json['token'] as String? ?? '',
      roomToken: json['room_token'] as String?,
      nickname: json['nickname'] as String?,
      avatar: json['avatar'] as String?,
      mobile: json['mobile'] as String?,
      email: json['email'] as String?,
      gender: json['gender'] as int?,
      sign: json['sign'] as String?,
      ex: json['ex'] as String?,
      status: json['status'] as int? ?? 1,
      createdAt: json['created_at'] as String? ?? json['createtime'] as String?,
      updatedAt: json['updated_at'] as String? ?? json['updatetime'] as String?,
    );
  }
  
  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'accid': accid,
      'token': token,
      'room_token': roomToken,
      'nickname': nickname,
      'avatar': avatar,
      'mobile': mobile,
      'email': email,
      'gender': gender,
      'sign': sign,
      'ex': ex,
      'status': status,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
  
  /// 复制并修改
  UserModel copyWith({
    int? id,
    String? accid,
    String? token,
    String? roomToken,
    String? nickname,
    String? avatar,
    String? mobile,
    String? email,
    int? gender,
    String? sign,
    String? ex,
    int? status,
    String? createdAt,
    String? updatedAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      accid: accid ?? this.accid,
      token: token ?? this.token,
      roomToken: roomToken ?? this.roomToken,
      nickname: nickname ?? this.nickname,
      avatar: avatar ?? this.avatar,
      mobile: mobile ?? this.mobile,
      email: email ?? this.email,
      gender: gender ?? this.gender,
      sign: sign ?? this.sign,
      ex: ex ?? this.ex,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
  
  @override
  String toString() {
    return 'UserModel{id: $id, accid: $accid, nickname: $nickname}';
  }
}

/// 登录响应模型
class LoginResponse {
  final UserModel user;
  final String token;
  
  LoginResponse({
    required this.user,
    required this.token,
  });
  
  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      user: UserModel.fromJson(json['user'] as Map<String, dynamic>? ?? json),
      token: json['token'] as String? ?? json['user']?['token'] as String? ?? '',
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'user': user.toJson(),
      'token': token,
    };
  }
}
