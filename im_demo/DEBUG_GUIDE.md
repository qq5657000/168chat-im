# 调试指南 - 登录注册功能

## 🔍 日志输出说明

现在登录和注册功能已经增强了详细的日志输出，你可以在 Debug 控制台看到完整的请求和响应过程。

### 登录流程日志示例

```
🚀 ========== 登录页面：开始登录流程 ==========
手机号: 13800138000
步骤 1: 调用服务端登录接口

🔐 ========== 开始登录 ==========
手机号: 13800138000
密码: ******

========== API POST 请求开始 ==========
URL: http://192.168.1.5:8168/api/yunxinauth/login
Headers: {Content-Type: application/json; charset=UTF-8, Accept: application/json}
Body: {"mobile":"13800138000","password":"123456"}
=====================================

Response Status: 200
Response Body: {"code":1,"msg":"登录成功","data":{"user":{"id":1,"accid":"abc123","token":"xyz789"...}}}
========== API POST 请求结束 ==========

========== 处理响应 ==========
Status Code: 200
Response Body: {"code":1,"msg":"登录成功","data":{...}}
解析后的 JSON: {code: 1, msg: 登录成功, data: {...}}
API Response Code: 1
API Response Msg: 登录成功
API Response Data: Instance of 'LoginResponse'
========== 响应处理完成 ==========

✅ 登录成功！
AccID: abc123
Token: xyz789...
========== 登录完成 ==========

步骤 1 完成: 服务端响应 code=1, msg=登录成功
✅ 步骤 1 成功: 服务端登录成功
AccID: abc123
Token: xyz789...
步骤 2: 使用 accid + token 登录云信 SDK
步骤 2 完成: 云信 SDK 响应 isSuccess=true
✅ 步骤 2 成功: 云信 SDK 登录成功
步骤 3: 初始化 CallKit
✅ 步骤 3 成功: CallKit 初始化完成
步骤 4: 跳转到主页
========== 登录流程全部完成 ==========
```

### 注册流程日志示例

```
🚀 ========== 注册页面：开始注册流程 ==========
手机号: 13800138001
昵称: 测试用户
步骤 1: 调用服务端注册接口

📝 ========== 开始注册 ==========
手机号: 13800138001
密码: ******
昵称: 测试用户
请求数据: {mobile: 13800138001, password: 123456, nickname: 测试用户}

========== API POST 请求开始 ==========
URL: http://192.168.1.5:8168/api/yunxinauth/register
Headers: {Content-Type: application/json; charset=UTF-8, Accept: application/json}
Body: {"mobile":"13800138001","password":"123456","nickname":"测试用户"}
=====================================

Response Status: 200
Response Body: {"code":1,"msg":"注册成功","data":{...}}
========== API POST 请求结束 ==========

✅ 注册成功！
AccID: def456
Token: uvw012...
========== 注册完成 ==========

步骤 1 完成: 服务端响应 code=1, msg=注册成功
✅ 步骤 1 成功: 服务端注册成功
...
========== 注册流程全部完成 ==========
```

---

## 🐛 常见错误及解决方案

### 1. 网络连接失败

**日志输出：**
```
❌ 网络错误: SocketException: ...
❌ 步骤 1 失败: 服务端登录失败
错误信息: 网络连接失败，请检查网络设置
```

**原因：**
- 服务端未启动
- IP 地址配置错误
- 防火墙阻止连接

**解决方案：**
1. 确认服务端正在运行：
   ```bash
   # 在服务端执行
   php think run -p 8168
   ```

2. 检查 API 地址配置：
   - 打开 `lib/src/api/api_config.dart`
   - 确认 `devBaseUrl = 'http://192.168.1.5:8168'`

3. Android 模拟器特殊处理：
   - 如果使用 Android 模拟器，将 `192.168.1.5` 改为 `10.0.2.2`
   - 或者使用真机测试

4. 检查防火墙：
   ```bash
   # Windows 防火墙允许 8168 端口
   netsh advfirewall firewall add rule name="PHP Server" dir=in action=allow protocol=TCP localport=8168
   ```

### 2. 请求超时

**日志输出：**
```
❌ 超时错误: TimeoutException
```

**解决方案：**
- 增加超时时间（编辑 `api_config.dart`）
- 检查网络速度
- 检查服务端响应速度

### 3. HTTP 错误 404

**日志输出：**
```
Response Status: 404
❌ HTTP 错误: 404
```

**原因：**
- API 路由不存在
- 服务端路由配置错误

**解决方案：**
1. 检查服务端路由是否正确配置
2. 确认 API 端点路径正确：
   - 登录：`POST /api/yunxinauth/login`
   - 注册：`POST /api/yunxinauth/register`

### 4. 服务端返回错误

