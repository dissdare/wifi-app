// 启动页冒烟测试：验证应用能启动并渲染自动登录页。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:board_control/main.dart';

void main() {
  testWidgets('启动页正常渲染', (WidgetTester tester) async {
    // autoConnect: false 跳过真实网络连接，仅验证界面渲染。
    await tester.pumpWidget(const BoardControlApp(autoConnect: false));
    await tester.pump();

    expect(find.text('主板控制台'), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
    expect(find.text('已断开连接'), findsOneWidget);
    expect(find.text('重新连接'), findsOneWidget);
  });
}
