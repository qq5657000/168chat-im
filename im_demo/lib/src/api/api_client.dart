// Copyright (c) 2024 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunxin_alog/yunxin_alog.dart';
import 'api_config.dart';
import 'api_response.dart';

/// 通用 HTTP 请求客户端
/// 封装所有 API 请求，统一处理 Header、Token、异常等
class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();
  
  // HTTP 客户端
  final http.Client _client = http.Client();
  
  // Token 缓存
  String? _cachedToken;
  
  /// 获取存储的 Token
  Future<String?> getToken() async {
    if (_cachedToken != null) {
      return _cachedToken;
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedToken = prefs.getString(ApiConfig.tokenKey);
      return _cachedToken;
    } catch (e) {
      Alog.e(tag: 'ApiClient', content: 'Get token failed: $e');
      return null;
    }
  }
  
  /// 保存 Token
  Future<void> saveToken(String token) async {
    try {
      _cachedToken = token;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(ApiConfig.tokenKey, token);
      Alog.d(tag: 'ApiClient', content: 'Token saved successfully');
    } catch (e) {
      Alog.e(tag: 'ApiClient', content: 'Save token failed: $e');
    }
  }
  
  /// 清除 Token
  Future<void> clearToken() async {
    try {
      _cachedToken = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(ApiConfig.tokenKey);
      await prefs.remove(ApiConfig.accidKey);
      await prefs.remove(ApiConfig.userInfoKey);
      Alog.d(tag: 'ApiClient', content: 'Token cleared successfully');
    } catch (e) {
      Alog.e(tag: 'ApiClient', content: 'Clear token failed: $e');
    }
  }
  
  /// 构建请求头
  Future<Map<String, String>> _buildHeaders({
    bool needAuth = true,
    Map<String, String>? extraHeaders,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json; charset=UTF-8',
      'Accept': 'application/json',
    };
    
    // 添加 Token
    if (needAuth) {
      final token = await getToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
        headers['token'] = token;
      }
    }
    
    // 添加额外的 Header
    if (extraHeaders != null) {
      headers.addAll(extraHeaders);
    }
    
    return headers;
  }
  
  /// GET 请求
  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool needAuth = true,
    T Function(dynamic)? fromJsonT,
  }) async {
    try {
      // 构建完整 URL
      var url = '${ApiConfig.apiBaseUrl}$path';
      if (queryParameters != null && queryParameters.isNotEmpty) {
        final queryString = queryParameters.entries
            .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value.toString())}')
            .join('&');
        url = '$url?$queryString';
      }
      
      final uri = Uri.parse(url);
      final headers = await _buildHeaders(needAuth: needAuth);
      
      Alog.d(tag: 'ApiClient', content: 'GET $url');
      Alog.d(tag: 'ApiClient', content: 'Headers: $headers');
      
      // 发送请求
      final response = await _client
          .get(uri, headers: headers)
          .timeout(Duration(seconds: ApiConfig.receiveTimeout));
      
      return _handleResponse<T>(response, fromJsonT);
    } on SocketException catch (e) {
      Alog.e(tag: 'ApiClient', content: 'Network error: $e');
      throw ApiException(code: -1, message: '网络连接失败，请检查网络设置');
    } on TimeoutException catch (e) {
      Alog.e(tag: 'ApiClient', content: 'Timeout error: $e');
      throw ApiException(code: -2, message: '请求超时，请稍后重试');
    } catch (e) {
      Alog.e(tag: 'ApiClient', content: 'Request error: $e');
      throw ApiException(code: -999, message: '请求失败: ${e.toString()}');
    }
  }
  
  /// POST 请求
  Future<ApiResponse<T>> post<T>(
    String path, {
    Map<String, dynamic>? data,
    bool needAuth = true,
    T Function(dynamic)? fromJsonT,
  }) async {
    try {
      final url = '${ApiConfig.apiBaseUrl}$path';
      final uri = Uri.parse(url);
      final headers = await _buildHeaders(needAuth: needAuth);
      final body = data != null ? jsonEncode(data) : null;
      
      // 详细日志输出
      print('');
      print('========== API POST 请求开始 ==========');
      print('URL: $url');
      print('Headers: $headers');
      print('Body: $body');
      print('=====================================');
      
      Alog.d(tag: 'ApiClient', content: '========== POST 请求 ==========');
      Alog.d(tag: 'ApiClient', content: 'URL: $url');
      Alog.d(tag: 'ApiClient', content: 'Headers: $headers');
      Alog.d(tag: 'ApiClient', content: 'Body: $body');
      
      // 发送请求
      final response = await _client
          .post(uri, headers: headers, body: body)
          .timeout(Duration(seconds: ApiConfig.sendTimeout));
      
      print('Response Status: ${response.statusCode}');
      print('Response Body: ${response.body}');
      print('========== API POST 请求结束 ==========');
      print('');
      
      return _handleResponse<T>(response, fromJsonT);
    } on SocketException catch (e) {
      print('❌ 网络错误: $e');
      Alog.e(tag: 'ApiClient', content: 'Network error: $e');
      throw ApiException(code: -1, message: '网络连接失败，请检查网络设置');
    } on TimeoutException catch (e) {
      print('❌ 超时错误: $e');
      Alog.e(tag: 'ApiClient', content: 'Timeout error: $e');
      throw ApiException(code: -2, message: '请求超时，请稍后重试');
    } catch (e) {
      print('❌ 请求错误: $e');
      print('错误类型: ${e.runtimeType}');
      Alog.e(tag: 'ApiClient', content: 'Request error: $e');
      throw ApiException(code: -999, message: '请求失败: ${e.toString()}');
    }
  }
  
  /// PUT 请求
  Future<ApiResponse<T>> put<T>(
    String path, {
    Map<String, dynamic>? data,
    bool needAuth = true,
    T Function(dynamic)? fromJsonT,
  }) async {
    try {
      final url = '${ApiConfig.apiBaseUrl}$path';
      final uri = Uri.parse(url);
      final headers = await _buildHeaders(needAuth: needAuth);
      final body = data != null ? jsonEncode(data) : null;
      
      Alog.d(tag: 'ApiClient', content: 'PUT $url');
      Alog.d(tag: 'ApiClient', content: 'Headers: $headers');
      Alog.d(tag: 'ApiClient', content: 'Body: $body');
      
      // 发送请求
      final response = await _client
          .put(uri, headers: headers, body: body)
          .timeout(Duration(seconds: ApiConfig.sendTimeout));
      
      return _handleResponse<T>(response, fromJsonT);
    } on SocketException catch (e) {
      Alog.e(tag: 'ApiClient', content: 'Network error: $e');
      throw ApiException(code: -1, message: '网络连接失败，请检查网络设置');
    } on TimeoutException catch (e) {
      Alog.e(tag: 'ApiClient', content: 'Timeout error: $e');
      throw ApiException(code: -2, message: '请求超时，请稍后重试');
    } catch (e) {
      Alog.e(tag: 'ApiClient', content: 'Request error: $e');
      throw ApiException(code: -999, message: '请求失败: ${e.toString()}');
    }
  }
  
  /// DELETE 请求
  Future<ApiResponse<T>> delete<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool needAuth = true,
    T Function(dynamic)? fromJsonT,
  }) async {
    try {
      var url = '${ApiConfig.apiBaseUrl}$path';
      if (queryParameters != null && queryParameters.isNotEmpty) {
        final queryString = queryParameters.entries
            .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value.toString())}')
            .join('&');
        url = '$url?$queryString';
      }
      
      final uri = Uri.parse(url);
      final headers = await _buildHeaders(needAuth: needAuth);
      
      Alog.d(tag: 'ApiClient', content: 'DELETE $url');
      Alog.d(tag: 'ApiClient', content: 'Headers: $headers');
      
      // 发送请求
      final response = await _client
          .delete(uri, headers: headers)
          .timeout(Duration(seconds: ApiConfig.receiveTimeout));
      
      return _handleResponse<T>(response, fromJsonT);
    } on SocketException catch (e) {
      Alog.e(tag: 'ApiClient', content: 'Network error: $e');
      throw ApiException(code: -1, message: '网络连接失败，请检查网络设置');
    } on TimeoutException catch (e) {
      Alog.e(tag: 'ApiClient', content: 'Timeout error: $e');
      throw ApiException(code: -2, message: '请求超时，请稍后重试');
    } catch (e) {
      Alog.e(tag: 'ApiClient', content: 'Request error: $e');
      throw ApiException(code: -999, message: '请求失败: ${e.toString()}');
    }
  }
  
  /// 处理响应
  ApiResponse<T> _handleResponse<T>(
    http.Response response,
    T Function(dynamic)? fromJsonT,
  ) {
    print('');
    print('========== 处理响应 ==========');
    print('Status Code: ${response.statusCode}');
    print('Response Body: ${response.body}');
    
    Alog.d(tag: 'ApiClient', content: 'Response status: ${response.statusCode}');
    Alog.d(tag: 'ApiClient', content: 'Response body: ${response.body}');
    
    // 检查 HTTP 状态码
    if (response.statusCode < 200 || response.statusCode >= 300) {
      print('❌ HTTP 错误: ${response.statusCode}');
      throw ApiException(
        code: response.statusCode,
        message: 'HTTP 错误: ${response.statusCode}',
      );
    }
    
    // 解析 JSON
    try {
      final jsonData = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      print('解析后的 JSON: $jsonData');
      
      final apiResponse = ApiResponse<T>.fromJson(jsonData, fromJsonT);
      
      print('API Response Code: ${apiResponse.code}');
      print('API Response Msg: ${apiResponse.msg}');
      print('API Response Data: ${apiResponse.data}');
      print('========== 响应处理完成 ==========');
      print('');
      
      // 检查业务状态码
      if (apiResponse.isFailure) {
        Alog.w(tag: 'ApiClient', content: 'API error: ${apiResponse.msg}');
      } else {
        Alog.d(tag: 'ApiClient', content: 'API success: ${apiResponse.msg}');
      }
      
      return apiResponse;
    } catch (e) {
      print('❌ 解析响应失败: $e');
      print('错误类型: ${e.runtimeType}');
      Alog.e(tag: 'ApiClient', content: 'Parse response failed: $e');
      throw ApiException(
        code: -998,
        message: '数据解析失败: ${e.toString()}',
      );
    }
  }
  
  /// 关闭客户端
  void close() {
    _client.close();
  }
}
