// Copyright (c) 2024 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'package:yunxin_alog/yunxin_alog.dart';
import '../api/api_client.dart';
import '../api/api_config.dart';
import '../api/api_response.dart';
import '../models/group_model.dart';

/// 群组服务
/// 处理群组创建、解散、成员管理等
class GroupService {
  static final GroupService _instance = GroupService._internal();
  factory GroupService() => _instance;
  GroupService._internal();
  
  final ApiClient _apiClient = ApiClient();
  
  /// 创建群组
  /// 
  /// [groupName] 群组名称
  /// [groupAvatar] 群组头像（可选）
  /// [intro] 群介绍（可选）
  /// [announcement] 群公告（可选）
  /// [memberAccids] 初始成员 accid 列表（可选）
  /// 
  /// 返回：创建的群组信息
  Future<ApiResponse<GroupModel>> createGroup({
    required String groupName,
    String? groupAvatar,
    String? intro,
    String? announcement,
    List<String>? memberAccids,
  }) async {
    try {
      Alog.d(tag: 'GroupService', content: 'Create group: $groupName');
      
      final data = <String, dynamic>{
        'group_name': groupName,
      };
      
      if (groupAvatar != null) data['group_avatar'] = groupAvatar;
      if (intro != null) data['intro'] = intro;
      if (announcement != null) data['announcement'] = announcement;
      if (memberAccids != null && memberAccids.isNotEmpty) {
        data['member_accids'] = memberAccids;
      }
      
      final response = await _apiClient.post<GroupModel>(
        ApiEndpoints.createGroup,
        data: data,
        needAuth: true,
        fromJsonT: (json) => GroupModel.fromJson(json as Map<String, dynamic>),
      );
      
      if (response.isSuccess) {
        Alog.d(tag: 'GroupService', content: 'Create group success: ${response.data?.groupId}');
      }
      
      return response;
    } catch (e) {
      Alog.e(tag: 'GroupService', content: 'Create group failed: $e');
      rethrow;
    }
  }
  
  /// 解散群组
  /// 
  /// [groupId] 群组 ID
  /// 
  /// 返回：操作结果
  Future<ApiResponse<dynamic>> disbandGroup(String groupId) async {
    try {
      Alog.d(tag: 'GroupService', content: 'Disband group: $groupId');
      
      final response = await _apiClient.post<dynamic>(
        ApiEndpoints.disbandGroup,
        data: {'group_id': groupId},
        needAuth: true,
      );
      
      if (response.isSuccess) {
        Alog.d(tag: 'GroupService', content: 'Disband group success');
      }
      
      return response;
    } catch (e) {
      Alog.e(tag: 'GroupService', content: 'Disband group failed: $e');
      rethrow;
    }
  }
  
  /// 获取群组列表
  /// 
  /// [page] 页码（从 1 开始）
  /// [pageSize] 每页数量
  /// 
  /// 返回：群组列表
  Future<ApiResponse<List<GroupModel>>> getGroupList({
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      Alog.d(tag: 'GroupService', content: 'Get group list: page=$page');
      
      final response = await _apiClient.get<List<GroupModel>>(
        ApiEndpoints.getGroupList,
        queryParameters: {
          'page': page,
          'page_size': pageSize,
        },
        needAuth: true,
        fromJsonT: (json) {
          if (json is List) {
            return json.map((item) => GroupModel.fromJson(item as Map<String, dynamic>)).toList();
          }
          return <GroupModel>[];
        },
      );
      
      if (response.isSuccess) {
        Alog.d(tag: 'GroupService', content: 'Get group list success: ${response.data?.length ?? 0} groups');
      }
      
      return response;
    } catch (e) {
      Alog.e(tag: 'GroupService', content: 'Get group list failed: $e');
      rethrow;
    }
  }
  
