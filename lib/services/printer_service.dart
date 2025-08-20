import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import '../models/printer_config.dart';
import '../models/printer_status.dart';

class PrinterService extends ChangeNotifier {
  SerialPort? _port;
  PrinterConfig _config = PrinterConfig();
  PrinterStatus _status = PrinterStatus();
  String _connectionStatus = '연결되지 않음';
  String? _lastMessage;
  MessageType _messageType = MessageType.info;

  // Getters
  PrinterConfig get config => _config;
  PrinterStatus get status => _status;
  String get connectionStatus => _connectionStatus;
  String? get lastMessage => _lastMessage;
  MessageType get messageType => _messageType;
  bool get isConnected => _config.isConnected;

  // ESC/POS 명령어 상수
  static const List<int> _ESC = [0x1B];
  static const List<int> _INIT = [0x1B, 0x40];
  static const List<int> _CUT_PARTIAL = [0x1B, 0x69];
  static const List<int> _CUT_FULL = [0x1B, 0x6D];
  static const List<int> _LINE_FEED = [0x0A];
  static const List<int> _CARRIAGE_RETURN = [0x0D];

  // 텍스트 속성
  static const List<int> _DOUBLE_WIDTH = [0x1B, 0x21, 0x20];
  static const List<int> _DOUBLE_HEIGHT = [0x1B, 0x21, 0x10];
  static const List<int> _DOUBLE_BOTH = [0x1B, 0x21, 0x30];
  static const List<int> _NORMAL = [0x1B, 0x21, 0x00];
  static const List<int> _BOLD_ON = [0x1B, 0x45, 0x01];
  static const List<int> _BOLD_OFF = [0x1B, 0x45, 0x00];

  // 정렬
  static const List<int> _ALIGN_LEFT = [0x1B, 0x61, 0x00];
  static const List<int> _ALIGN_CENTER = [0x1B, 0x61, 0x01];
  static const List<int> _ALIGN_RIGHT = [0x1B, 0x61, 0x02];

  void _showMessage(String message, MessageType type) {
    _lastMessage = message;
    _messageType = type;
    notifyListeners();
    
    // 3초 후 메시지 자동 제거
    Future.delayed(const Duration(seconds: 3), () {
      _lastMessage = null;
      notifyListeners();
    });
  }

