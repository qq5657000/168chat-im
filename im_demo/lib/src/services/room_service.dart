// Copyright (c) 2024 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:yunxin_alog/yunxin_alog.dart';
import '../api/api_client.dart';
import '../api/api_config.dart';
import '../api/api_response.dart';
import '../models/room_model.dart';

/// 房间服务
/// 处理房间创建、加入、离开等（NERoom）
class RoomService {
  static final RoomService _instance = RoomService._internal();
  factory RoomService() => _instance;
  RoomService._internal();

  final ApiClient _apiClient = ApiClient();

  // ─── 核心业务方法 ────────────────────────────────────────────────────────────

  /// 创建群内课堂（由群主/管理员调用）
  ///
  /// [roomName]   房间名称（建议传入创建者昵称）
  /// [roomUuid]   Flutter 端生成的唯一 UUID（格式：时间戳_随机4位，防碰撞）
  /// [groupId]    关联群组的 NIM teamId（必填，权限验证在后端执行）
  /// [roomType]   房间类型，默认 1=听课房间
  /// [maxMembers] 最大成员数，默认 100
  /// [subject]    公告/主题（可选）
  /// [ex]         扩展字段（可选）
  Future<ApiResponse<RoomModel>> createRoom({
    required String roomName,
    required String roomUuid,
    required String groupId,
    int roomType = 1,
    int maxMembers = 100,
    String? subject,
    String? ex,
  }) async {
    try {
      Alog.d(
          tag: 'RoomService',
          content: 'Create room: $roomName uuid=$roomUuid groupId=$groupId');

      final data = <String, dynamic>{
        'room_name': roomName,
        'room_uuid': roomUuid,
        'group_id': groupId,
        'room_type': roomType,
        'max_members': maxMembers,
      };

      if (subject != null) data['subject'] = subject;
      if (ex != null) data['ex'] = ex;

      final response = await _apiClient.post<RoomModel>(
        ApiEndpoints.createRoom,
        data: data,
        needAuth: true,
        fromJsonT: (json) => RoomModel.fromJson(json as Map<String, dynamic>),
      );

      if (response.isSuccess) {
        Alog.d(
            tag: 'RoomService',
            content: 'Create room success: ${response.data?.roomId}');
      }

      return response;
    } catch (e) {
      Alog.e(tag: 'RoomService', content: 'Create room failed: $e');
      rethrow;
    }
  }

  /// 获取指定群组正在进行中的课堂列表（用于群聊横幅）
  ///
  /// [groupId] NIM teamId（字符串形式）
  ///
  /// 后端会自动附加：status=1 + 12小时内创建 + 群状态=有效
  Future<ApiResponse<List<RoomModel>>> getRoomsByGroupId(
      String groupId) async {
    try {
      Alog.d(
          tag: 'RoomService',
          content: 'Get rooms by groupId: $groupId');

      final response = await _apiClient.get<List<RoomModel>>(
        ApiEndpoints.getRoomList,
        queryParameters: {
          'group_id': groupId,
          'status': 1,
          'page': 1,
          'page_size': 10, // 同一个群不太可能超过10个并发课堂
        },
        needAuth: true,
        fromJsonT: (json) {
          if (json is List) {
            return json
                .map((item) =>
                    RoomModel.fromJson(item as Map<String, dynamic>))
                .toList();
          }
          return <RoomModel>[];
        },
      );

      if (response.isSuccess) {
        Alog.d(
            tag: 'RoomService',
            content:
                'Get rooms by group success: ${response.data?.length ?? 0} rooms');
      }

      return response;
    } catch (e) {
      Alog.e(tag: 'RoomService', content: 'Get rooms by group failed: $e');
      rethrow;
    }
  }

  /// 加入房间（学生端）
  ///
  /// 后端会原子性校验人数是否超员。
  /// [roomId] 房间 ID
  Future<ApiResponse<RoomModel>> joinRoom(String roomId) async {
    try {
      Alog.d(tag: 'RoomService', content: 'Join room: $roomId');

      final response = await _apiClient.post<RoomModel>(
        ApiEndpoints.joinRoom,
        data: {'room_id': roomId},
        needAuth: true,
        fromJsonT: (json) => RoomModel.fromJson(json as Map<String, dynamic>),
      );

      if (response.isSuccess) {
        Alog.d(tag: 'RoomService', content: 'Join room success');
      }

      return response;
    } catch (e) {
      Alog.e(tag: 'RoomService', content: 'Join room failed: $e');
      rethrow;
    }
  }

  /// 离开房间（在线人数 -1）
  ///
  /// [roomId] 房间 ID
  Future<ApiResponse<dynamic>> leaveRoom(String roomId) async {
    try {
      Alog.d(tag: 'RoomService', content: 'Leave room: $roomId');

      final response = await _apiClient.post<dynamic>(
        ApiEndpoints.leaveRoom,
        data: {'room_id': roomId},
        needAuth: true,
      );

      if (response.isSuccess) {
        Alog.d(tag: 'RoomService', content: 'Leave room success');
      }

      return response;
    } catch (e) {
      Alog.e(tag: 'RoomService', content: 'Leave room failed: $e');
      rethrow;
    }
  }

