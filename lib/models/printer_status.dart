class PrinterStatus {
  bool paperEmpty;
  bool headUp;
  bool cutError;
  bool nearEnd;
  bool prOutSensor;
  String mechanicalType;
  String presenterType;
  String sdkVersion;

  PrinterStatus({
    this.paperEmpty = false,
    this.headUp = false,
    this.cutError = false,
    this.nearEnd = false,
    this.prOutSensor = false,
    this.mechanicalType = 'Unknown',
    this.presenterType = 'Unknown',
    this.sdkVersion = 'Unknown',
  });

  PrinterStatus copyWith({
    bool? paperEmpty,
    bool? headUp,
    bool? cutError,
    bool? nearEnd,
    bool? prOutSensor,
    String? mechanicalType,
    String? presenterType,
    String? sdkVersion,
  }) {
    return PrinterStatus(
      paperEmpty: paperEmpty ?? this.paperEmpty,
      headUp: headUp ?? this.headUp,
      cutError: cutError ?? this.cutError,
      nearEnd: nearEnd ?? this.nearEnd,
      prOutSensor: prOutSensor ?? this.prOutSensor,
      mechanicalType: mechanicalType ?? this.mechanicalType,
      presenterType: presenterType ?? this.presenterType,
      sdkVersion: sdkVersion ?? this.sdkVersion,
    );
  }

  bool get hasError {
    return paperEmpty || headUp || cutError || prOutSensor;
  }

  bool get hasWarning {
    return nearEnd;
  }

  List<String> get errorMessages {
    List<String> messages = [];
    if (paperEmpty) messages.add('용지 부족');
    if (headUp) messages.add('헤드 업');
    if (cutError) messages.add('절단 오류');
    if (prOutSensor) messages.add('센서 오류');
    return messages;
  }

  List<String> get warningMessages {
    List<String> messages = [];
    if (nearEnd) messages.add('용지 부족 경고');
    return messages;
  }
}

