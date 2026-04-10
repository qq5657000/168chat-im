// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:im_demo/l10n/S.dart';
import 'package:im_demo/src/mine/mine_page.dart';
import 'package:im_demo/src/room/create_room_page.dart';
import 'package:im_demo/src/room/group_room_banner.dart';
import 'package:im_demo/src/services/group_sync_service.dart';
import 'package:netease_common_ui/utils/color_utils.dart';
import 'package:nim_chatkit/chatkit_utils.dart';
import 'package:nim_chatkit/repo/contact_repo.dart';
import 'package:nim_chatkit/repo/conversation_repo.dart';
import 'package:nim_chatkit/repo/team_repo.dart';
import 'package:nim_chatkit/router/imkit_router_factory.dart';
import 'package:nim_chatkit/services/message/nim_chat_cache.dart';
import 'package:nim_chatkit/service_locator.dart';
import 'package:nim_chatkit/services/login/im_login_service.dart';
import 'package:nim_chatkit_ui/chat_kit_client.dart';
import 'package:nim_chatkit_ui/view/chat_kit_message_list/item/chat_kit_message_item.dart';
import 'package:nim_chatkit_ui/view/input/actions.dart';
import 'package:nim_contactkit_ui/page/contact_page.dart';
import 'package:nim_conversationkit_ui/conversation_kit_client.dart';
import 'package:nim_conversationkit_ui/page/conversation_page.dart';
import 'package:nim_core_v2/nim_core.dart';
import 'package:yunxin_alog/yunxin_alog.dart';

const channelName = "com.hestia.n168chat.app.flutter.im/channel";
const pushMethodName = "pushMessage";

class HomePage extends StatefulWidget {
  final int pageIndex;

  const HomePage({Key? key, this.pageIndex = 0}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int currentIndex = 0;

  int chatUnreadCount = 0;
  int contactUnreadCount = 0;
  int teamActionsUnreadCount = 0;

  initUnread() {
    ConversationRepo.getMsgUnreadCount().then((value) {
      if (value.isSuccess && value.data != null) {
        if (mounted) {
          setState(() {
            chatUnreadCount = value.data!;
          });
        }
      }
    });
    ContactRepo.addApplicationUnreadCountNotifier.listen((count) {
      if (mounted) {
        setState(() {
          contactUnreadCount = count;
        });
      }
    });
    TeamRepo.teamActionsUnreadCountNotifier.listen((count) {
      if (mounted) {
        setState(() {
          teamActionsUnreadCount = count;
        });
      }
    });
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == pushMethodName && call.arguments is Map) {
      _dispatchMessage(call.arguments);
    }
  }

  void _handleMessageFromNative() {
    const channel = MethodChannel(channelName);
    channel.setMethodCallHandler((call) => _handleMethodCall(call));
    channel.invokeMapMethod<String, dynamic>(pushMethodName).then((value) {
      Alog.d(tag: 'HomePage', content: "Message from Native is = $value}");
      _dispatchMessage(value);
    });
  }

  void _dispatchMessage(Map? params) {
    var sessionType = params?['sessionType'] as String?;
    var sessionId = params?['sessionId'] as String?;
    if (sessionType?.isNotEmpty == true && sessionId?.isNotEmpty == true) {
      if (sessionType == 'p2p') {
        goToP2pChat(context, sessionId!);
      } else if (sessionType == 'team') {
        goToTeamChat(context, sessionId!);
      }
    }
  }

  // ─── 初始化配置 ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    currentIndex = widget.pageIndex;
    initUnread();
    ChatKitClient.instance.registerRevokedMessage();
    ChatKitClient.instance.chatUIConfig.getPushPayload = _getPushPayload;
    _handleMessageFromNative();

    // 隐藏私聊/群聊页面顶部的防诈骗提示 Tips
    ChatKitClient.instance.showWarningTyps = false;

    // ── 自定义消息渲染 ─────────────────────────────────────────────────────
    var messageBuilder = ChatKitMessageBuilder();
    messageBuilder.extendBuilder = {
      NIMMessageType.custom: (NIMMessage msg) {
        return Container(
          child: Text(
            msg.text ?? 'default text',
            style: TextStyle(fontSize: 20, color: Colors.red),
          ),
        );
      }
    };
    ChatKitClient.instance.chatUIConfig.messageBuilder = messageBuilder;

