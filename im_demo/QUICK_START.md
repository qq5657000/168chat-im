# Flutter 端快速开始指南

## 🚀 快速部署（5 分钟）

### 1. 安装依赖

```bash
cd E:\code\waibao\168chat\nim-uikit-flutter\im_demo
flutter pub get
```

### 2. 运行应用

```bash
# Android
flutter run

# iOS
flutter run -d ios
```

### 3. 测试功能

1. **注册账号**
   - 打开应用，点击"立即注册"
   - 输入手机号、密码、昵称
   - 点击"注册"按钮
   - 注册成功后自动登录并跳转到主页

2. **登录账号**
   - 输入已注册的手机号和密码
   - 点击"登录"按钮
   - 登录成功后跳转到主页

3. **创建群组**
   - 在主页导航到群组页面
   - 点击右上角"+"按钮
   - 输入群组名称和简介
   - 点击"创建群组"

4. **创建房间**
   - 在主页导航到房间页面
   - 点击右上角"+"按钮
   - 输入房间名称和主题
   - 选择房间类型和最大人数
   - 点击"创建房间"

---

## 📁 新增文件位置

所有新增文件都在 `lib/src/` 目录下：

```
lib/src/
├── api/                    # API 基础设施
│   ├── api_config.dart     # API 配置
│   ├── api_response.dart   # 响应模型
│   └── api_client.dart     # HTTP 客户端
├── models/                 # 数据模型
│   ├── user_model.dart
│   ├── group_model.dart
│   └── room_model.dart
├── services/               # 服务层
│   ├── auth_service.dart
│   ├── group_service.dart
│   └── room_service.dart
├── auth/                   # 认证页面
│   ├── login_page_new.dart
│   └── register_page.dart
├── group/                  # 群组页面
│   ├── group_list_page.dart
│   ├── create_group_page.dart
│   └── group_detail_page.dart
└── room/                   # 房间页面
    ├── room_list_page.dart
    └── create_room_page.dart
```

---

## ⚙️ 环境配置

### 切换开发/生产环境

编辑 `lib/src/api/api_config.dart`：

```dart
// 开发环境（默认）
static bool isProduction = false;

// 切换到生产环境
static bool isProduction = true;
```

或在代码中动态切换：

```dart
import 'package:im_demo/src/api/api_config.dart';

// 切换到生产环境
ApiConfig.switchToProduction();

// 切换到开发环境
ApiConfig.switchToDevelopment();
```

### API 地址配置

编辑 `lib/src/api/api_config.dart`：

```dart
// 开发环境 API 地址
static const String devBaseUrl = 'http://192.168.1.5:8168';

// 生产环境 API 地址
static const String prodBaseUrl = 'https://q168api.witherelax.com';
```

---

## 🔗 在主页集成群组和房间入口

### 方法 1：添加浮动按钮

编辑 `lib/src/home/home_page.dart`：

```dart
import 'package:im_demo/src/group/group_list_page.dart';
import 'package:im_demo/src/room/room_list_page.dart';

// 在 Scaffold 中添加
floatingActionButton: Column(
  mainAxisAlignment: MainAxisAlignment.end,
  children: [
    FloatingActionButton(
      heroTag: 'group',
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const GroupListPage()),
        );
      },
      child: const Icon(Icons.group),
    ),
    const SizedBox(height: 16),
    FloatingActionButton(
      heroTag: 'room',
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const RoomListPage()),
        );
      },
      child: const Icon(Icons.video_call),
    ),
  ],
)
```

### 方法 2：添加到底部导航栏

编辑 `lib/src/home/home_page.dart`：

```dart
// 在 BottomNavigationBar 中添加
BottomNavigationBar(
  currentIndex: _currentIndex,
  onTap: (index) {
    setState(() {
      _currentIndex = index;
    });
    if (index == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const GroupListPage()),
      );
    } else if (index == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const RoomListPage()),
      );
    }
  },
  items: const [
    BottomNavigationBarItem(icon: Icon(Icons.chat), label: '消息'),
    BottomNavigationBarItem(icon: Icon(Icons.group), label: '群组'),
    BottomNavigationBarItem(icon: Icon(Icons.video_call), label: '房间'),
    BottomNavigationBarItem(icon: Icon(Icons.person), label: '我的'),
  ],
)
```

---

## 🐛 常见问题

### 1. 编译错误

**问题：** `flutter pub get` 失败

**解决：**
```bash
flutter clean
flutter pub get
```

### 2. 网络请求失败

**问题：** 提示"网络连接失败"

**解决：**
- 确保服务端正在运行
- 检查 `api_config.dart` 中的 API 地址
- Android 模拟器使用 `10.0.2.2` 代替 `localhost`
- iOS 模拟器可以直接使用 `localhost`

### 3. 登录失败

**问题：** 服务端登录成功，但云信 SDK 登录失败

**解决：**
- 检查服务端返回的 `accid` 和 `token` 是否正确
- 确认 `config.dart` 中的 `AppKey` 与服务端一致
- 查看控制台日志获取详细错误信息

---

## 📝 API 测试

### 使用 Postman 测试服务端 API

#### 1. 注册

```
POST http://192.168.1.5:8168/api/yunxinauth/register
Content-Type: application/json

{
  "mobile": "13800138000",
  "password": "123456",
  "nickname": "测试用户"
}
```

#### 2. 登录

```
POST http://192.168.1.5:8168/api/yunxinauth/login
Content-Type: application/json

{
  "mobile": "13800138000",
  "password": "123456"
}
```

#### 3. 创建群组

```
POST http://192.168.1.5:8168/api/yxgroup/create
Content-Type: application/json
Authorization: Bearer YOUR_TOKEN

{
  "group_name": "测试群组",
  "intro": "这是一个测试群组"
}
```

---

## ✅ 验证清单

- [ ] `flutter pub get` 成功
- [ ] 应用能正常启动
- [ ] 注册功能正常
- [ ] 登录功能正常
- [ ] 登录后能连接云信 SDK
- [ ] 能创建群组
- [ ] 能查看群组列表
- [ ] 能创建房间
- [ ] 能查看房间列表

---

## 📚 更多文档

- 完整集成指南：`FLUTTER_INTEGRATION_GUIDE.md`
- 服务端部署指南：`../fastadmin/database/yunxin_deploy_guide.md`

---

## 🎉 完成！

现在你的 Flutter 应用已经成功对接服务端 API，所有鉴权流程都通过服务端进行！
