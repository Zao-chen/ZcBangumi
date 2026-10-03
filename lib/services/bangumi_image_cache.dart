import 'package:dio/dio.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'bangumi_endpoint_service.dart';
import 'network_proxy_config.dart';
import 'web_network_config.dart';

class BangumiImageCache {
  BangumiImageCache(
    BangumiEndpointService endpoints, {
    BaseCacheManager? legacyCache,
  }) : _files = _BangumiImageFileService(endpoints) {
    manager = _BangumiCacheManager(
      Config('bangumi_images_v1', fileService: _files),
      legacyCache ?? DefaultCacheManager(),
    );
  }

  final _BangumiImageFileService _files;
  late final CacheManager manager;

  Future<void> dispose() async {
    NetworkProxyConfig.uninstallDio(_files.dio);
    _files.dio.close(force: true);
    await manager.dispose();
  }
}

class _BangumiCacheManager extends CacheManager with ImageCacheManager {
  _BangumiCacheManager(super.config, this.legacyCache);

  final BaseCacheManager legacyCache;

  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async =>
      await super.getFileFromCache(key, ignoreMemCache: ignoreMemCache) ??
      await legacyCache.getFileFromCache(key, ignoreMemCache: ignoreMemCache);

  @override
  Future<FileInfo?> getFileFromMemory(String key) async =>
      await super.getFileFromMemory(key) ??
      await legacyCache.getFileFromMemory(key);
}

class _BangumiImageFileService extends FileService {
  _BangumiImageFileService(this.endpoints) {
    dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        responseType: ResponseType.bytes,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 400,
      ),
    );
    NetworkProxyConfig.installDio(dio);
    WebNetworkConfig.installWebAdapter(dio);
    endpoints.install(dio);
  }

  final BangumiEndpointService endpoints;
  final HttpFileService _external = HttpFileService();
  late final Dio dio;

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    if (endpoints.kindForUri(Uri.parse(url)) == null) {
      return _external.get(url, headers: headers);
    }
    final response = await dio.get<List<int>>(
      url,
      options: Options(headers: headers),
    );
    if (response.statusCode != 304 &&
        response.headers.value('content-type')?.startsWith('image/') != true) {
      throw const FormatException('镜像返回的内容不是图片，请检查连接或手动验证');
    }
    return _BangumiImageResponse(response);
  }
}

class _BangumiImageResponse implements FileServiceResponse {
  _BangumiImageResponse(this.response);

  final Response<List<int>> response;

  @override
  Stream<List<int>> get content => Stream.value(response.data ?? const []);
  @override
  int? get contentLength => response.data?.length;
  @override
  int get statusCode => response.statusCode ?? 0;
  @override
  DateTime get validTill {
    final cacheControl = response.headers.value('cache-control') ?? '';
    final maxAge = RegExp(r'max-age=(\d+)').firstMatch(cacheControl)?.group(1);
    final seconds =
        cacheControl.contains('no-cache') || cacheControl.contains('no-store')
        ? 0
        : int.tryParse(maxAge ?? '') ?? 604800;
    return DateTime.now().add(Duration(seconds: seconds));
  }

  @override
  String? get eTag => response.headers.value('etag');
  @override
  String get fileExtension =>
      switch (response.headers.value('content-type')?.split(';').first) {
        'image/jpeg' => 'jpg',
        'image/png' => 'png',
        'image/gif' => 'gif',
        'image/webp' => 'webp',
        _ => 'img',
      };
}