    // ── moreActions：自定义按钮 + 创建课堂（仅群聊可见）─────────────────────
    ChatKitClient.instance.chatUIConfig.moreActions = [
      // 示例：原有自定义消息按钮（所有会话类型均可见）
      ActionItem(
        type: 'custom',
        icon: const Icon(Icons.android_outlined),
        title: '自定义',
        onTap: (BuildContext ctx, String conversationId,
            NIMConversationType sessionType,
            {NIMMessageSender? messageSender}) async {
          var msg =
              await MessageCreator.createCustomMessage('自定义消息', '');
          if (msg.isSuccess && msg.data != null) {
            Fluttertoast.showToast(msg: '发送自定义消息！');
            messageSender?.call(msg.data!);
          }
        },
      ),

      // ── 创建课堂（conversationTypes 限定：仅群聊）────────────────────────
      ActionItem(
        type: 'create_classroom',
        icon: const Icon(Icons.cast_for_education,
            color: Color(0xFF337EFF), size: 28),
        title: '创建课堂',
        conversationTypes: [NIMConversationType.team], // 单聊不显示此按钮
        onTap: (BuildContext ctx, String conversationId,
            NIMConversationType sessionType,
            {NIMMessageSender? messageSender}) async {
          // 此 onTap 仅在群聊时触发（MorePanel 已根据 conversationTypes 过滤）
          final teamId =
              ChatKitUtils.getConversationTargetId(conversationId);

          // ── 异步校验群主/管理员身份（使用缓存，快速无网络请求）──────────────
          // NIMChatCache.getMyTeamMember 先读本地缓存，命中则同步返回，否则异步拉取
          final teamMember =
              await NIMChatCache.instance.getMyTeamMember(teamId);

          if (teamMember == null) {
            Fluttertoast.showToast(msg: '获取群身份失败，请重试');
            return;
          }

          final role = teamMember.teamInfo.memberRole;
          final isAdminOrOwner =
              role == NIMTeamMemberRole.memberRoleOwner ||
                  role == NIMTeamMemberRole.memberRoleManager;

          if (!isAdminOrOwner) {
            Fluttertoast.showToast(msg: '仅群主和管理员可创建课堂');
            return;
          }

          // ── 跳转创建课堂页面（自动创建，无表单）────────────────────────
          if (!ctx.mounted) return;
          Navigator.push(
            ctx,
            MaterialPageRoute(
              builder: (_) => CreateRoomPage(groupId: teamId),
            ),
          );
        },
      ),
    ];

    ChatKitClient.instance.chatUIConfig.keepDefaultMoreAction = true;

    // ── 启动群组同步服务（监听 NIM SDK 群事件 → 同步到后端数据库）──────────
    // 解决：群通过 SDK 直接创建/操作时，fa_im_group/fa_im_group_member 表为空导致权限校验失败
    GroupSyncService().init();

    // ── 群聊置顶课堂横幅（仅群聊 & 有进行中课堂时显示）──────────────────────
    ChatKitClient.instance.chatUIConfig.topWidgetBuilder =
        (String conversationId, NIMConversationType conversationType) {
      if (conversationType != NIMConversationType.team) return null;
      final teamId = ChatKitUtils.getConversationTargetId(conversationId);
      return GroupRoomBanner(groupId: teamId);
    };