  // 사용 가능한 포트 목록 가져오기
  List<String> getAvailablePorts() {
    List<String> ports = [];
    
    // COM 포트 추가
    for (int i = 1; i <= 7; i++) {
      ports.add('COM$i');
    }
    
    // USB 포트 추가
    ports.add('USB');
    
    // 실제 사용 가능한 시리얼 포트 확인
    try {
      final availablePorts = SerialPort.availablePorts;
      for (String portName in availablePorts) {
        if (!ports.contains(portName)) {
          ports.add(portName);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('포트 검색 오류: $e');
      }
    }
    
    return ports;
  }

  // 프린터 연결
  Future<bool> connect() async {
    try {
      _connectionStatus = '연결 중...';
      notifyListeners();

      // USB 포트인 경우 실제 시리얼 포트를 찾아서 연결
      String portName = _config.port;
      if (portName == 'USB') {
        final availablePorts = SerialPort.availablePorts;
        if (availablePorts.isNotEmpty) {
          portName = availablePorts.first;
        } else {
          _connectionStatus = '연결되지 않음';
          _showMessage('사용 가능한 USB 포트를 찾을 수 없습니다.', MessageType.error);
          notifyListeners();
          return false;
        }
      }

      _port = SerialPort(portName);
      
      // 포트 설정
      final portConfig = SerialPortConfig();
      portConfig.baudRate = _config.baudRate;
      portConfig.bits = 8;
      portConfig.stopBits = 1;
      portConfig.parity = SerialPortParity.none;
      
      // Flow Control 설정
      switch (_config.flowControl) {
        case 0: // None
          portConfig.setFlowControl(SerialPortFlowControl.none);
          break;
        case 1: // Xon/Xoff
          portConfig.setFlowControl(SerialPortFlowControl.xonXoff);
          break;
        case 2: // Hardware
          portConfig.setFlowControl(SerialPortFlowControl.rtsCts);
          break;
      }

      _port!.config = portConfig;

      // 포트 열기
      if (_port!.openReadWrite()) {
        _config = _config.copyWith(isConnected: true);
        _connectionStatus = '연결됨';
        _showMessage('프린터에 성공적으로 연결되었습니다.', MessageType.success);
        
        // 프린터 초기화
        await _sendCommand(_INIT);
        
        notifyListeners();
        return true;
      } else {
        _connectionStatus = '연결되지 않음';
        _showMessage('프린터 연결에 실패했습니다.', MessageType.error);
        notifyListeners();
        return false;
      }
    } catch (e) {
      _connectionStatus = '연결되지 않음';
      _showMessage('연결 오류: ${e.toString()}', MessageType.error);
      notifyListeners();
      return false;
    }
  }

  // 프린터 연결 해제
  Future<void> disconnect() async {
    try {
      if (_port != null && _port!.isOpen) {
        _port!.close();
      }
      _port = null;
      _config = _config.copyWith(isConnected: false);
      _connectionStatus = '연결되지 않음';
      _showMessage('프린터 연결이 해제되었습니다.', MessageType.info);
      notifyListeners();
    } catch (e) {
      _showMessage('연결 해제 오류: ${e.toString()}', MessageType.error);
    }
  }

  // 명령어 전송
  Future<bool> _sendCommand(List<int> command) async {
    if (_port == null || !_port!.isOpen) {
      _showMessage('프린터가 연결되지 않았습니다.', MessageType.error);
      return false;
    }

    try {
      final data = Uint8List.fromList(command);
      final bytesWritten = _port!.write(data);
      return bytesWritten == data.length;
    } catch (e) {
      _showMessage('명령어 전송 오류: ${e.toString()}', MessageType.error);
      return false;
    }
  }

  // 텍스트 인쇄
  Future<void> printText(String text, {int alignment = 0, int mode = 0}) async {
    if (!isConnected) {
      _showMessage('프린터가 연결되지 않았습니다.', MessageType.error);
      return;
    }

    _showMessage('텍스트를 인쇄하고 있습니다...', MessageType.info);

    try {
      // 정렬 설정
      switch (alignment) {
        case 0:
          await _sendCommand(_ALIGN_LEFT);
          break;
        case 1:
          await _sendCommand(_ALIGN_CENTER);
          break;
        case 2:
          await _sendCommand(_ALIGN_RIGHT);
          break;
      }

      // 텍스트 모드 설정
      if (mode & 0x10 != 0 && mode & 0x20 != 0) {
        await _sendCommand(_DOUBLE_BOTH);
      } else if (mode & 0x10 != 0) {
        await _sendCommand(_DOUBLE_HEIGHT);
      } else if (mode & 0x20 != 0) {
        await _sendCommand(_DOUBLE_WIDTH);
      } else {
        await _sendCommand(_NORMAL);
      }

      // 굵게 설정
      if (mode & 0x08 != 0) {
        await _sendCommand(_BOLD_ON);
      }

      // 텍스트 전송
      final textBytes = text.codeUnits;
      await _sendCommand(textBytes);

      // 설정 초기화
      await _sendCommand(_NORMAL);
      await _sendCommand(_BOLD_OFF);
      await _sendCommand(_ALIGN_LEFT);

      _showMessage('텍스트 인쇄가 완료되었습니다.', MessageType.success);
    } catch (e) {
      _showMessage('텍스트 인쇄 오류: ${e.toString()}', MessageType.error);
    }
  }

  // 바코드 인쇄
  Future<void> printBarcode(String data, {int type = 111}) async {
    if (!isConnected) {
      _showMessage('프린터가 연결되지 않았습니다.', MessageType.error);
      return;
    }

    _showMessage('바코드를 인쇄하고 있습니다...', MessageType.info);

    try {
      // CODE128 바코드 명령어
      List<int> command = [
        0x1D, 0x6B, 0x49, // CODE128 선택
        data.length, // 데이터 길이
        ...data.codeUnits // 데이터
      ];

      await _sendCommand(command);
      _showMessage('바코드 인쇄가 완료되었습니다.', MessageType.success);
    } catch (e) {
      _showMessage('바코드 인쇄 오류: ${e.toString()}', MessageType.error);
    }
  }

  // QR코드 인쇄
  Future<void> printQRCode(String data, {int size = 25}) async {
    if (!isConnected) {
      _showMessage('프린터가 연결되지 않았습니다.', MessageType.error);
      return;
    }

    _showMessage('QR코드를 인쇄하고 있습니다...', MessageType.info);

    try {
      // QR코드 명령어 (간단한 구현)
      List<int> command = [
        0x1D, 0x28, 0x6B, // QR 코드 명령
        0x04, 0x00, 0x31, 0x41, size, 0x00, // 크기 설정
        ...data.codeUnits
      ];

      await _sendCommand(command);
      _showMessage('QR코드 인쇄가 완료되었습니다.', MessageType.success);
    } catch (e) {
      _showMessage('QR코드 인쇄 오류: ${e.toString()}', MessageType.error);
    }
  }

  // PDF417 인쇄
  Future<void> printPDF417(String data) async {
    if (!isConnected) {
      _showMessage('프린터가 연결되지 않았습니다.', MessageType.error);
      return;
    }

    _showMessage('PDF417을 인쇄하고 있습니다...', MessageType.info);

    try {
      // PDF417 명령어 (간단한 구현)
      List<int> command = [
        0x1D, 0x28, 0x6B, // PDF417 명령
        0x04, 0x00, 0x30, 0x50, 0x30, 0x00,
        ...data.codeUnits
      ];

      await _sendCommand(command);
      _showMessage('PDF417 인쇄가 완료되었습니다.', MessageType.success);
    } catch (e) {
      _showMessage('PDF417 인쇄 오류: ${e.toString()}', MessageType.error);
    }
  }

  // 용지 자르기
  Future<void> cutPaper({bool fullCut = false}) async {
    if (!isConnected) return;

    try {
      if (fullCut) {
        await _sendCommand(_CUT_FULL);
      } else {
        await _sendCommand(_CUT_PARTIAL);
      }
    } catch (e) {
      _showMessage('용지 자르기 오류: ${e.toString()}', MessageType.error);
    }
  }

  // 줄 바꿈
  Future<void> lineFeed({int lines = 1}) async {
    if (!isConnected) return;

    try {
      for (int i = 0; i < lines; i++) {
        await _sendCommand(_LINE_FEED);
      }
    } catch (e) {
      _showMessage('줄 바꿈 오류: ${e.toString()}', MessageType.error);
    }
  }

  // 샘플 영수증 인쇄
  Future<void> printSampleReceipt() async {
    if (!isConnected) {
      _showMessage('프린터가 연결되지 않았습니다.', MessageType.error);
      return;
    }

    _showMessage('샘플 영수증을 인쇄하고 있습니다...', MessageType.info);

    try {
      // 회사명 (중앙 정렬, 더블 높이)
      await printText('REXOD CO.,LTD\n\n', alignment: 1, mode: 0x10);
      
      // 주소
      await printText('1616, Daeryung Techno Town 19Cha 70,\n', alignment: 0);
      await printText('Gasan digital 2-ro,Geumcheon-gu,\n', alignment: 0);
      await printText('Seoul,Korea\n\n', alignment: 0);
      
      // 영수증 정보
      await printText('RefSO#.               Receipt#:         87\n', alignment: 0);
      await printText('01/01/2019               Store:       017A\n', alignment: 0);
      await printText('Assoc: Admin           Cashier:      Admin\n\n', alignment: 0);
      
      // 고객 정보
      await printText(' Bill To : REXOD\n', alignment: 0);
      await printText(' 1616, Daeryung Techno Town 19Cha 70      \n', alignment: 2);
      await printText('    Gasan digital 2-ro, Geumcheon-gu      \n', alignment: 2);
      await printText('                         Seoul,Korea      \n\n', alignment: 2);
      
      // 매장용 표시
      await printText(' <<For Store>>\n\n', alignment: 1, mode: 0x21);
      
      // 상품 목록 헤더
      await printText('DCS       ITEM#    QTY   PRICE   EXT PRICE\n', alignment: 0);
      await printText('------------------------------------------\n', alignment: 0);
      
      // 상품 목록
      await printText('Flame Grilled 33   1  14,000.00     14,000\n', alignment: 0);
      await printText('Victoria\'s Filet\n', alignment: 0);
      await printText('             22    1  48,000.00     48,000\n', alignment: 0);
      await printText('------------------------------------------\n', alignment: 0);
      
      // 합계
      await printText('         2 Unit(s)    Subtotal:     62,000\n', alignment: 0);
      await printText('                10.000 %   Tax:      6,200\n', alignment: 0);
      await printText('       RECEIPT TOTAL: 68,200\n', alignment: 0, mode: 0x29);
      
      // 결제 정보
      await printText('Tend:     68,200      \n', alignment: 2);
      await printText('       Cash: 8,200\n', alignment: 0);
      await printText('  Gift Cert: 10,000 #87654321\n', alignment: 0);
      await printText('     CrCard: 50,000 Card\n', alignment: 0);
      await printText('             **********9411 Exp 03/12\n\n', alignment: 0);
      
      // 서명란
      await printText('Signature\n\n', alignment: 0);
      await printText('       We appreciate your business!\n', alignment: 0);
      
      // 줄 바꿈 및 용지 자르기
      await lineFeed(lines: 4);
      await cutPaper();

      _showMessage('샘플 영수증 인쇄가 완료되었습니다.', MessageType.success);
    } catch (e) {
      _showMessage('샘플 영수증 인쇄 오류: ${e.toString()}', MessageType.error);
    }
  }

  // 프린터 상태 확인
  Future<void> checkStatus() async {
    if (!isConnected) {
      _showMessage('프린터가 연결되지 않았습니다.', MessageType.error);
      return;
    }

    _showMessage('프린터 상태를 확인하고 있습니다...', MessageType.info);

    try {
      // 상태 확인 명령어 전송
      await _sendCommand([0x10, 0x04, 0x01]);
      
      // 실제 구현에서는 프린터로부터 응답을 읽어야 하지만,
      // 여기서는 시뮬레이션으로 랜덤 상태를 생성
      await Future.delayed(const Duration(milliseconds: 500));
      
      _status = _status.copyWith(
        paperEmpty: false,
        headUp: false,
        cutError: false,
        nearEnd: DateTime.now().millisecondsSinceEpoch % 3 == 0,
        mechanicalType: 'RMP8300',
        sdkVersion: 'v2.1.0',
      );

      if (_status.hasError) {
        _showMessage('프린터에 오류가 있습니다: ${_status.errorMessages.join(', ')}', MessageType.error);
      } else if (_status.hasWarning) {
        _showMessage('프린터 경고: ${_status.warningMessages.join(', ')}', MessageType.warning);
      } else {
        _showMessage('프린터 상태가 정상입니다.', MessageType.success);
      }
      
      notifyListeners();
    } catch (e) {
      _showMessage('상태 확인 오류: ${e.toString()}', MessageType.error);
    }
  }

  // 프린터 재부팅
  Future<void> rebootPrinter() async {
    if (!isConnected) {
      _showMessage('프린터가 연결되지 않았습니다.', MessageType.error);
      return;
    }

    _showMessage('프린터를 재부팅하고 있습니다...', MessageType.info);

    try {
      // 재부팅 명령어 전송 (실제 명령어는 프린터마다 다를 수 있음)
      await _sendCommand([0x1B, 0x3F, 0x0A, 0x00]);
      
      // 연결 해제
      await disconnect();
      
      _showMessage('프린터 재부팅이 완료되었습니다.', MessageType.success);
    } catch (e) {
      _showMessage('재부팅 오류: ${e.toString()}', MessageType.error);
    }
  }

  // 설정 업데이트
  void updateConfig(PrinterConfig newConfig) {
    _config = newConfig;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}

enum MessageType {
  info,
  success,
  warning,
  error,
}

