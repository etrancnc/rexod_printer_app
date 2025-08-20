import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

class TestApp extends StatefulWidget {
  const TestApp({super.key});

  @override
  State<TestApp> createState() => _TestAppState();
}

class _TestAppState extends State<TestApp> {
  List<String> _availablePorts = [];
  String? _selectedPort;
  SerialPort? _port;
  bool _isConnected = false;
  String _status = '연결되지 않음';
  String _log = '';

  @override
  void initState() {
    super.initState();
    _refreshPorts();
  }

  void _refreshPorts() {
    setState(() {
      _availablePorts = SerialPort.availablePorts;
      _log += '사용 가능한 포트: ${_availablePorts.join(', ')}\n';
    });
  }

  Future<void> _connect() async {
    if (_selectedPort == null) {
      _addLog('포트를 선택하세요.');
      return;
    }

    try {
      _port = SerialPort(_selectedPort!);
      
      final config = SerialPortConfig();
      config.baudRate = 115200;
      config.bits = 8;
      config.stopBits = 1;
      config.parity = SerialPortParity.none;
      config.setFlowControl(SerialPortFlowControl.rtsCts);
      
      _port!.config = config;
      
      if (_port!.openReadWrite()) {
        setState(() {
          _isConnected = true;
          _status = '연결됨';
        });
        _addLog('포트 $_selectedPort에 성공적으로 연결되었습니다.');
        
        // 프린터 초기화 명령 전송
        final initCommand = [0x1B, 0x40];
        final bytesWritten = _port!.write(Uint8List.fromList(initCommand));
        _addLog('초기화 명령 전송: $bytesWritten bytes');
        
      } else {
        final error = SerialPort.lastError;
        _addLog('연결 실패: ${error?.message ?? "알 수 없는 오류"}');
      }
    } catch (e) {
      _addLog('연결 오류: $e');
    }
  }

  Future<void> _disconnect() async {
    if (_port != null && _port!.isOpen) {
      _port!.close();
    }
    _port = null;
    setState(() {
      _isConnected = false;
      _status = '연결되지 않음';
    });
    _addLog('연결이 해제되었습니다.');
  }

  Future<void> _testPrint() async {
    if (!_isConnected || _port == null) {
      _addLog('프린터가 연결되지 않았습니다.');
      return;
    }

    try {
      // 테스트 텍스트 인쇄
      final testText = 'TEST PRINT\n';
      final textBytes = testText.codeUnits;
      final bytesWritten = _port!.write(Uint8List.fromList(textBytes));
      _addLog('테스트 인쇄: $bytesWritten bytes 전송');
      
      // 줄바꿈
      final lineFeed = [0x0A];
      _port!.write(Uint8List.fromList(lineFeed));
      
    } catch (e) {
      _addLog('인쇄 오류: $e');
    }
  }

  void _addLog(String message) {
    setState(() {
      _log += '${DateTime.now().toString().substring(11, 19)}: $message\n';
    });
  }

  void _clearLog() {
    setState(() {
      _log = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('프린터 연결 테스트'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 포트 선택
            Row(
              children: [
                const Text('포트: '),
                Expanded(
                  child: DropdownButton<String>(
                    value: _selectedPort,
                    hint: const Text('포트 선택'),
                    items: _availablePorts.map((port) {
                      return DropdownMenuItem(
                        value: port,
                        child: Text(port),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedPort = value;
                      });
                    },
                  ),
                ),
                IconButton(
                  onPressed: _refreshPorts,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // 상태 표시
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isConnected ? Colors.green.shade50 : Colors.red.shade50,
                border: Border.all(
                  color: _isConnected ? Colors.green : Colors.red,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '상태: $_status',
                style: TextStyle(
                  color: _isConnected ? Colors.green.shade800 : Colors.red.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // 버튼들
            Row(
              children: [
                ElevatedButton(
                  onPressed: _isConnected ? null : _connect,
                  child: const Text('연결'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isConnected ? _disconnect : null,
                  child: const Text('연결 해제'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isConnected ? _testPrint : null,
                  child: const Text('테스트 인쇄'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // 로그
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '로그:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: _clearLog,
                  child: const Text('지우기'),
                ),
              ],
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _log,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _disconnect();
    super.dispose();
  }
}

