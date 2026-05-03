// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:im_demo/src/push/apns_token_store.dart';
import 'package:netease_common_ui/utils/color_utils.dart';
import 'package:netease_common_ui/widgets/common_browse_page.dart';

import '../../l10n/S.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Widget divider = const Divider(
      color: CommonColors.color_f5f8fc,
      height: 1,
      thickness: 1,
      indent: 20,
    );
    TextStyle _style =
        const TextStyle(fontSize: 14, color: CommonColors.color_333333);
    return Scaffold(
      body: Container(
        color: Colors.white,
        child: Column(
          children: [
            const SizedBox(
              height: 102,
            ),
            SvgPicture.asset(
              'assets/ic_yunxin.svg',
              width: 46,
              height: 46,
            ),
            Text(
              S.of(context).yunxinName,
              style: const TextStyle(
                  fontSize: 24, color: CommonColors.color_333333),
            ),
            const SizedBox(
              height: 45,
            ),
            divider,
            ListTile(
              title: Text(
                S.of(context).mineVersion,
                style: _style,
              ),
              // 如果引入package_info 则不需要手动修改此处，但是如果只为了版本号引入不值得
              trailing: Text(
                'V10.7.7',
                style: _style,
              ),
            ),
            divider,
            ListTile(
              title: Text(
                S.of(context).mineProduct,
                style: _style,
              ),
              trailing: SvgPicture.asset(
                'assets/ic_right_arrow.svg',
                height: 16,
                width: 16,
              ),
              onTap: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => CommonBrowser(
                            title: S.of(context).mineAbout,
                            url: 'https://netease.im/m/')));
              },
            ),
            divider,
            if (Platform.isIOS) ...[
              ListTile(
                title: Text(
                  '推送诊断（可复制）',
                  style: _style,
                ),
                subtitle: Text(
                  '云信证书名: apns\n'
                  'Token: ${ApnsTokenStore.tokenPreview}\n'
                  '上报: ${ApnsTokenStore.lastUpdateSummary}',
                  style: const TextStyle(
                      fontSize: 12, color: CommonColors.color_666666),
                ),
                trailing: const Icon(Icons.copy, size: 20),
                onTap: () {
                  final text =
                      'apnsCername=apns\n${ApnsTokenStore.fullTokenHex.isNotEmpty ? "deviceToken=${ApnsTokenStore.fullTokenHex}" : "deviceToken=(无)"}\n${ApnsTokenStore.lastUpdateSummary}';
                  Clipboard.setData(ClipboardData(text: text));
                  Fluttertoast.showToast(msg: '已复制到剪贴板');
                },
              ),
              divider,
            ],
          ],
        ),
      ),
    );
  }
}
