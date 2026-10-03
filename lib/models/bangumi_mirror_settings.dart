import 'dart:convert';

enum BangumiServiceKind {
  web('网页', 'https://bgm.tv'),
  api('公开 API', 'https://api.bgm.tv'),
  next('next API', 'https://next.bgm.tv'),
  lain('lain 图片', 'https://lain.bgm.tv'),
  fast('fast 图片', 'https://fast.bgm.tv');

  const BangumiServiceKind(this.label, this.officialBaseUrl);

  final String label;
  final String officialBaseUrl;
}

enum BangumiMirrorSource { official, bangumiVip, custom }

class BangumiMirrorSettings {
  const BangumiMirrorSettings({
    this.source = BangumiMirrorSource.official,
    this.customWeb = '',
    this.customApi = '',
    this.customNext = '',
    this.customLain = '',
    this.customFast = '',
  });

  final BangumiMirrorSource source;
  final String customWeb;
  final String customApi;
  final String customNext;
  final String customLain;
  final String customFast;

  bool get isOfficial => source == BangumiMirrorSource.official;
  String get displayName => switch (source) {
    BangumiMirrorSource.official => '官方站',
    BangumiMirrorSource.bangumiVip => 'bangumi.vip',
    BangumiMirrorSource.custom => '自定义镜像',
  };

  Map<BangumiServiceKind, Uri> get endpoints {
    if (isOfficial) {
      return {
        for (final kind in BangumiServiceKind.values)
          kind: Uri.parse(kind.officialBaseUrl),
      };
    }
    if (source == BangumiMirrorSource.bangumiVip) {
      return generatedEndpoints('https://bangumi.vip');
    }
    final generated = generatedEndpoints(customWeb);
    final overrides = {
      BangumiServiceKind.api: customApi,
      BangumiServiceKind.next: customNext,
      BangumiServiceKind.lain: customLain,
      BangumiServiceKind.fast: customFast,
    };
    return {
      ...generated,
      for (final entry in overrides.entries)
        if (entry.value.trim().isNotEmpty)
          entry.key: normalizeBaseUrl(entry.value),
    };
  }

  String get fingerprint {
    final resolved = endpoints;
    return jsonEncode([
      for (final kind in BangumiServiceKind.values) resolved[kind]!.origin,
    ]);
  }

  static Uri normalizeBaseUrl(String input) {
    final raw = input.trim();
    if (raw.isEmpty) throw const FormatException('请填写镜像网页主域名');
    final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.port < 1 ||
        uri.port > 65535 ||
        uri.host.contains(RegExp(r'\s'))) {
      throw const FormatException('地址必须是 HTTPS 根地址，可含端口，不可含路径、账号或参数');
    }
    return Uri.parse(uri.origin);
  }

  static Map<BangumiServiceKind, Uri> generatedEndpoints(String input) {
    final web = normalizeBaseUrl(input);
    return {
      BangumiServiceKind.web: web,
      for (final kind in BangumiServiceKind.values)
        if (kind != BangumiServiceKind.web)
          kind: web.replace(host: '${kind.name}.${web.host}'),
    };
  }

  Map<String, dynamic> toJson() => {
    'source': source.name,
    'web': customWeb,
    'api': customApi,
    'next': customNext,
    'lain': customLain,
    'fast': customFast,
  };

  factory BangumiMirrorSettings.fromJson(Map<String, dynamic> json) {
    return BangumiMirrorSettings(
      source: BangumiMirrorSource.values.firstWhere(
        (source) => source.name == json['source'],
        orElse: () => BangumiMirrorSource.official,
      ),
      customWeb: json['web'] as String? ?? '',
      customApi: json['api'] as String? ?? '',
      customNext: json['next'] as String? ?? '',
      customLain: json['lain'] as String? ?? '',
      customFast: json['fast'] as String? ?? '',
    );
  }
}
