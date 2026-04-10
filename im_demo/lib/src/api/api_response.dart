// Copyright (c) 2024 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

/// API 统一响应模型
/// 对应服务端返回格式：{ code, msg, data }
class ApiResponse<T> {
  final int code;
  final String msg;
  final T? data;
  
  ApiResponse({
    required this.code,
    required this.msg,
    this.data,
  });
  
  /// 是否成功（code == 1 表示成功）
  bool get isSuccess => code == 1;
  
  /// 是否失败
  bool get isFailure => !isSuccess;
  
  /// 从 JSON 创建响应对象
  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic)? fromJsonT,
  ) {
    return ApiResponse<T>(
      code: json['code'] as int? ?? 0,
      msg: json['msg'] as String? ?? '',
      data: json['data'] != null && fromJsonT != null
          ? fromJsonT(json['data'])
          : json['data'] as T?,
    );
  }
  
  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'msg': msg,
      'data': data,
    };
  }
  
  /// 成功响应
  factory ApiResponse.success({T? data, String? msg}) {
    return ApiResponse<T>(
      code: 1,
      msg: msg ?? 'success',
      data: data,
    );
  }
  
  /// 失败响应
  factory ApiResponse.failure({required String msg, int? code}) {
    return ApiResponse<T>(
      code: code ?? 0,
      msg: msg,
      data: null,
    );
  }
  
  @override
  String toString() {
    return 'ApiResponse{code: $code, msg: $msg, data: $data}';
  }
}

/// API 异常类
class ApiException implements Exception {
  final int code;
  final String message;
  final dynamic data;
  
  ApiException({
    required this.code,
    required this.message,
    this.data,
  });
  
  @override
  String toString() {
    return 'ApiException{code: $code, message: $message, data: $data}';
  }
}
