// 启动页冒烟测试：验证应用能启动并渲染首页。
import 'package:flutter_test/flutter_test.dart';

import 'package:board_control/main.dart';

void main() {
  testWidgets('首页正常渲染', (WidgetTester tester) async {
    // autoConnect: false 跳过真实网络连接，仅验证界面渲染。
    await tester.pumpWidget(const BoardControlApp(autoConnect: false));
    await tester.pump();

    expect(find.text('主板控制台'), findsOneWidget);
    expect(find.text('wifi连接主板'), findsOneWidget);
    expect(find.text('远程连接主板'), findsOneWidget);
  });
}
