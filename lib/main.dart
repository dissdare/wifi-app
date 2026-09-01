import 'package:flutter/material.dart';

import 'auto_login_screen.dart';

void main() {
  runApp(const BoardControlApp());
}

class BoardControlApp extends StatelessWidget {
  final bool autoConnect;

  const BoardControlApp({super.key, this.autoConnect = true});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '主板控制台',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.light,
      ),
      home: AutoLoginScreen(autoConnect: autoConnect),
    );
  }
}
