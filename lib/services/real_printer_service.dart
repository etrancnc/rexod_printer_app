import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import '../models/printer_config.dart';
import '../models/printer_status.dart';
import 'winspool_raw.dart';
import 'package:charset_converter/charset_converter.dart';

/// 메시지 타입
enum MessageType { info, success, warning, error }

class RealPrinterService extends ChangeNotifier {
  // --- 공통 상태 ---
  PrinterConfig _config = PrinterConfig();
  PrinterStatus _status = PrinterStatus();
  String _connectionStatus = '연결되지 않음';
  String? _lastMessage;
  String? _lastErrorDetails;
  MessageType _messageType = MessageType.info;
  bool _isConnecting = false;
  bool _isPrinting = false;

  // ★ 용지 상태가 ‘확정’인지 여부(초기/USB/미응답이면 false)
  bool _statusKnown = false;

  // --- 직렬(Serial) 경로 ---
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription? _readerSubscription;

  // --- 스풀러(USB) 경로 ---
  bool _useSpooler = false;
  WinSpoolRaw? _spool;
  String? _spoolPrinterName; // 실제 연결된 프린터 표시명

  // --- 로그 ---
  final List<String> _logs = [];
  static const int _maxLogs = 500;

  // ===== Getters =====
  PrinterConfig get config => _config;
  PrinterStatus get status => _status;
  String get connectionStatus => _connectionStatus;
  String? get lastMessage => _lastMessage;
  String? get lastErrorDetails => _lastErrorDetails;
  MessageType get messageType => _messageType;

  /// 화면에서 표시할 연결 방식 (미연결/미선택 라벨 포함)
  String get transport {
    if (!isConnected) {
      if (_config.port == 'USB') return 'USB(스풀러, 미연결)';
      if ((_config.port).isEmpty) return '미선택';
      return '직렬(COM, 미연결)';
    }
    return _useSpooler ? 'USB(스풀러)' : '직렬(COM)';
  }

  /// 스풀러 경로일 때 선택된 프린터명
  String? get spoolPrinterName => _spoolPrinterName;

  /// 연결 여부
  bool get isConnected =>
      _useSpooler ? (_spool?.isOpen ?? false) : (_port != null && _port!.isOpen && _config.isConnected);

  bool get isConnecting => _isConnecting;
  bool get isPrinting => _isPrinting;

  /// 용지 상태 보고 가능 여부(USB는 불가)
  bool get canReportPaperStatus => !_useSpooler && isConnected;

  /// 용지 상태가 확정되었는지(최초 상태 수신 전에는 false)
  bool get statusKnown => _statusKnown;

  /// 로그(읽기 전용)
  UnmodifiableListView<String> get logs => UnmodifiableListView(_logs);

  // ESC/POS 시퀀스
  static const List<int> _INIT = [0x1B, 0x40];
  static const List<int> _STATUS_REQUEST = [0x10, 0x04, 0x01];
  static const List<int> _LINE_FEED = [0x0A];
  static const List<int> _CUT_PARTIAL = [0x1D, 0x56, 0x42, 0x03]; // GS V B n