  /// 获取群组信息
  /// 
  /// [groupId] 群组 ID
  /// 
  /// 返回：群组信息
  Future<ApiResponse<GroupModel>> getGroupInfo(String groupId) async {
    try {
      Alog.d(tag: 'GroupService', content: 'Get group info: $groupId');
      
      final response = await _apiClient.get<GroupModel>(
        ApiEndpoints.getGroupInfo,
        queryParameters: {'group_id': groupId},
        needAuth: true,
        fromJsonT: (json) => GroupModel.fromJson(json as Map<String, dynamic>),
      );
      
      if (response.isSuccess) {
        Alog.d(tag: 'GroupService', content: 'Get group info success');
      }
      
      return response;
    } catch (e) {
      Alog.e(tag: 'GroupService', content: 'Get group info failed: $e');
      rethrow;
    }
  }
  
  /// 获取群成员列表
  /// 
  /// [groupId] 群组 ID
  /// 
  /// 返回：群成员列表
  Future<ApiResponse<List<GroupMemberModel>>> getGroupMembers(String groupId) async {
    try {
      Alog.d(tag: 'GroupService', content: 'Get group members: $groupId');
      
      final response = await _apiClient.get<List<GroupMemberModel>>(
        ApiEndpoints.getGroupMembers,
        queryParameters: {'group_id': groupId},
        needAuth: true,
        fromJsonT: (json) {
          if (json is List) {
            return json.map((item) => GroupMemberModel.fromJson(item as Map<String, dynamic>)).toList();
          }
          return <GroupMemberModel>[];
        },
      );
      
      if (response.isSuccess) {
        Alog.d(tag: 'GroupService', content: 'Get group members success: ${response.data?.length ?? 0} members');
      }
      
      return response;
    } catch (e) {
      Alog.e(tag: 'GroupService', content: 'Get group members failed: $e');
      rethrow;
    }
  }
  
  /// 添加群成员
  /// 
  /// [groupId] 群组 ID
  /// [accids] 要添加的成员 accid 列表
  /// 
  /// 返回：操作结果
  Future<ApiResponse<dynamic>> addGroupMember({
    required String groupId,
    required List<String> accids,
  }) async {
    try {
      Alog.d(tag: 'GroupService', content: 'Add group member: $groupId, accids=$accids');
      
      final response = await _apiClient.post<dynamic>(
        ApiEndpoints.addGroupMember,
        data: {
          'group_id': groupId,
          'accids': accids,
        },
        needAuth: true,
      );
      
      if (response.isSuccess) {
        Alog.d(tag: 'GroupService', content: 'Add group member success');
      }
      
      return response;
    } catch (e) {
      Alog.e(tag: 'GroupService', content: 'Add group member failed: $e');
      rethrow;
    }
  }
  
  /// 移除群成员
  /// 
  /// [groupId] 群组 ID
  /// [accids] 要移除的成员 accid 列表
  /// 
  /// 返回：操作结果
  Future<ApiResponse<dynamic>> removeGroupMember({
    required String groupId,
    required List<String> accids,
  }) async {
    try {
      Alog.d(tag: 'GroupService', content: 'Remove group member: $groupId, accids=$accids');
      
      final response = await _apiClient.post<dynamic>(
        ApiEndpoints.removeGroupMember,
        data: {
          'group_id': groupId,
          'accids': accids,
        },
        needAuth: true,
      );
      
      if (response.isSuccess) {
        Alog.d(tag: 'GroupService', content: 'Remove group member success');
      }
      
      return response;
    } catch (e) {
      Alog.e(tag: 'GroupService', content: 'Remove group member failed: $e');
      rethrow;
    }
  }
  
  /// ── 群组同步（被 GroupSyncService 调用）──────────────────────────────────

