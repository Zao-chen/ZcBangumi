enum NetworkProxyMode { direct, system, manual }

class NetworkProxySettings {
  final NetworkProxyMode mode;
  final String host;
  final int? port;

  const NetworkProxySettings({
    this.mode = NetworkProxyMode.direct,
    this.host = '',
    this.port,
  });

  const NetworkProxySettings.direct()
    : mode = NetworkProxyMode.direct,
      host = '',
      port = null;

  bool get isManual => mode == NetworkProxyMode.manual;

  bool get isManualValid {
    final value = port;
    return host.trim().isNotEmpty &&
        value != null &&
        value > 0 &&
        value < 65536;
  }

  String get displayText {
    switch (mode) {
      case NetworkProxyMode.direct:
        return '直连';
      case NetworkProxyMode.system:
        return '系统环境代理';
      case NetworkProxyMode.manual:
        return isManualValid ? '${host.trim()}:$port' : '手动代理未配置';
    }
  }

  NetworkProxySettings copyWith({
    NetworkProxyMode? mode,
    String? host,
    int? port,
    bool clearPort = false,
  }) {
    return NetworkProxySettings(
      mode: mode ?? this.mode,
      host: host ?? this.host,
      port: clearPort ? null : port ?? this.port,
    );
  }

  Map<String, dynamic> toJson() {
    return {'mode': mode.name, 'host': host.trim(), 'port': port};
  }

  factory NetworkProxySettings.fromJson(Map<String, dynamic> json) {
    final modeName = '${json['mode'] ?? ''}';
    final mode = NetworkProxyMode.values.firstWhere(
      (item) => item.name == modeName,
      orElse: () => NetworkProxyMode.direct,
    );
    final rawPort = json['port'];
    return NetworkProxySettings(
      mode: mode,
      host: _normalizeHost('${json['host'] ?? ''}'),
      port: rawPort is num ? rawPort.toInt() : int.tryParse('$rawPort'),
    ).normalized();
  }

  NetworkProxySettings normalized() {
    if (mode != NetworkProxyMode.manual) {
      return NetworkProxySettings(mode: mode);
    }
    return NetworkProxySettings(
      mode: mode,
      host: _normalizeHost(host),
      port: port,
    );
  }

  static String _normalizeHost(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    final withScheme = Uri.tryParse(trimmed);
    if (withScheme != null && withScheme.hasScheme) {
      return withScheme.host;
    }
    final withoutPath = trimmed.split('/').first;
    if (withoutPath.startsWith('[')) {
      final end = withoutPath.indexOf(']');
      if (end > 0) return withoutPath.substring(1, end);
    }
    return withoutPath.split(':').first.trim();
  }

  @override
  bool operator ==(Object other) {
    return other is NetworkProxySettings &&
        other.mode == mode &&
        other.host == host &&
        other.port == port;
  }

  @override
  int get hashCode => Object.hash(mode, host, port);
}
