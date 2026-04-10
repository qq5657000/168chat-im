// Copyright (c) 2024 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

/// 群组模型
class GroupModel {
  final int id;
  final String groupId; // 云信群组 ID
  final String groupName;
  final String? groupAvatar;
  final String ownerAccid; // 群主 accid
  final String? announcement; // 群公告
  final String? intro; // 群介绍
  final int memberCount; // 成员数量
  final int maxMemberCount; // 最大成员数
  final int joinMode; // 加入方式：0-自由加入 1-需要验证 2-禁止加入
  final int inviteMode; // 邀请方式：0-管理员 1-所有人
  final int updateMode; // 群信息修改权限：0-管理员 1-所有人
  final int status; // 状态：1-正常 0-已解散
  final String? ex; // 扩展字段
  final String? createdAt;
  final String? updatedAt;
  
  GroupModel({
    required this.id,
    required this.groupId,
    required this.groupName,
    this.groupAvatar,
    required this.ownerAccid,
    this.announcement,
    this.intro,
    this.memberCount = 0,
    this.maxMemberCount = 200,
    this.joinMode = 0,
    this.inviteMode = 1,
    this.updateMode = 0,
    this.status = 1,
    this.ex,
    this.createdAt,
    this.updatedAt,
  });
  
  /// 从 JSON 创建
  factory GroupModel.fromJson(Map<String, dynamic> json) {
    return GroupModel(
      id: json['id'] as int? ?? 0,
      groupId: json['group_id'] as String? ?? '',
      groupName: json['group_name'] as String? ?? '',
      groupAvatar: json['group_avatar'] as String?,
      ownerAccid: json['owner_accid'] as String? ?? '',
      announcement: json['announcement'] as String?,
      intro: json['intro'] as String?,
      memberCount: json['member_count'] as int? ?? 0,
      maxMemberCount: json['max_member_count'] as int? ?? 200,
      joinMode: json['join_mode'] as int? ?? 0,
      inviteMode: json['invite_mode'] as int? ?? 1,
      updateMode: json['update_mode'] as int? ?? 0,
      status: json['status'] as int? ?? 1,
      ex: json['ex'] as String?,
      createdAt: json['created_at'] as String? ?? json['createtime'] as String?,
      updatedAt: json['updated_at'] as String? ?? json['updatetime'] as String?,
    );
  }
  
  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'group_id': groupId,
      'group_name': groupName,
      'group_avatar': groupAvatar,
      'owner_accid': ownerAccid,
      'announcement': announcement,
      'intro': intro,
      'member_count': memberCount,
      'max_member_count': maxMemberCount,
      'join_mode': joinMode,
      'invite_mode': inviteMode,
      'update_mode': updateMode,
      'status': status,
      'ex': ex,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
  
  /// 复制并修改
  GroupModel copyWith({
    int? id,
    String? groupId,
    String? groupName,
    String? groupAvatar,
    String? ownerAccid,
    String? announcement,
    String? intro,
    int? memberCount,
    int? maxMemberCount,
    int? joinMode,
    int? inviteMode,
    int? updateMode,
    int? status,
    String? ex,
    String? createdAt,
    String? updatedAt,
  }) {
    return GroupModel(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      groupName: groupName ?? this.groupName,
      groupAvatar: groupAvatar ?? this.groupAvatar,
      ownerAccid: ownerAccid ?? this.ownerAccid,
      announcement: announcement ?? this.announcement,
      intro: intro ?? this.intro,
      memberCount: memberCount ?? this.memberCount,
      maxMemberCount: maxMemberCount ?? this.maxMemberCount,
      joinMode: joinMode ?? this.joinMode,
      inviteMode: inviteMode ?? this.inviteMode,
      updateMode: updateMode ?? this.updateMode,
      status: status ?? this.status,
      ex: ex ?? this.ex,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
  
  @override
  String toString() {
    return 'GroupModel{id: $id, groupId: $groupId, groupName: $groupName}';
  }
}

/// 群成员模型
class GroupMemberModel {
  final int id;
  final String groupId;
  final String accid;
  final String? nickname;
  final String? avatar;
  final int type; // 0-普通成员 1-管理员 2-群主
  final int muteType; // 0-正常 1-禁言
  final String? joinedAt;
  
  GroupMemberModel({
    required this.id,
    required this.groupId,
    required this.accid,
    this.nickname,
    this.avatar,
    this.type = 0,
    this.muteType = 0,
    this.joinedAt,
  });
  
  factory GroupMemberModel.fromJson(Map<String, dynamic> json) {
    return GroupMemberModel(
      id: json['id'] as int? ?? 0,
      groupId: json['group_id'] as String? ?? '',
      accid: json['accid'] as String? ?? '',
      nickname: json['nickname'] as String?,
      avatar: json['avatar'] as String?,
      type: json['type'] as int? ?? 0,
      muteType: json['mute_type'] as int? ?? 0,
      joinedAt: json['joined_at'] as String? ?? json['createtime'] as String?,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'group_id': groupId,
      'accid': accid,
      'nickname': nickname,
      'avatar': avatar,
      'type': type,
      'mute_type': muteType,
      'joined_at': joinedAt,
    };
  }
  
  /// 是否是群主
  bool get isOwner => type == 2;
  
  /// 是否是管理员
  bool get isAdmin => type == 1;
  
  /// 是否被禁言
  bool get isMuted => muteType == 1;
  
  @override
  String toString() {
    return 'GroupMemberModel{groupId: $groupId, accid: $accid, type: $type}';
  }
}