  /// 同步群组信息到后端本地数据库
  ///
  /// Flutter 端 NIM SDK 已有完整群数据，直接传给后端存库，
  /// 后端无需再调用 NIM 服务端 API，彻底避免 NIM API 权限问题。
  ///
  /// [groupId]         NIM 群组 tid（必填）
  /// [ownerAccid]      群主的 accid（从 NIMTeam.ownerAccountId 取得）
  /// [groupName]       群名称
  /// [memberCount]     当前成员数
  /// [memberLimit]     最大成员数
  /// [callerMemberType] 调用者在该群的角色：0=普通 1=管理员 2=群主
  Future<void> syncGroup(
    String groupId, {
    String? ownerAccid,
    String? groupName,
    int? memberCount,
    int? memberLimit,
    int callerMemberType = 0,
  }) async {
    try {
      Alog.d(tag: 'GroupService', content: 'syncGroup: $groupId role=$callerMemberType');

      final data = <String, dynamic>{
        'tid': groupId,
        'member_type': callerMemberType,
      };
      if (ownerAccid != null && ownerAccid.isNotEmpty) {
        data['owner_accid'] = ownerAccid;
      }
      if (groupName != null && groupName.isNotEmpty) {
        data['group_name'] = groupName;
      }
      if (memberCount != null) data['member_count'] = memberCount;
      if (memberLimit != null) data['member_limit'] = memberLimit;

      await _apiClient.post<dynamic>(
        ApiEndpoints.syncGroup,
        data: data,
        needAuth: true,
      );
      Alog.d(tag: 'GroupService', content: 'syncGroup success: $groupId');
    } catch (e) {
      // best-effort：失败不影响 UI
      Alog.w(tag: 'GroupService', content: 'syncGroup failed (ignored): $e');
    }
  }

  /// 同步群组解散：标记 fa_im_group.status=0 并关闭关联课堂
  ///
  /// [groupId] NIM 群组 tid
  Future<void> syncGroupDismissed(String groupId) async {
    try {
      Alog.d(tag: 'GroupService', content: 'syncGroupDismissed: $groupId');
      await _apiClient.post<dynamic>(
        ApiEndpoints.syncGroup,
        data: {'tid': groupId, 'dismiss': 1},
        needAuth: true,
      );
      Alog.d(tag: 'GroupService', content: 'syncGroupDismissed success: $groupId');
    } catch (e) {
      Alog.w(tag: 'GroupService', content: 'syncGroupDismissed failed (ignored): $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────

  /// 同步管理员角色变更到后端
  ///
  /// 当 Flutter 收到群通知消息（AddManager / RemoveManager）时调用，
  /// 将 [accid] 在 [groupId] 群中的 manager 角色写入后端数据库。
  ///
  /// [groupId]  云信群组 ID
  /// [accid]    被修改角色的成员 accid
  /// [isAdmin]  true=设为管理员 false=取消管理员
  Future<void> setMemberAdmin(
    String groupId,
    String accid, {
    required bool isAdmin,
  }) async {
    try {
      Alog.d(
        tag: 'GroupService',
        content: 'setMemberAdmin: groupId=$groupId accid=$accid isAdmin=$isAdmin',
      );
      await _apiClient.post<dynamic>(
        ApiEndpoints.setGroupAdmin,
        data: {
          'tid': groupId,
          'accid': accid,
          'is_admin': isAdmin ? 1 : 0,
        },
        needAuth: true,
      );
    } catch (e) {
      // 非致命错误，打印即可，不抛出
      Alog.w(tag: 'GroupService', content: 'setMemberAdmin failed (ignored): $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────

  /// 更新群组信息
  /// 
  /// [groupId] 群组 ID
  /// [groupName] 群组名称
  /// [groupAvatar] 群组头像
  /// [intro] 群介绍
  /// [announcement] 群公告
  /// 
  /// 返回：更新后的群组信息
  Future<ApiResponse<GroupModel>> updateGroupInfo({
    required String groupId,
    String? groupName,
    String? groupAvatar,
    String? intro,
    String? announcement,
  }) async {
    try {
      Alog.d(tag: 'GroupService', content: 'Update group info: $groupId');
      
      final data = <String, dynamic>{'group_id': groupId};
      if (groupName != null) data['group_name'] = groupName;
      if (groupAvatar != null) data['group_avatar'] = groupAvatar;
      if (intro != null) data['intro'] = intro;
      if (announcement != null) data['announcement'] = announcement;
      
      final response = await _apiClient.post<GroupModel>(
        ApiEndpoints.updateGroupInfo,
        data: data,
        needAuth: true,
        fromJsonT: (json) => GroupModel.fromJson(json as Map<String, dynamic>),
      );
      
      if (response.isSuccess) {
        Alog.d(tag: 'GroupService', content: 'Update group info success');
      }
      
      return response;
    } catch (e) {
      Alog.e(tag: 'GroupService', content: 'Update group info failed: $e');
      rethrow;
    }
  }
}
