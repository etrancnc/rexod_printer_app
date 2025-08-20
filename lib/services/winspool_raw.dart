// lib/services/winspool_raw.dart
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Windows 스풀러(WritePrinter, RAW)로 ESC/POS 바이트를 보내는 간단 유틸
class WinSpoolRaw {
  int? _hPrinter; // HANDLE(IntPtr)
  bool get isOpen => _hPrinter != null && _hPrinter! != 0;

  /// 프린터 열기 (표시 이름)
  bool open(String printerName) {
    final pName = TEXT(printerName);
    final phPrinter = calloc<IntPtr>();
    final ok = OpenPrinter(pName, phPrinter, nullptr) != 0;
    calloc.free(pName);

    if (ok) {
      _hPrinter = phPrinter.value;
    }
    calloc.free(phPrinter);
    return ok;
  }

  /// 닫기
  void close() {
    if (isOpen) {
      ClosePrinter(_hPrinter!);
      _hPrinter = null;
    }
  }

  /// RAW 바이트 쓰기
  bool writeRaw(List<int> bytes, {String docName = 'RAW ESC/POS'}) {
    if (!isOpen) return false;

    final pDocName = TEXT(docName);
    final pDataType = TEXT('RAW');

    final info = calloc<DOC_INFO_1>()
      ..ref.pDocName = pDocName
      ..ref.pOutputFile = nullptr
      ..ref.pDatatype = pDataType;

    final started = StartDocPrinter(_hPrinter!, 1, info.cast()) != 0;
    if (!started) {
      calloc.free(info);
      calloc.free(pDocName);
      calloc.free(pDataType);
      return false;
    }

    StartPagePrinter(_hPrinter!);

    final pData = calloc<Uint8>(bytes.length);
    for (var i = 0; i < bytes.length; i++) {
      pData[i] = bytes[i];
    }
    final pcbWritten = calloc<Uint32>();
    final ok =
        WritePrinter(_hPrinter!, pData.cast(), bytes.length, pcbWritten) != 0;

    EndPagePrinter(_hPrinter!);
    EndDocPrinter(_hPrinter!);

    calloc.free(pcbWritten);
    calloc.free(pData);
    calloc.free(info);
    calloc.free(pDocName);
    calloc.free(pDataType);

    return ok;
  }

  /// 로컬/연결된 프린터 이름 나열
  static List<String> enumPrinters() {
    final flags = PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS;
    final pcbNeeded = calloc<Uint32>();
    final pcReturned = calloc<Uint32>();

    // 1st call: required size
    EnumPrinters(flags, nullptr, 2, nullptr, 0, pcbNeeded, pcReturned);
    final size = pcbNeeded.value;
    if (size == 0) {
      calloc.free(pcbNeeded);
      calloc.free(pcReturned);
      return [];
    }

    // 2nd call: actual data
    final buffer = calloc<Uint8>(size);
    final ok = EnumPrinters(flags, nullptr, 2, buffer, size, pcbNeeded, pcReturned) != 0;

    final result = <String>[];
    if (ok) {
      final count = pcReturned.value;
      final infos = buffer.cast<PRINTER_INFO_2>();
      for (var i = 0; i < count; i++) {
        final name = infos.elementAt(i).ref.pPrinterName.toDartString();
        result.add(name);
      }
    }

    calloc.free(buffer);
    calloc.free(pcbNeeded);
    calloc.free(pcReturned);
    return result;
  }

  /// 표시 이름에 힌트 문자열이 들어가는 프린터 검색
  static String? findByHint({String hint = 'REXOD'}) {
    final h = hint.toLowerCase();
    for (final n in enumPrinters()) {
      if (n.toLowerCase().contains(h)) return n;
    }
    return null;
  }
}
