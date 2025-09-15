import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ← 로그 복사용
import 'package:http/http.dart' as dio;
import 'package:provider/provider.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'services/real_printer_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => RealPrinterService(),
      child: MaterialApp(
        title: 'REXOD RX830-V120 프린터 제어 애플리케이션',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        // 자동 스크롤바 비활성화 (RawScrollbar/PrimaryScrollController 충돌 방지)
        scrollBehavior: const MaterialScrollBehavior().copyWith(scrollbars: false),
        home: const PrinterControlScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class PrinterControlScreen extends StatefulWidget {
  const PrinterControlScreen({super.key});

  @override
  State<PrinterControlScreen> createState() => _PrinterControlScreenState();
}

class _PrinterControlScreenState extends State<PrinterControlScreen> {
  final ScrollController _logCtrl = ScrollController();

  // ★ 포트 목록을 로컬 상태로 관리 (build 중 Provider 메서드 호출 피하기)
  List<String> _ports = [];
  String? _selectedPort;
  bool _portsLoading = false;

  // ★ 로그 자동 스크롤용
  int _lastLogCount = 0;

  @override
  void initState() {
    super.initState();
    // 첫 프레임 그린 다음에 포트 로드 (빌드 중 notify 방지)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPorts();
    });
  }

  Future<void> _loadPorts() async {
    final service = context.read<RealPrinterService>();
    setState(() => _portsLoading = true);

    // 포트 조회 시, 서비스에 '조용 모드'로 요청 → notifyListeners 방지
    final ports = [...service.getAvailablePorts(quiet: true)];
    if (!ports.contains('USB')) ports.add('USB');

    if (!mounted) return; // 안전장치
    setState(() {
      _ports = ports;
      _selectedPort = ports.contains(service.config.port)
          ? service.config.port
          : (ports.isNotEmpty ? ports.first : null);
      _portsLoading = false;
    });
  }

  @override
  void dispose() {
    _logCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Row(
          children: [
            Icon(MdiIcons.printer, size: 28),
            const SizedBox(width: 8),
            const Text('REXOD 프린터 제어 애플리케이션'),
          ],
        ),
        actions: [
          // 포트 새로고침 → build 밖에서 로컬 상태 갱신
          IconButton(
            tooltip: '포트 새로고침',
            onPressed: _loadPorts,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Consumer<RealPrinterService>(
        builder: (context, printerService, child) {
          // ★ 로그 자동 스크롤: 길이가 증가했으면 맨 아래로
          final logCount = printerService.logs.length;
          if (logCount != _lastLogCount) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_logCtrl.hasClients) {
                _logCtrl.jumpTo(_logCtrl.position.maxScrollExtent);
              }
            });
            _lastLogCount = logCount;
          }

          return Column(
            children: [
              // 메시지 알림
              if (printerService.lastMessage != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _getMessageColor(printerService.messageType),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _getMessageBorderColor(printerService.messageType),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _getMessageIcon(printerService.messageType),
                        color: _getMessageIconColor(printerService.messageType),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          printerService.lastMessage!,
                          style: TextStyle(
                            color: _getMessageTextColor(printerService.messageType),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (printerService.lastErrorDetails != null)
                        TextButton(
                          onPressed: () => _showDetails(context, printerService.lastErrorDetails!),
                          child: const Text('자세히'),
                        )
                    ],
                  ),
                ),

              // 메인 콘텐츠
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 좌측 연결 패널 (스크롤 가능)
                    SizedBox(
                      width: 320,
                      child: Card(
                        margin: const EdgeInsets.all(8),
                        child: SingleChildScrollView(
                          primary: false,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // 연결 설정 헤더
                                Row(
                                  children: [
                                    Icon(
                                      printerService.isConnected ? MdiIcons.wifi : MdiIcons.wifiOff,
                                      color: printerService.isConnected ? Colors.green : Colors.grey,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      '연결 설정',
                                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                const Text('프린터 연결을 설정하고 관리합니다.', style: TextStyle(color: Colors.grey)),
                                const SizedBox(height: 16),

                                // 포트 선택 (로컬 상태 사용)
                                const Text('포트', style: TextStyle(fontWeight: FontWeight.w500)),
                                const SizedBox(height: 4),
                                if (_portsLoading)
                                  const LinearProgressIndicator(minHeight: 4)
                                else
                                  DropdownButtonFormField<String>(
                                    value: (_selectedPort != null && _ports.contains(_selectedPort))
                                        ? _selectedPort
                                        : (_ports.isNotEmpty ? _ports.first : null),
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    ),
                                    items: _ports
                                        .map((port) => DropdownMenuItem(
                                      value: port,
                                      child: Text(port == 'USB' ? 'USB (자동탐지)' : port),
                                    ))
                                        .toList(),
                                    onChanged: printerService.isConnected
                                        ? null
                                        : (value) {
                                      if (value != null) {
                                        setState(() => _selectedPort = value);
                                        printerService.updateConfig(
                                          printerService.config.copyWith(port: value),
                                        );
                                      }
                                    },
                                  ),
                                const SizedBox(height: 12),

                                // 자동탐지 연결 버튼
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.usb),
                                    label: const Text('USB 자동탐지로 연결'),
                                    onPressed: (!printerService.isConnected && !printerService.isConnecting)
                                        ? () async {
                                      // USB로 설정 후 연결
                                      setState(() => _selectedPort = 'USB');
                                      printerService.updateConfig(
                                        printerService.config.copyWith(port: 'USB'),
                                      );
                                      await printerService.connect();
                                    }
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Baud Rate
                                const Text('Baud Rate', style: TextStyle(fontWeight: FontWeight.w500)),
                                const SizedBox(height: 4),
                                DropdownButtonFormField<int>(
                                  value: printerService.config.baudRate,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                  items: [9600, 19200, 38400, 57600, 115200]
                                      .map((rate) => DropdownMenuItem(value: rate, child: Text(rate.toString())))
                                      .toList(),
                                  onChanged: printerService.isConnected
                                      ? null
                                      : (value) {
                                    if (value != null) {
                                      printerService.updateConfig(
                                        printerService.config.copyWith(baudRate: value),
                                      );
                                    }
                                  },
                                ),
                                const SizedBox(height: 16),

                                // Flow Control
                                const Text('Flow Control', style: TextStyle(fontWeight: FontWeight.w500)),
                                const SizedBox(height: 4),
                                DropdownButtonFormField<int>(
                                  value: printerService.config.flowControl,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                  items: const [
                                    DropdownMenuItem(value: 0, child: Text('None')),
                                    DropdownMenuItem(value: 1, child: Text('Xon/Xoff')),
                                    DropdownMenuItem(value: 2, child: Text('Hardware')),
                                  ],
                                  onChanged: printerService.isConnected
                                      ? null
                                      : (value) {
                                    if (value != null) {
                                      printerService.updateConfig(
                                        printerService.config.copyWith(flowControl: value),
                                      );
                                    }
                                  },
                                ),
                                const SizedBox(height: 16),

                                const Divider(),
                                const SizedBox(height: 16),

                                // 연결 상태
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('상태:', style: TextStyle(fontWeight: FontWeight.w500)),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: printerService.isConnected ? Colors.green : Colors.grey,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        printerService.connectionStatus,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // 연결/해제 버튼
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: printerService.isConnected || printerService.isConnecting
                                        ? null
                                        : () => printerService.connect(),
                                    child: printerService.isConnecting
                                        ? const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        ),
                                        SizedBox(width: 8),
                                        Text('연결 중...'),
                                      ],
                                    )
                                        : const Text('연결'),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    onPressed: printerService.isConnected ? () => printerService.disconnect() : null,
                                    child: const Text('연결 해제'),
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // 프린터 상태
                                const Text('프린터 상태',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                _buildStatusRow('기계 타입', printerService.status.mechanicalType),
                                _buildStatusRow('SDK 버전', printerService.status.sdkVersion),

                                // ★ 용지 상태: paperEmpty > nearEnd > 정상
                                Builder(
                                  builder: (_) {
                                    final svc = printerService;
                                    String paperText;
                                    Color? paperColor;

                                    if (!svc.isConnected) {
                                      paperText = '미연결';
                                    } else if (!svc.canReportPaperStatus) {
                                      paperText = '알 수 없음';
                                    } else if (!svc.statusKnown) {
                                      paperText = '알 수 없음';
                                    } else {
                                      final s = svc.status;
                                      if (s.paperEmpty) {
                                        paperText = '없음';
                                        paperColor = Colors.red;
                                      } else if (s.nearEnd) {
                                        paperText = '부족 경고';
                                        paperColor = Colors.orange;
                                      } else {
                                        paperText = '정상';
                                      }
                                    }
                                    return _buildStatusRow('용지 상태', paperText, valueColor: paperColor);
                                  },
                                ),

                                // 추가 표시: 연결 방식/스풀러 프린터명
                                _buildStatusRow('연결 방식', printerService.transport),
                                _buildStatusRow('스풀러 프린터', printerService.spoolPrinterName ?? '-'),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: printerService.isConnected ? () => printerService.checkStatus() : null,
                                    icon: Icon(MdiIcons.refresh, size: 16),
                                    label: const Text('상태 새로고침'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // 우측 기능 버튼 영역 (스크롤 가능, Expanded 제거)
                    Expanded(
                      child: Card(
                        margin: const EdgeInsets.all(8),
                        child: SingleChildScrollView(
                          primary: false,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('프린터 기능',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                const Text('다양한 인쇄 기능을 테스트할 수 있습니다.',
                                    style: TextStyle(color: Colors.grey)),
                                const SizedBox(height: 16),

                                // 기능 버튼 그리드 (스크롤뷰 안이므로 shrinkWrap/physics)
                                GridView.count(
                                  crossAxisCount: 4,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 1.2,
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  children: [
                                    _buildFunctionButton(
                                      context,
                                      '텍스트 인쇄',
                                      MdiIcons.formatText,
                                          () async {
                                        final success = await printerService.printText(
                                          '안녕하세요\n\nDouble Width\nDouble Height\nDouble Width,Height\n',
                                        );
                                        if (!success) {}
                                      },
                                      printerService.isConnected && !printerService.isPrinting,
                                      isLoading: printerService.isPrinting,
                                    ),
                                    _buildFunctionButton(
                                      context,
                                      '바코드 인쇄',
                                      MdiIcons.barcode,
                                          () async {
                                        final success =
                                        await printerService.printBarcode('0123456789AB');
                                        if (!success) {}
                                      },
                                      printerService.isConnected && !printerService.isPrinting,
                                      isLoading: printerService.isPrinting,
                                    ),
                                    _buildFunctionButton(
                                      context,
                                      'PDF417 인쇄',
                                      MdiIcons.qrcode,
                                          () async {
                                        final success =
                                        await printerService.printPDF417('1234567890');
                                        if (!success) {}
                                      },
                                      printerService.isConnected && !printerService.isPrinting,
                                      isLoading: printerService.isPrinting,
                                    ),

                                    _buildFunctionButton(
                                      context,
                                      'QR코드 인쇄',
                                      MdiIcons.qrcode,
                                          () async {
                                        final success =
                                        await printerService.printQRCode('REXOD.NET');
                                        if (!success) {}
                                      },
                                      printerService.isConnected && !printerService.isPrinting,
                                      isLoading: printerService.isPrinting,
                                    ),
                                    _buildFunctionButton(
                                      context,
                                      '이미지 인쇄',
                                      MdiIcons.image,
                                          () => _showNotImplemented(context),
                                      printerService.isConnected && !printerService.isPrinting,
                                    ),
                                    _buildFunctionButton(
                                      context,
                                      '상태 확인',
                                      MdiIcons.information,
                                          () => printerService.checkStatus(),
                                      printerService.isConnected && !printerService.isPrinting,
                                    ),
                                    _buildFunctionButton(
                                      context,
                                      '샘플 영수증',
                                      MdiIcons.receipt,
                                          () async {
                                            final url = 'https://qrcode.nijimori.kr/v1/print/orcode_receipt?orcode=2c6df4399d6051de2700.png';

                                            // 기존 샘플 호출 주석 처리 후 ↓ 이걸로 교체
                                            final success = await printerService.printTicketInlineFromUrl(
                                              url: url,
                                              columns: 48,      // 80mm 보통 48, 58mm면 32/42 중 기기 맞게
                                              cp437Index: 0,    // 한자 나오면 16으로 바꿔서 재시도
                                            );
                                        if (!success) {}
                                      },
                                      printerService.isConnected && !printerService.isPrinting,
                                      isLoading: printerService.isPrinting,
                                    ),
                                    _buildFunctionButton(
                                      context,
                                      '프린터 재부팅',
                                      MdiIcons.restart,
                                          () async {
                                        final success = await printerService.rebootPrinter();
                                        if (!success) {}
                                      },
                                      printerService.isConnected && !printerService.isPrinting,
                                      isLoading: printerService.isPrinting,
                                    ),
                                    // ★ RAW 테스트 버튼
                                    _buildFunctionButton(
                                      context,
                                      'RAW 테스트',
                                      MdiIcons.fileSend,
                                          () async {
                                        final ok = await printerService.printRawSelfTest();
                                        if (!ok) {}
                                      },
                                      printerService.isConnected && !printerService.isPrinting,
                                      isLoading: printerService.isPrinting,
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 16),

                                // 샘플 영수증 미리보기
                                const Text('샘플 영수증 미리보기',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                Container(
                                  height: 200,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(color: Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const SingleChildScrollView(
                                    child: Text(
                                      'REXOD CO.,LTD\n\n'
                                          '1616, Daeryung Techno Town 19Cha 70,\n'
                                          'Gasan digital 2-ro,Geumcheon-gu,\n'
                                          'Seoul,Korea\n\n'
                                          'RefSO#.               Receipt#:         87\n'
                                          '01/01/2019               Store:       017A\n'
                                          'Assoc: Admin           Cashier:      Admin\n\n'
                                          'Bill To : REXOD\n'
                                          '1616, Daeryung Techno Town 19Cha 70\n'
                                          'Gasan digital 2-ro, Geumcheon-gu\n'
                                          'Seoul,Korea\n\n'
                                          '<<For Store>>\n\n'
                                          'DCS       ITEM#    QTY   PRICE   EXT PRICE\n'
                                          '------------------------------------------\n'
                                          'Flame Grilled 33   1  14,000.00     14,000\n'
                                          'Victoria\'s Filet\n'
                                          '22    1  48,000.00     48,000\n'
                                          '------------------------------------------\n'
                                          '2 Unit(s)    Subtotal:     62,000\n'
                                          '10.000 %   Tax:      6,200\n'
                                          'RECEIPT TOTAL: 68,200\n'
                                          'Tend:     68,200\n'
                                          'Cash: 8,200\n'
                                          'Gift Cert: 10,000 #87654321\n'
                                          'CrCard: 50,000 Card\n'
                                          '**********9411 Exp 03/12\n\n'
                                          'Signature\n\n'
                                          'We appreciate your business!',
                                      style: TextStyle(fontFamily: 'monospace', fontSize: 11),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 16),

                                // ★ 실시간 로그 패널
                                const Text('실시간 로그',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: printerService.logs.isEmpty
                                          ? null
                                          : () {
                                        Clipboard.setData(
                                          ClipboardData(text: printerService.logs.join('\n')),
                                        );
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                              content: Text('로그를 클립보드에 복사했습니다.')),
                                        );
                                      },
                                      icon: Icon(MdiIcons.contentCopy, size: 16),
                                      label: const Text('복사'),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      onPressed: printerService.logs.isEmpty
                                          ? null
                                          : () => printerService.clearLogs(),
                                      icon: Icon(MdiIcons.deleteOutline, size: 16),
                                      label: const Text('지우기'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  height: 180,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Scrollbar(
                                    controller: _logCtrl,
                                    child: ListView.builder(
                                      controller: _logCtrl,
                                      itemCount: printerService.logs.length,
                                      itemBuilder: (_, i) => Text(
                                        printerService.logs[i],
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 11,
                                          color: Colors.greenAccent,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusRow(
      String label,
      String value, {
        bool isWarning = false, // 기존 호출부 호환
        Color? valueColor,      // 직접 색 지정 가능 (우선순위↑)
      }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: valueColor ?? (isWarning ? Colors.orange : null),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFunctionButton(
      BuildContext context,
      String label,
      IconData icon,
      VoidCallback onPressed,
      bool enabled, {
        bool isLoading = false,
      }) {
    return Card(
      elevation: enabled ? 2 : 0,
      child: InkWell(
        onTap: enabled && !isLoading ? onPressed : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  icon,
                  size: 32,
                  color: enabled ? Theme.of(context).primaryColor : Colors.grey,
                ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: enabled ? null : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNotImplemented(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('이 기능은 아직 구현되지 않았습니다.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showDetails(BuildContext context, String details) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('오류 상세'),
        content: SingleChildScrollView(
          child: Text(details, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('닫기')),
        ],
      ),
    );
  }

  Color _getMessageColor(MessageType type) {
    switch (type) {
      case MessageType.success:
        return Colors.green.shade50;
      case MessageType.error:
        return Colors.red.shade50;
      case MessageType.warning:
        return Colors.orange.shade50;
      case MessageType.info:
      return Colors.blue.shade50;
    }
  }

  Color _getMessageBorderColor(MessageType type) {
    switch (type) {
      case MessageType.success:
        return Colors.green.shade300;
      case MessageType.error:
        return Colors.red.shade300;
      case MessageType.warning:
        return Colors.orange.shade300;
      case MessageType.info:
      return Colors.blue.shade300;
    }
  }

  Color _getMessageTextColor(MessageType type) {
    switch (type) {
      case MessageType.success:
        return Colors.green.shade800;
      case MessageType.error:
        return Colors.red.shade800;
      case MessageType.warning:
        return Colors.orange.shade800;
      case MessageType.info:
      return Colors.blue.shade800;
    }
  }

  Color _getMessageIconColor(MessageType type) {
    switch (type) {
      case MessageType.success:
        return Colors.green.shade600;
      case MessageType.error:
        return Colors.red.shade600;
      case MessageType.warning:
        return Colors.orange.shade600;
      case MessageType.info:
      return Colors.blue.shade600;
    }
  }

  IconData _getMessageIcon(MessageType type) {
    switch (type) {
      case MessageType.success:
        return MdiIcons.checkCircle;
      case MessageType.error:
        return MdiIcons.alertCircle;
      case MessageType.warning:
        return MdiIcons.alert;
      case MessageType.info:
      default:
        return MdiIcons.information;
    }
  }
}