    // ── 会话列表自定义消息展示 + 标题栏配置 ────────────────────────────────────
    ConversationKitClient.instance.conversationUIConfig = ConversationUIConfig(
        titleBarConfig: ConversationTitleBarConfig(
          showTitleBarLeftIcon: false, // 隐藏左侧 logo 图标
          titleBarTitle: '168聊', // 自定义标题
        ),
        itemConfig: ConversationItemConfig(
            lastMessageContentBuilder: (context, conversationInfo) {
      if (conversationInfo.conversation.lastMessage?.messageType ==
              NIMMessageType.custom &&
          conversationInfo.conversation.lastMessage?.attachment == null) {
        return S.of(context).customMessage;
      }
      return null;
    }));
  }

  @override
  void dispose() {
    super.dispose();
    ChatKitClient.instance.unregisterRevokedMessage();
  }

  Future<Map<String, dynamic>> _getPushPayload(
      NIMMessage message, String conversationId) async {
    Map<String, dynamic> pushPayload = {};
    String? sessionId;
    String? sessionType;
    if ((await NimCore.instance.conversationIdUtil
                .conversationType(conversationId))
            .data ==
        NIMConversationType.p2p) {
      sessionId = getIt<IMLoginService>().userInfo?.accountId;
      sessionType = 'p2p';
    } else {
      sessionId = ChatKitUtils.getConversationTargetId(conversationId);
      sessionType = 'team';
    }

    var oppoParam = {'sessionId': sessionId, 'sessionType': sessionType};
    var oppoField = {
      'click_action_type': 4,
      'click_action_activity':
          'com.hestia.n168chat.app.flutter.im.MainActivity',
      'action_parameters': oppoParam
    };
    pushPayload['oppoField'] = oppoField;

    pushPayload['vivoField'] = {'pushMode': 0};

    var huaweiClickAction = {
      'type': 1,
      'action': 'com.hestia.n168chat.app.flutter.im.push'
    };
    var config = {
      'category': 'IM',
      'data':
          jsonEncode({'sessionId': sessionId, 'sessionType': sessionType})
    };
    pushPayload['hwField'] = {
      'click_action': huaweiClickAction,
      'androidConfig': config
    };

    pushPayload['sessionId'] = sessionId;
    pushPayload['sessionType'] = sessionType;
    return pushPayload;
  }

  Widget _getIcon(Widget tabIcon, {bool showRedPoint = false}) {
    if (!showRedPoint) return tabIcon;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        tabIcon,
        if ((contactUnreadCount + teamActionsUnreadCount) > 0 ||
            chatUnreadCount > 0)
          Positioned(
            top: -2.0,
            right: -3.0,
            child: Container(
              height: 6,
              width: 6,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
          )
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: bottomNavigatorList().map((res) => res.widget).toList(),
      ),
      bottomNavigationBar: Theme(
        data: ThemeData(
          brightness: Brightness.light,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: BottomNavigationBar(
          backgroundColor: '#F6F8FA'.toColor(),
          selectedFontSize: 10,
          unselectedFontSize: 10,
          elevation: 0,
          items: List.generate(
            bottomNavigatorList().length,
            (index) => BottomNavigationBarItem(
              icon: _getIcon(
                  index == currentIndex
                      ? bottomNavigatorList()[index].selectedIcon
                      : bottomNavigatorList()[index].unselectedIcon,
                  showRedPoint: (index == 1 &&
                          (contactUnreadCount + teamActionsUnreadCount) > 0) ||
                      (index == 0 && chatUnreadCount > 0)),
              label: bottomNavigatorList()[index].title,
            ),
          ),
          currentIndex: currentIndex,
          type: BottomNavigationBarType.fixed,
          onTap: _changePage,
        ),
      ),
    );
  }

  void _changePage(int index) {
    if (index != currentIndex) {
      setState(() => currentIndex = index);
    }
  }

  List<NavigationBarData> bottomNavigatorList() {
    return getBottomNavigatorList(context);
  }

  Widget getSwindleWidget() {
    // 移除防诈骗提示 Tips
    return const SizedBox.shrink();
  }

  // ── BottomNavigation（移除了原"课堂" Tab）──────────────────────────────────
  List<NavigationBarData> getBottomNavigatorList(BuildContext context) {
    return [
      NavigationBarData(
        widget: ConversationPage(
          onUnreadCountChanged: (unreadCount) {
            setState(() => chatUnreadCount = unreadCount);
          },
          topWidget: getSwindleWidget(),
        ),
        title: S.of(context).message,
        selectedIcon: SvgPicture.asset(
          'assets/icon_session_selected.svg',
          width: 28,
          height: 28,
        ),
        unselectedIcon: SvgPicture.asset(
          'assets/icon_session_selected.svg',
          width: 28,
          height: 28,
          colorFilter: const ColorFilter.mode(
              CommonColors.color_c5c9d2, BlendMode.srcIn),
        ),
      ),
      NavigationBarData(
        widget: const ContactPage(),
        title: S.of(context).contact,
        selectedIcon: SvgPicture.asset(
          'assets/icon_contact_selected.svg',
          width: 28,
          height: 28,
        ),
        unselectedIcon: SvgPicture.asset(
          'assets/icon_contact_unselected.svg',
          width: 28,
          height: 28,
          colorFilter: const ColorFilter.mode(
              CommonColors.color_c5c9d2, BlendMode.srcIn),
        ),
      ),
      // ── "课堂" Tab 已移除，入口改为群聊加号菜单 ──────────────────────────
      NavigationBarData(
        widget: const MinePage(),
        title: S.of(context).mine,
        selectedIcon: SvgPicture.asset(
          'assets/icon_my_selected.svg',
          width: 28,
          height: 28,
        ),
        unselectedIcon: SvgPicture.asset(
          'assets/icon_my_selected.svg',
          width: 28,
          height: 28,
          colorFilter: const ColorFilter.mode(
              CommonColors.color_c5c9d2, BlendMode.srcIn),
        ),
      ),
    ];
  }
}

/// 底部导航栏数据对象
class NavigationBarData {
  final Widget unselectedIcon;
  final Widget selectedIcon;
  final String title;
  final Widget widget;

  NavigationBarData({
    required this.unselectedIcon,
    required this.selectedIcon,
    required this.title,
    required this.widget,
  });
}
