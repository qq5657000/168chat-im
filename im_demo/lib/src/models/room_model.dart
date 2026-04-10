// Copyright (c) 2024 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

/// 房间模型（NERoom）
class RoomModel {
  final int id;
  final String roomId; // 云信房间 ID（varchar 64，格式：时间戳_随机4位）
  final String roomName;
  final String? roomAvatar;
  final String ownerAccid; // 房主 accid
  final String ownerNickname; // 房主昵称（用于横幅展示）
  final String groupId; // 关联群组 ID（fa_im_group.tid 字符串形式，"0"=未关联）
  final String? subject; // 房间主题
  final int roomType; // 房间类型：0=普通 1=听课 2=会议
  final int maxMembers; // 最大成员数（从 DB 读取，默认 100）
  final int currentMembers; // 当前在线人数
  final int status; // 状态：1-进行中 0-已结束
  final String? ex; // 扩展字段
  final String? createdAt;
  final String? updatedAt;

  RoomModel({
    required this.id,
    required this.roomId,
    required this.roomName,
    this.roomAvatar,
    required this.ownerAccid,
    this.ownerNickname = '',
    this.groupId = '0',
    this.subject,
    this.roomType = 1,
    this.maxMembers = 100,
    this.currentMembers = 0,
    this.status = 1,
    this.ex,
    this.createdAt,
    this.updatedAt,
  });

  /// 从 JSON 创建（对应 PHP formatRoom() 返回格式）
  factory RoomModel.fromJson(Map<String, dynamic> json) {
    return RoomModel(
      id: json['id'] as int? ?? 0,
      roomId: json['room_id'] as String? ?? '',
      roomName: json['room_name'] as String? ?? '',
      roomAvatar: json['room_avatar'] as String?,
      ownerAccid: json['owner_accid'] as String? ?? '',
      ownerNickname: json['owner_nickname'] as String? ?? '',
      groupId: json['group_id'] as String? ?? '0',
      subject: json['subject'] as String?,
      roomType: json['room_type'] as int? ?? 1,
      maxMembers: json['max_members'] as int? ?? 100,
      currentMembers: json['current_members'] as int? ?? 0,
      status: json['status'] as int? ?? 1,
      ex: json['ex'] as String?,
      createdAt:
          json['created_at'] as String? ?? json['createtime'] as String?,
      updatedAt:
          json['updated_at'] as String? ?? json['updatetime'] as String?,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'room_id': roomId,
      'room_name': roomName,
      'room_avatar': roomAvatar,
      'owner_accid': ownerAccid,
      'owner_nickname': ownerNickname,
      'group_id': groupId,
      'subject': subject,
      'room_type': roomType,
      'max_members': maxMembers,
      'current_members': currentMembers,
      'status': status,
      'ex': ex,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  /// 复制并修改
  RoomModel copyWith({
    int? id,
    String? roomId,
    String? roomName,
    String? roomAvatar,
    String? ownerAccid,
    String? ownerNickname,
    String? groupId,
    String? subject,
    int? roomType,
    int? maxMembers,
    int? currentMembers,
    int? status,
    String? ex,
    String? createdAt,
    String? updatedAt,
  }) {
    return RoomModel(
      id: id ?? this.id,
      roomId: roomId ?? this.roomId,
      roomName: roomName ?? this.roomName,
      roomAvatar: roomAvatar ?? this.roomAvatar,
      ownerAccid: ownerAccid ?? this.ownerAccid,
      ownerNickname: ownerNickname ?? this.ownerNickname,
      groupId: groupId ?? this.groupId,
      subject: subject ?? this.subject,
      roomType: roomType ?? this.roomType,
      maxMembers: maxMembers ?? this.maxMembers,
      currentMembers: currentMembers ?? this.currentMembers,
      status: status ?? this.status,
      ex: ex ?? this.ex,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 是否已满员
  bool get isFull => currentMembers >= maxMembers;

  /// 是否进行中
  bool get isActive => status == 1;

  @override
  String toString() {
    return 'RoomModel{id: $id, roomId: $roomId, roomName: $roomName, groupId: $groupId}';
  }
}
