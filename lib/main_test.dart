import 'package:flutter/material.dart';
import 'test_app.dart';

void main() {
  runApp(const TestMainApp());
}

class TestMainApp extends StatelessWidget {
  const TestMainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '프린터 연결 테스트',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const TestApp(),
    );
  }
}