  /// 通知后端房间已在 NERoom 侧消失（joinRoom 返回 code=1004）
  ///
  /// 后端收到带正确签名的请求后，会将 fa_im_room.status 更新为 0，
  /// 使该房间从横幅列表中消失，避免群成员继续看到并尝试加入失效课堂。
  ///
  /// 安全性：使用 md5(room_id + '1004') 作为签名（op 参数），
  ///   后端同样计算并比对，防止外部随意关闭房间。
  ///
  /// [roomId] 房间 ID
  Future<ApiResponse<dynamic>> notifyRoomGone(String roomId) async {
    try {
      Alog.d(tag: 'RoomService', content: 'Notify room gone (1004): $roomId');

      // 生成签名：md5(room_id + '1004')
      final bytes = utf8.encode('${roomId}1004');
      final op = md5.convert(bytes).toString();

      final response = await _apiClient.post<dynamic>(
        ApiEndpoints.leaveRoom,
        data: {'room_id': roomId, 'op': op},
        needAuth: true,
      );

      if (response.isSuccess) {
        Alog.d(
            tag: 'RoomService',
            content: 'Notify room gone success: $roomId');
      } else {
        Alog.w(
            tag: 'RoomService',
            content:
                'Notify room gone failed: ${response.code} ${response.msg}');
      }

      return response;
    } catch (e) {
      Alog.e(tag: 'RoomService', content: 'Notify room gone error: $e');
      rethrow;
    }
  }

  /// 关闭/结束房间（仅房主调用）
  ///
  /// 更新后端 status=0，使房间不再出现在进行中列表。
  /// 须在 NERoom SDK 的 endRoom() **之后**调用此接口同步数据库状态。
  ///
  /// [roomId] 房间 ID
  Future<ApiResponse<dynamic>> closeRoom(String roomId) async {
    try {
      Alog.d(tag: 'RoomService', content: 'Close room: $roomId');

      final response = await _apiClient.post<dynamic>(
        ApiEndpoints.closeRoom,
        data: {'room_id': roomId},
        needAuth: true,
      );

      if (response.isSuccess) {
        Alog.d(tag: 'RoomService', content: 'Close room success: $roomId');
      }

      return response;
    } catch (e) {
      Alog.e(tag: 'RoomService', content: 'Close room failed: $e');
      rethrow;
    }
  }

  // ─── 辅助方法 ─────────────────────────────────────────────────────────────

  /// 获取房间列表（通用，支持多种过滤）
  ///
  /// [page]    页码（从 1 开始）
  /// [pageSize] 每页数量
  /// [status]  房间状态：1=进行中 0=已结束
  /// [groupId] 群组 ID（传入后后端附加12h过滤+群状态校验）
  Future<ApiResponse<List<RoomModel>>> getRoomList({
    int page = 1,
    int pageSize = 20,
    int? status,
    String? groupId,
  }) async {
    try {
      Alog.d(
          tag: 'RoomService',
          content: 'Get room list: page=$page groupId=$groupId');

      final queryParams = <String, dynamic>{
        'page': page,
        'page_size': pageSize,
      };

      if (status != null) queryParams['status'] = status;
      if (groupId != null) queryParams['group_id'] = groupId;

      final response = await _apiClient.get<List<RoomModel>>(
        ApiEndpoints.getRoomList,
        queryParameters: queryParams,
        needAuth: true,
        fromJsonT: (json) {
          if (json is List) {
            return json
                .map((item) =>
                    RoomModel.fromJson(item as Map<String, dynamic>))
                .toList();
          }
          return <RoomModel>[];
        },
      );

      if (response.isSuccess) {
        Alog.d(
            tag: 'RoomService',
            content:
                'Get room list success: ${response.data?.length ?? 0} rooms');
      }

      return response;
    } catch (e) {
      Alog.e(tag: 'RoomService', content: 'Get room list failed: $e');
      rethrow;
    }
  }

  /// 获取单个房间信息
  ///
  /// [roomId] 房间 ID
  Future<ApiResponse<RoomModel>> getRoomInfo(String roomId) async {
    try {
      Alog.d(tag: 'RoomService', content: 'Get room info: $roomId');

      final response = await _apiClient.get<RoomModel>(
        ApiEndpoints.getRoomInfo,
        queryParameters: {'room_id': roomId},
        needAuth: true,
        fromJsonT: (json) =>
            RoomModel.fromJson(json as Map<String, dynamic>),
      );

      if (response.isSuccess) {
        Alog.d(tag: 'RoomService', content: 'Get room info success');
      }

      return response;
    } catch (e) {
      Alog.e(tag: 'RoomService', content: 'Get room info failed: $e');
      rethrow;
    }
  }
}