**日志输出：**
```
Response Status: 200
Response Body: {"code":0,"msg":"手机号已存在","data":null}
❌ 步骤 1 失败: 服务端注册失败
错误信息: 手机号已存在
```

**原因：**
- 业务逻辑错误（如手机号已注册）
- 参数验证失败

**解决方案：**
- 根据错误信息调整输入
- 检查服务端日志获取详细错误

### 5. 云信 SDK 登录失败

**日志输出：**
```
✅ 步骤 1 成功: 服务端登录成功
AccID: abc123
Token: xyz789...
步骤 2: 使用 accid + token 登录云信 SDK
❌ 步骤 2 失败: 云信 SDK 登录失败
错误码: 302
```

**原因：**
- Token 无效
- AppKey 不匹配
- 云信服务异常

**解决方案：**
1. 确认 AppKey 一致：
   - Flutter: `lib/src/config.dart` 中的 `AppKey`
   - 服务端: `application/extra/yunxin.php` 中的 `app_key`

2. 检查服务端云信 API 调用是否成功

3. 查看云信错误码文档：
   - https://doc.yunxin.163.com/

---

## 📱 测试步骤

### 步骤 1：启动服务端

```bash
cd E:\code\waibao\168chat\fastadmin
php think run -p 8168
```

确认看到：
```
ThinkPHP Development server is started On <http://0.0.0.0:8168/>
```

### 步骤 2：启动 Flutter 应用

```bash
cd E:\code\waibao\168chat\nim-uikit-flutter\im_demo
flutter run
```

### 步骤 3：测试注册

1. 点击"立即注册"
2. 输入手机号：`13800138000`
3. 输入昵称：`测试用户`
4. 输入密码：`123456`
5. 确认密码：`123456`
6. 点击"注册"按钮

**观察 Debug 控制台：**
- 应该看到完整的请求日志
- 应该看到服务端响应
- 应该看到云信 SDK 登录日志
- 最后跳转到主页

### 步骤 4：测试登录

1. 重启应用（或退出登录）
2. 输入手机号：`13800138000`
3. 输入密码：`123456`
4. 点击"登录"按钮

**观察 Debug 控制台：**
- 应该看到完整的登录流程日志
- 最后跳转到主页

---

## 🔧 调试技巧

### 1. 查看完整日志

在 VS Code 或 Android Studio 的 Debug Console 中查看完整输出。

### 2. 使用 Postman 测试服务端

**测试登录接口：**
```
POST http://192.168.1.5:8168/api/yunxinauth/login
Content-Type: application/json

{
  "mobile": "13800138000",
  "password": "123456"
}
```

**预期响应：**
```json
{
  "code": 1,
  "msg": "登录成功",
  "data": {
    "user": {
      "id": 1,
      "accid": "...",
      "token": "...",
      "mobile": "13800138000",
      ...
    },
    "token": "..."
  }
}
```

### 3. 检查服务端日志

查看 FastAdmin 日志：
```
E:\code\waibao\168chat\fastadmin\runtime\log\
```

### 4. 抓包工具

使用 Charles 或 Fiddler 抓包查看实际的 HTTP 请求和响应。

---

## ✅ 验证清单

测试前请确认：

- [ ] 服务端正在运行（`php think run -p 8168`）
- [ ] 数据库已导入（`yunxin_im.sql`）
- [ ] 云信配置已填写（`application/extra/yunxin.php`）
- [ ] Flutter 依赖已安装（`flutter pub get`）
- [ ] API 地址配置正确（`lib/src/api/api_config.dart`）
- [ ] AppKey 配置一致（Flutter 和服务端）

测试时请观察：

- [ ] Debug 控制台有详细的日志输出
- [ ] 能看到 HTTP 请求的 URL、Headers、Body
- [ ] 能看到 HTTP 响应的 Status Code、Body
- [ ] 能看到服务端返回的 code、msg、data
- [ ] 能看到云信 SDK 登录结果
- [ ] 登录/注册成功后能跳转到主页

---

## 📞 获取帮助

如果遇到问题：

1. **查看 Debug 控制台日志**
   - 找到具体的错误信息
   - 确认请求是否真正发出

2. **查看服务端日志**
   - 确认服务端是否收到请求
   - 确认服务端是否正确处理

3. **使用 Postman 测试**
   - 排除是否是服务端问题

4. **检查网络配置**
   - 确认 IP 地址正确
   - 确认端口未被占用
   - 确认防火墙未阻止

---

## 🎉 成功标志

当你看到以下日志时，说明一切正常：

```
✅ 步骤 1 成功: 服务端登录成功
✅ 步骤 2 成功: 云信 SDK 登录成功
✅ 步骤 3 成功: CallKit 初始化完成
========== 登录流程全部完成 ==========
```

然后应用会自动跳转到主页！🎊
