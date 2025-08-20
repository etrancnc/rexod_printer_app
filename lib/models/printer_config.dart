class PrinterConfig {
  String port;
  int baudRate;
  int flowControl; // 0: None, 1: Xon/Xoff, 2: Hardware
  bool isConnected;

  PrinterConfig({
    this.port = 'USB',
    this.baudRate = 115200,
    this.flowControl = 2,
    this.isConnected = false,
  });

  PrinterConfig copyWith({
    String? port,
    int? baudRate,
    int? flowControl,
    bool? isConnected,
  }) {
    return PrinterConfig(
      port: port ?? this.port,
      baudRate: baudRate ?? this.baudRate,
      flowControl: flowControl ?? this.flowControl,
      isConnected: isConnected ?? this.isConnected,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'port': port,
      'baudRate': baudRate,
      'flowControl': flowControl,
      'isConnected': isConnected,
    };
  }

  factory PrinterConfig.fromJson(Map<String, dynamic> json) {
    return PrinterConfig(
      port: json['port'] ?? 'USB',
      baudRate: json['baudRate'] ?? 115200,
      flowControl: json['flowControl'] ?? 2,
      isConnected: json['isConnected'] ?? false,
    );
  }

  String get flowControlName {
    switch (flowControl) {
      case 0:
        return 'None';
      case 1:
        return 'Xon/Xoff';
      case 2:
        return 'Hardware';
      default:
        return 'Unknown';
    }
  }
}

