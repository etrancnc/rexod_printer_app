import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

class ErrorDialog extends StatelessWidget {
  final String title;
  final String message;
  final String? details;
  final List<String>? suggestions;

  const ErrorDialog({
    super.key,
    required this.title,
    required this.message,
    this.details,
    this.suggestions,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String message,
    String? details,
    List<String>? suggestions,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => ErrorDialog(
        title: title,
        message: message,
        details: details,
        suggestions: suggestions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: Icon(
        MdiIcons.alertCircle,
        color: Colors.red,
        size: 48,
      ),
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            if (details != null) ...[
              const SizedBox(height: 16),
              const Text(
                '상세 정보:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  details!,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ],
            if (suggestions != null && suggestions!.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                '해결 방법:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              ...suggestions!.map((suggestion) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• '),
                    Expanded(child: Text(suggestion)),
                  ],
                ),
              )),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('확인'),
        ),
      ],
    );
  }
}

class ConnectionErrorDialog extends ErrorDialog {
  ConnectionErrorDialog({
    super.key,
    required String message,
    String? details,
  }) : super(
          title: '연결 오류',
          message: message,
          details: details,
          suggestions: const [
            '프린터가 켜져 있고 올바르게 연결되었는지 확인하세요.',
            '다른 애플리케이션에서 포트를 사용하고 있지 않은지 확인하세요.',
            '프린터 드라이버가 설치되었는지 확인하세요.',
            '포트 설정(Baud Rate, Flow Control)이 올바른지 확인하세요.',
            'USB 케이블이나 시리얼 케이블이 손상되지 않았는지 확인하세요.',
          ],
        );

  static Future<void> show(
    BuildContext context, {
    required String message,
    String? details,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => ConnectionErrorDialog(
        message: message,
        details: details,
      ),
    );
  }
}

class PrintErrorDialog extends ErrorDialog {
  PrintErrorDialog({
    super.key,
    required String message,
    String? details,
  }) : super(
          title: '인쇄 오류',
          message: message,
          details: details,
          suggestions: const [
            '프린터에 용지가 충분히 있는지 확인하세요.',
            '프린터 헤드가 올바르게 닫혀 있는지 확인하세요.',
            '프린터에 오류 상태가 없는지 확인하세요.',
            '프린터 연결이 안정적인지 확인하세요.',
            '프린터를 재부팅해보세요.',
          ],
        );

  static Future<void> show(
    BuildContext context, {
    required String message,
    String? details,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => PrintErrorDialog(
        message: message,
        details: details,
      ),
    );
  }
}