  // ===== 로그 유틸 =====
  void _log(String msg, {MessageType type = MessageType.info, bool notify = true}) {
    final ts = _ts();
    _logs.add('[$ts] $msg');
    if (_logs.length > _maxLogs) {
      _logs.removeRange(0, _logs.length - _maxLogs);
    }
    _lastMessage = msg;
    _messageType = type;
    if (notify) notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  String _ts() {
    final n = DateTime.now();
    String two(int x) => x.toString().padLeft(2, '0');
    String three(int x) => x.toString().padLeft(3, '0');
    return '${two(n.hour)}:${two(n.minute)}:${two(n.second)}.${three(n.millisecond)}';
  }

  String _hexDump(List<int> bytes, {int max = 128}) {
    final take = bytes.length > max ? max : bytes.length;
    final head = bytes.take(take).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    if (bytes.length > take) return '$head ... (+${bytes.length - take} bytes)';
    return head;
  }

  // ===== 메시지 표시 =====
  void _showMessage(String message, MessageType type, {String? details}) {
    _lastMessage = message;
    _messageType = type;
    _lastErrorDetails = details;
    _log('MSG(${type.name}): $message${details != null ? ' [details: $details]' : ''}');
    notifyListeners();
    Future.delayed(const Duration(seconds: 5), () {
      if (_lastMessage == message) {
        _lastMessage = null;
        _lastErrorDetails = null;
        notifyListeners();
      }
    });
  }

  // ===== 포트 스캔 (조용 모드 지원) =====
  List<String> getAvailablePorts({bool quiet = false}) {
    final ports = <String>[];
    try {
      final sysPorts = SerialPort.availablePorts;
      ports.addAll(sysPorts);
      _log('사용 가능한 COM 포트: $ports', notify: !quiet);
    } catch (e, st) {
      _log('포트 조회 오류: $e', type: MessageType.error, notify: !quiet);
      _lastErrorDetails = '$e\n$st';
    }
    return ports;
  }

  // 추가: 칸지 모드 해제 헬퍼
  List<int> _fsCancelKanji() => [0x1C, 0x2E]; // FS .

// 추가: 코드페이지 전환 헬퍼
  List<int> _escSelectCodePage(int n) => [0x1B, 0x74, n]; // ESC t n

  // 1) EUC-KR만 고정
  Future<List<int>> _encodeKR(String text) async {
    try {
      return await CharsetConverter.encode('euc-kr', text);
    } catch (_) {
      // 폴백: 한글은 '?'로 대체
      final safe = text.replaceAll(RegExp(r'[^\x00-\x7F]'), '?');
      return latin1.encode(safe);
    }
  }

  // 2) CP437 인코딩 도우미 (블록문자/아스키아트용)
  Future<List<int>> _encodeCP437(String text) async {
    const candidates = ['cp437', 'ibm437', '437', 'windows-437', 'x-ibm437'];
    for (final name in candidates) {
      try { return await CharsetConverter.encode(name, text); } catch (_) {}
    }
    final safe = text.replaceAll(RegExp(r'[^\x00-\x7F]'), '?');
    return latin1.encode(safe);
  }


  static const List<int> _ESC_T_KOREAN = [0x1B, 0x74, 30]; // ESC t 30 (KSC-5601)
  List<int> _escAlign(int n) => [0x1B, 0x61, n]; // 0:left, 1:center, 2:right

  Future<void> _selectKoreanCodepage() async {
    await _sendRaw(_ESC_T_KOREAN, docName: 'SET_CODEPAGE_KR');
  }

  Future<void> _printAsciiArtCp437(String art) async {
    // 코드페이지 CP437로 전환 (ESC t 0)
    await _sendRaw([0x1B, 0x74, 0x00], docName: 'SET_CODEPAGE_CP437');

    // CP437로 인코딩해서 전송
    final bytes = await CharsetConverter.encode('cp437', art);
    await _sendRaw(bytes, docName: 'ASCII_ART_CP437');

    // 다시 한글 코드페이지(ESC t 30)로 복귀
    await _sendRaw([0x1B, 0x74, 30], docName: 'SET_CODEPAGE_KR');
  }

  // ===== 연결 =====
  Future<bool> connect() async {
    if (_isConnecting) {
      _showMessage('이미 연결을 시도하고 있습니다.', MessageType.warning);
      return false;
    }
    _isConnecting = true;
    _connectionStatus = '연결 중...';
    notifyListeners();

    try {
      await disconnect(); // 기존 연결 정리
      _statusKnown = false; // 새 연결 시작 시 상태 미확정
      _log('연결 시도: port=${_config.port}, baud=${_config.baudRate}, flow=${_config.flowControl}');

      // --- 분기: USB(스풀러) vs 직렬 ---
      if (_config.port == 'USB') {
        final all = WinSpoolRaw.enumPrinters();
        _log('[Spool] 설치 프린터: $all');

        _spoolPrinterName =
            WinSpoolRaw.findByHint(hint: 'RMP-8300') ??
                WinSpoolRaw.findByHint(hint: 'REXOD') ??
                WinSpoolRaw.findByHint(hint: 'POS');

        if (_spoolPrinterName == null) {
          throw Exception('스풀러에서 REXOD 프린터를 찾지 못했습니다. 프린터 이름에 "RMP-8300" 또는 "REXOD"가 포함되어야 합니다.');
        }
        _log('[Spool] 선택 프린터: $_spoolPrinterName');

        _spool = WinSpoolRaw();
        final okOpen = _spool!.open(_spoolPrinterName!);
        if (!okOpen) {
          throw Exception('스풀러 열기 실패: $_spoolPrinterName');
        }

        _useSpooler = true;
        _config = _config.copyWith(isConnected: true);
        _connectionStatus = 'USB(스풀러) 연결됨 ($_spoolPrinterName)';
        _showMessage('USB 프린터에 연결되었습니다.', MessageType.success);

        // USB는 상태 조회 불가 → 상태 미확정 유지
        _status = _status.copyWith(
          mechanicalType: 'RMP8300 (USB)',
          sdkVersion: 'WinSpool',
        );
        _statusKnown = false;
        notifyListeners();

        _isConnecting = false;
        notifyListeners();
        return true;
      } else {
        // ---- 직렬(COM) 경로 ----
        final portName = _config.port;
        if (!SerialPort.availablePorts.contains(portName)) {
          throw Exception('포트 $portName 을(를) 찾을 수 없습니다. 사용 가능: ${SerialPort.availablePorts.join(', ')}');
        }

        _port = SerialPort(portName);

        final cfg = SerialPortConfig()
          ..baudRate = _config.baudRate
          ..bits = 8
          ..stopBits = 1
          ..parity = SerialPortParity.none;

        switch (_config.flowControl) {
          case 0:
            cfg.setFlowControl(SerialPortFlowControl.none);
            break;
          case 1:
            cfg.setFlowControl(SerialPortFlowControl.xonXoff);
            break;
          case 2:
            cfg.setFlowControl(SerialPortFlowControl.rtsCts);
            break;
        }
        _port!.config = cfg;

        if (!_port!.openReadWrite()) {
          final error = SerialPort.lastError;
          throw Exception('포트 열기 실패: ${error?.message ?? "알 수 없는 오류"}');
        }
        if (!_port!.isOpen) {
          throw Exception('포트가 열리지 않았습니다.');
        }
        _log('[Serial] 포트 오픈: $portName');

        _reader = SerialPortReader(_port!);
        _readerSubscription = _reader!.stream.listen(
          _handleReceivedData,
          onError: (err) {
            _log('시리얼 읽기 오류: $err');
            _showMessage('데이터 읽기 오류: $err', MessageType.error);
          },
        );

        // 초기화 + 응답 확인
        await _sendCommand(_INIT);
        await _selectKoreanCodepage();
        await Future.delayed(const Duration(milliseconds: 200));
        final ok = await _checkPrinterResponse();
        if (!ok) {
          throw Exception('프린터가 응답하지 않습니다. 전원/케이블/포트를 확인하세요.');
        }

        _config = _config.copyWith(isConnected: true);
        _connectionStatus = '연결됨 ($portName)';
        _showMessage('프린터에 성공적으로 연결되었습니다.', MessageType.success);

        await _updatePrinterStatus(); // 기계타입/SDK 갱신
        _statusKnown = true;          // 직렬은 상태 응답됨

        _isConnecting = false;
        notifyListeners();
        return true;
      }
    } catch (e, st) {
      _log('연결 실패: $e\n$st');
      await _cleanup();
      _connectionStatus = '연결 실패';
      _showMessage('연결 오류: $e', MessageType.error, details: e.toString());
      _isConnecting = false;
      notifyListeners();
      return false;
    }
  }

  // ===== 스풀러 경로: 간단 자가 테스트 =====
  Future<bool> printRawSelfTest() async {
    final bytes = <int>[]
      ..addAll(_INIT)
      ..addAll('*** REXOD RAW TEST ***\n'.codeUnits)
      ..addAll('Hello, ESC/POS via ${_useSpooler ? "WinSpool" : "Serial"}\n'.codeUnits)
      ..addAll(_LINE_FEED)
      ..addAll(_LINE_FEED)
      ..addAll(_CUT_PARTIAL);
    final ok = await _sendRaw(bytes, docName: 'RAW-SELFTEST');
    _showMessage(ok ? 'RAW 테스트 전송 완료' : 'RAW 테스트 전송 실패', ok ? MessageType.success : MessageType.error);
    return ok;
  }

  // ===== 공통 헬퍼 =====
  Future<bool> _sendRaw(List<int> bytes, {String docName = 'ESC/POS RAW'}) async {
    final dump = _hexDump(bytes);
    if (_useSpooler) {
      if (!(_spool?.isOpen ?? false)) {
        _log('[Spool] Write 실패: 스풀러 미오픈');
        return false;
      }
      _log('[Spool]-> $docName (${bytes.length} bytes) : $dump');
      final ok = _spool!.writeRaw(bytes, docName: docName);
      _log('[Spool] result=$ok');
      return ok;
    } else {
      if (!(_port?.isOpen ?? false)) {
        _log('[Serial] Write 실패: 포트 미오픈');
        return false;
      }
      try {
        _log('[Serial]-> ${bytes.length} bytes : $dump');
        final data = Uint8List.fromList(bytes);
        final written = _port!.write(data);
        await Future.delayed(const Duration(milliseconds: 10));
        final ok = written == data.length;
        _log('[Serial] written=$written/${data.length}, ok=$ok');
        return ok;
      } catch (e) {
        _log('[Serial] write 예외: $e');
        return false;
      }
    }
  }

  Future<bool> _sendCommand(List<int> command) async {
    if (_useSpooler) {
      if (!(_spool?.isOpen ?? false)) {
        _showMessage('프린터가 연결되지 않았습니다.(USB)', MessageType.error);
        return false;
      }
    } else {
      if (!(_port?.isOpen ?? false)) {
        _showMessage('프린터가 연결되지 않았습니다.(COM)', MessageType.error);
        return false;
      }
    }
    return _sendRaw(command);
  }

  // ===== 시리얼 수신 처리(USB/스풀러는 사용 안 함) =====
  void _handleReceivedData(Uint8List data) {
    final dump = _hexDump(data);
    _log('[Serial]<- ${data.length} bytes : $dump');
    if (data.isNotEmpty) _parseStatusData(data);
  }

  void _parseStatusData(Uint8List data) {
    try {
      final b = data[0];
      _status = _status.copyWith(
        paperEmpty: (b & 0x04) != 0,
        headUp: (b & 0x08) != 0,
        cutError: (b & 0x10) != 0,
        nearEnd: (b & 0x02) != 0,
        prOutSensor: (b & 0x20) != 0,
      );
      _statusKnown = true; // ← 최초 수신 시 확정
      notifyListeners();
    } catch (e) {
      _log('상태 파싱 오류: $e');
    }
  }

  Future<bool> _checkPrinterResponse() async {
    if (_useSpooler) {
      return true;
    }
    try {
      await _sendCommand(_STATUS_REQUEST);
      final completer = Completer<bool>();
      final timer = Timer(const Duration(seconds: 2), () {
        if (!completer.isCompleted) completer.complete(false);
      });
      StreamSubscription? tmp;
      if (_reader != null) {
        tmp = _reader!.stream.listen((data) {
          if (data.isNotEmpty && !completer.isCompleted) completer.complete(true);
        });
      }
      final res = await completer.future;
      timer.cancel();
      await tmp?.cancel();
      return res;
    } catch (e) {
      _log('_checkPrinterResponse 예외: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    _log('연결 해제 요청');
    await _cleanup();
    _config = _config.copyWith(isConnected: false);
    _connectionStatus = '연결되지 않음';
    _statusKnown = false; // 해제 시 미확정
    _showMessage('프린터 연결이 해제되었습니다.', MessageType.info);
    notifyListeners();
  }

  Future<void> _cleanup() async {
    try {
      // 스풀러
      if (_spool != null) {
        _log('[Spool] close');
        _spool!.close();
        _spool = null;
      }
      _useSpooler = false;
      _spoolPrinterName = null;

      // 직렬
      await _readerSubscription?.cancel();
      _readerSubscription = null;
      _reader?.close();
      _reader = null;
      if (_port != null && _port!.isOpen) {
        _log('[Serial] close');
        _port!.close();
      }
      _port?.dispose();
      _port = null;
    } catch (e) {
      _log('정리 오류: $e');
    }
  }

  // ===== 인쇄 기능 =====
  Future<bool> _printTextInternal(String text, {int alignment = 0, int mode = 0}) async {
    // 한국어 페이지 보장(USB/직렬 공통)
    await _sendRaw([0x1B, 0x74, 30], docName: 'CODEPAGE_KR');

    final kr = await _encodeKR(text);

    if (_useSpooler) {
      final bytes = <int>[
        0x1B, 0x61, alignment, // 정렬
        0x1B, 0x21, mode, // 모드
        ...kr, // ✅ 인코딩된 바이트만 사용
        ..._LINE_FEED,
        0x1B, 0x21, 0x00, // 모드 초기화
        0x1B, 0x61, 0x00, // 정렬 초기화
      ];
      return _sendRaw(bytes, docName: 'TEXT-KR');
    } else {
      if (!await _sendCommand([0x1B, 0x61, alignment])) return false;
      if (!await _sendCommand([0x1B, 0x21, mode])) return false;
      if (!await _sendRaw(kr, docName: 'TEXT-KR')) return false; // ✅
      if (!await _sendCommand(_LINE_FEED)) return false;
      if (!await _sendCommand([0x1B, 0x21, 0x00])) return false;
      if (!await _sendCommand([0x1B, 0x61, 0x00])) return false;
      return true;
    }
  }

  Future<bool> printText(String text, {int alignment = 0, int mode = 0}) async {
    if (!(_useSpooler ? (_spool?.isOpen ?? false) : (_port?.isOpen ?? false))) {
      _showMessage('프린터가 연결되지 않았습니다.', MessageType.error);
      return false;
    }
    if (_isPrinting) {
      _showMessage('이미 인쇄 중입니다.', MessageType.warning);
      return false;
    }

    _isPrinting = true;
    _showMessage('텍스트를 인쇄하고 있습니다...', MessageType.info);
    notifyListeners();

    try {
      final ok = await _printTextInternal(text, alignment: alignment, mode: mode);
      _showMessage(ok ? '텍스트 인쇄 완료' : '텍스트 인쇄 실패',
          ok ? MessageType.success : MessageType.error);
      _isPrinting = false;
      notifyListeners();
      return ok;
    } catch (e) {
      _showMessage('텍스트 인쇄 실패: $e', MessageType.error);
      _isPrinting = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> printBarcode(String data) async {
    if (!(_useSpooler ? (_spool?.isOpen ?? false) : (_port?.isOpen ?? false))) {
      _showMessage('프린터가 연결되지 않았습니다.', MessageType.error);
      return false;
    }
    if (_isPrinting) {
      _showMessage('이미 인쇄 중입니다.', MessageType.warning);
      return false;
    }
    _isPrinting = true;
    _showMessage('바코드를 인쇄하고 있습니다...', MessageType.info);
    notifyListeners();

    try {
      final bytes = <int>[
        0x1D, 0x68, 0x64, // 높이
        0x1D, 0x77, 0x03, // 너비
        0x1D, 0x6B, 0x49, data.length, ...data.codeUnits,
        ..._LINE_FEED,
      ];
      final ok = await _sendRaw(bytes, docName: 'BARCODE');
      _showMessage(ok ? '바코드 인쇄 완료' : '바코드 인쇄 실패',
          ok ? MessageType.success : MessageType.error);
      _isPrinting = false;
      notifyListeners();
      return ok;
    } catch (e) {
      _showMessage('바코드 인쇄 실패: $e', MessageType.error);
      _isPrinting = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> printQRCode(String data,
      {int moduleSize = 6, int ecLevel = 0x31 /*0x30~0x33*/}) async {
    if (!(_useSpooler ? (_spool?.isOpen ?? false) : (_port?.isOpen ?? false))) {
      _showMessage('프린터가 연결되지 않았습니다.', MessageType.error);
      return false;
    }
    if (_isPrinting) {
      _showMessage('이미 인쇄 중입니다.', MessageType.warning);
      return false;
    }

    _isPrinting = true;
    _showMessage('QR코드를 인쇄하고 있습니다...', MessageType.info);
    notifyListeners();

    try {
      final size = moduleSize.clamp(3, 16);
      final ecc = ecLevel.clamp(0x30, 0x33);
      final bytesData = data.codeUnits;
      final len = bytesData.length + 3;
      final pL = len & 0xFF;
      final pH = (len >> 8) & 0xFF;

      final bytes = <int>[
        // 모델2
        0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00,
        // 모듈 사이즈
        0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, size,
        // 오류정정
        0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, ecc,
        // 데이터 저장
        0x1D, 0x28, 0x6B, pL, pH, 0x31, 0x50, 0x30, ...bytesData,
        // 인쇄
        0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30,
        ..._LINE_FEED,
      ];

      final ok = await _sendRaw(bytes, docName: 'QRCODE');
      _showMessage(ok ? 'QR코드 인쇄 완료' : 'QR코드 인쇄 실패',
          ok ? MessageType.success : MessageType.error);
      _isPrinting = false;
      notifyListeners();
      return ok;
    } catch (e) {
      _showMessage('QR코드 인쇄 실패: $e', MessageType.error);
      _isPrinting = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> printPDF417(String data) async {
    if (!(_useSpooler ? (_spool?.isOpen ?? false) : (_port?.isOpen ?? false))) {
      _showMessage('프린터가 연결되지 않았습니다.', MessageType.error);
      return false;
    }
    if (_isPrinting) {
      _showMessage('이미 인쇄 중입니다.', MessageType.warning);
      return false;
    }

    _isPrinting = true;
    _showMessage('PDF417을 인쇄하고 있습니다...', MessageType.info);
    notifyListeners();

    try {
      final bytesData = data.codeUnits;
      final len = bytesData.length + 3;
      final pL = len & 0xFF;
      final pH = (len >> 8) & 0xFF;

      final bytes = <int>[
        // 모듈/행 높이 (데모 값)
        0x1D, 0x28, 0x6B, 0x03, 0x00, 0x30, 0x50, 0x02,
        0x1D, 0x28, 0x6B, 0x03, 0x00, 0x30, 0x51, 0x03,
        // 데이터
        0x1D, 0x28, 0x6B, pL, pH, 0x30, 0x50, 0x30, ...bytesData,
        // 인쇄
        0x1D, 0x28, 0x6B, 0x03, 0x00, 0x30, 0x51, 0x30,
        ..._LINE_FEED,
      ];

      final ok = await _sendRaw(bytes, docName: 'PDF417');
      _showMessage(ok ? 'PDF417 인쇄 완료' : 'PDF417 인쇄 실패',
          ok ? MessageType.success : MessageType.error);
      _isPrinting = false;
      notifyListeners();
      return ok;
    } catch (e) {
      _showMessage('PDF417 인쇄 실패: $e', MessageType.error);
      _isPrinting = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> printSampleReceipt() async {
    if (!isConnected) {
      _showMessage('프린터가 연결되지 않았습니다.', MessageType.error);
      return false;
    }
    if (_isPrinting) {
      _showMessage('이미 인쇄 중입니다.', MessageType.warning);
      return false;
    }

    _isPrinting = true;
    _showMessage('샘플 영수증을 인쇄하고 있습니다...', MessageType.info);
    notifyListeners();

    try {
      final body = StringBuffer()
        ..writeln('************************************************')
        ..writeln('N I J I M O R I')
        ..writeln('STUDIO ENTRANCE TICKET')
        ..writeln('************************************************')
        ..writeln('- 티켓번호')
        ..writeln('  41bf144d-55e2-42df-b916-aebe94bad33f')
        ..writeln('- 구매자명 : 김호균')
        ..writeln('- 유효기간 : 2025-09-15 ~ 2026-09-14')
        ..writeln()
        ..writeln('------------------------------------------')
        ..writeln('[입장권 정보]')
        ..writeln('------------------------------------------');

      final asciiArt = StringBuffer()
        ..writeln('█▀▀▀▀▀▀▀██▀██▀█▀███▀▀▀▀▀▀▀█')
        ..writeln('█ █▀▀▀█ █▀▄▀▄█▄ ▄██ █▀▀▀█ █')
        ..writeln('█ █   █ █  ▄██▄▀▄▄█ █   █ █')
        ..writeln('█ ▀▀▀▀▀ █ ▄▀▄▀█▀▄ █ ▀▀▀▀▀ █')
        ..writeln('█▀█▀▀▀▀▀█▄ ▄  ▀█ ▄█▀▀▀▀▀███')
        ..writeln('█ ▄▄█▀ ▀  ▀▄▀ █▄▀▄▀▀ █▀▀▄▀█')
        ..writeln('█▄██▀▀▄▀ ▄▄█▄███ ▄█ ▀ ▀▀▄▀█')
        ..writeln('█ ▄▀▀ ▄▀▀▀▄▄█▄ ▀▀  ▀▀█▀█▀▀█')
        ..writeln('█ █ █  ▀▀  ▀█ ▄▀ ▀▀▀▀ ▀▀█▀█')
        ..writeln('█▀▀▀▀▀▀▀█▄█ ▀▀███ █▀█ ▀▀▄▀█')
        ..writeln('█ █▀▀▀█ █ ▀▀ ██▄  ▀▀▀ ▄▀▀ █')
        ..writeln('█ █   █ █ ▄▀█▄  ██▀▄▄▄▀█▄ █')
        ..writeln('█ ▀▀▀▀▀ █▀ ▀█ ▄▀▀▄█ ▄▄▄▀▀ █')
        ..writeln('▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀');

      final bodyKR   = await _encodeKR(body.toString());
      final art437   = await _encodeCP437(asciiArt.toString());

      final b = BytesBuilder();
      b.add(_INIT);

      b.add(_escSelectCodePage(30)); // EUC-KR (KSC-5601)
      b.add(bodyKR);

      // 아스키아트 구간만 CP437로 전환 후 출력
      b.add(_fsCancelKanji());       // FS .   ← 이게 진짜 중요해!
      b.add(_escSelectCodePage(0));  // ESC t 0 = PC437 (모델 따라 16일 수도)

      b.add(_escAlign(1)); // center
      b.add(art437);

      // 필요 시 다시 EUC-KR 복귀 (추가 텍스트가 없다면 생략 가능)
      b.add(_escAlign(0));
      b.add(_escSelectCodePage(30));

      b.add(_LINE_FEED);
      b.add(_LINE_FEED);
      b.add(_CUT_PARTIAL);

      final ok = await _sendRaw(b.toBytes(), docName: 'SAMPLE RECEIPT');
      _showMessage(ok ? '샘플 영수증 인쇄 완료' : '샘플 영수증 인쇄 실패',
          ok ? MessageType.success : MessageType.error);

      _isPrinting = false;
      notifyListeners();
      return ok;  } catch (e) {
      _showMessage('샘플 영수증 인쇄 실패: $e', MessageType.error);
      _isPrinting = false;
      notifyListeners();
      return false;
    }

  }

  Future<void> checkStatus() async {
    if (!(_useSpooler ? (_spool?.isOpen ?? false) : (_port?.isOpen ?? false))) {
      _showMessage('프린터가 연결되지 않았습니다.', MessageType.error);
      return;
    }
    if (_useSpooler) {
      _showMessage('USB(스풀러) 경로에서는 상태 조회를 지원하지 않습니다.', MessageType.info);
      return;
    }
    _showMessage('프린터 상태 확인 중...', MessageType.info);
    try {
      await _updatePrinterStatus();
      _statusKnown = true;
      if (_status.hasError) {
        _showMessage('프린터 오류: ${_status.errorMessages.join(', ')}', MessageType.error);
      } else if (_status.hasWarning) {
        _showMessage('프린터 경고: ${_status.warningMessages.join(', ')}', MessageType.warning);
      } else {
        _showMessage('프린터 상태 정상', MessageType.success);
      }
    } catch (e) {
      _showMessage('상태 확인 실패: $e', MessageType.error);
    }
  }

  Future<void> _updatePrinterStatus() async {
    if (_useSpooler) return; // 스풀러 경로는 스킵
    try {
      if (!await _sendCommand(_STATUS_REQUEST)) {
        throw Exception('상태 요청 전송 실패');
      }
      await Future.delayed(const Duration(milliseconds: 200));
      // 데모 표기값
      _status = _status.copyWith(
        mechanicalType: 'RMP8300',
        sdkVersion: 'v2.1.0',
      );
      _log('상태 업데이트: mech=${_status.mechanicalType}, sdk=${_status.sdkVersion}');
      notifyListeners();
    } catch (e) {
      _log('상태 업데이트 오류: $e');
    }
  }

  Future<bool> rebootPrinter() async {
    if (!(_useSpooler ? (_spool?.isOpen ?? false) : (_port?.isOpen ?? false))) {
      _showMessage('프린터가 연결되지 않았습니다.', MessageType.error);
      return false;
    }
    _showMessage('프린터 재부팅 중...', MessageType.info);
    try {
      // 제조사별 명령 상이. 여긴 데모.
      final ok = await _sendRaw([0x1B, 0x3F, 0x0A, 0x00], docName: 'REBOOT');
      await Future.delayed(const Duration(seconds: 2));
      await disconnect();
      _showMessage(ok ? '프린터 재부팅 완료. 다시 연결하세요.' : '재부팅 명령 실패', ok ? MessageType.success : MessageType.error);
      return ok;
    } catch (e) {
      _showMessage('재부팅 실패: $e', MessageType.error);
      return false;
    }
  }

  // ===== 설정 =====
  void updateConfig(PrinterConfig newConfig) {
    _log('설정 변경: port=${newConfig.port}, baud=${newConfig.baudRate}, flow=${newConfig.flowControl}');
    _config = newConfig;
    notifyListeners();
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
}
