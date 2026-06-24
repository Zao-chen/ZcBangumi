import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class AppLogService extends ChangeNotifier {
  AppLogService({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const int maxLogBytes = 1024 * 1024;

  final DateTime Function() _now;
  File? _logFile;
  Future<void> _writeQueue = Future.value();

  Future<void> init() async {
    await _prepareLogFile();
    await info('app', '日志服务已启动');
  }

  Future<void> _prepareLogFile() async {
    if (_logFile != null) return;
    final dir = await getApplicationSupportDirectory();
    final logDir = Directory('${dir.path}${Platform.pathSeparator}logs');
    if (!await logDir.exists()) {
      await logDir.create(recursive: true);
    }
    _logFile = File('${logDir.path}${Platform.pathSeparator}zc_bangumi.log');
    if (!await _logFile!.exists()) {
      await _logFile!.create(recursive: true);
    }
    await _trimIfNeeded();
  }

  Future<File> exportLogFile() async {
    final source = await _ensureLogFile();
    final exportDir = await getTemporaryDirectory();
    final stamp = _formatFileStamp(_now());
    final target = File(
      '${exportDir.path}${Platform.pathSeparator}zc_bangumi_log_$stamp.txt',
    );
    return source.copy(target.path);
  }

  Future<List<AppLogEntry>> readEntries({int limit = 300}) async {
    final file = await _ensureLogFile();
    final lines = await file.readAsLines();
    return lines.reversed
        .map(AppLogEntry.tryParse)
        .whereType<AppLogEntry>()
        .take(limit)
        .toList(growable: false);
  }

  Future<String> readText() async {
    final file = await _ensureLogFile();
    return file.readAsString();
  }

  Future<void> clear() async {
    final file = await _ensureLogFile();
    await file.writeAsString('');
    notifyListeners();
  }

  Future<void> info(String category, String message) {
    return _write('INFO', category, message);
  }

  Future<void> warning(String category, String message) {
    return _write('WARN', category, message);
  }

  Future<void> error(String category, String message) {
    return _write('ERROR', category, message);
  }

  Future<File> _ensureLogFile() async {
    await _prepareLogFile();
    return _logFile!;
  }

  Future<void> _write(String level, String category, String message) {
    final line =
        '${_now().toIso8601String()} [$level] ${_sanitize(category)} ${_sanitize(message)}\n';
    _writeQueue = _writeQueue.then((_) async {
      final file = await _ensureLogFile();
      await _trimIfNeeded();
      await file.writeAsString(line, mode: FileMode.append, flush: true);
      notifyListeners();
    });
    return _writeQueue;
  }

  Future<void> _trimIfNeeded() async {
    final file = _logFile;
    if (file == null) return;
    if (!await file.exists()) return;
    final length = await file.length();
    if (length <= maxLogBytes) return;

    final lines = await file.readAsLines();
    final kept = lines.length > 1000
        ? lines.sublist(lines.length - 1000)
        : lines;
    await file.writeAsString('${kept.join('\n')}\n');
  }

  String _formatFileStamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}${two(time.month)}${two(time.day)}_'
        '${two(time.hour)}${two(time.minute)}${two(time.second)}';
  }

  String _sanitize(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class AppLogEntry {
  final DateTime time;
  final String level;
  final String category;
  final String message;

  const AppLogEntry({
    required this.time,
    required this.level,
    required this.category,
    required this.message,
  });

  static final RegExp _linePattern = RegExp(
    r'^(\S+) \[(INFO|WARN|ERROR)\] ([^ ]+) ?(.*)$',
  );

  static AppLogEntry? tryParse(String line) {
    final match = _linePattern.firstMatch(line);
    if (match == null) return null;
    final time = DateTime.tryParse(match.group(1)!);
    if (time == null) return null;
    return AppLogEntry(
      time: time,
      level: match.group(2)!,
      category: match.group(3)!,
      message: match.group(4) ?? '',
    );
  }
}

class AppLogDioInterceptor extends Interceptor {
  AppLogDioInterceptor(this.logService);

  final AppLogService logService;
  final Map<int, DateTime> _startedAt = {};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _startedAt[options.hashCode] = DateTime.now();
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final statusCode = response.statusCode ?? 0;
    if (statusCode >= 400) {
      unawaited(
        logService.warning(
          'network',
          '${response.requestOptions.method} ${_safeUri(response.requestOptions)} -> $statusCode ${_elapsed(response.requestOptions)}',
        ),
      );
    }
    _startedAt.remove(response.requestOptions.hashCode);
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    unawaited(
      logService.error(
        'network',
        '${err.requestOptions.method} ${_safeUri(err.requestOptions)} -> ${err.response?.statusCode ?? err.type.name} ${_elapsed(err.requestOptions)} ${err.message ?? ''}',
      ),
    );
    _startedAt.remove(err.requestOptions.hashCode);
    super.onError(err, handler);
  }

  String _elapsed(RequestOptions options) {
    final started = _startedAt[options.hashCode];
    if (started == null) return '';
    final elapsed = DateTime.now().difference(started).inMilliseconds;
    return '${elapsed}ms';
  }

  String _safeUri(RequestOptions options) {
    final uri = options.uri;
    final queryKeys = uri.queryParameters.keys.toList()..sort();
    final query = queryKeys.isEmpty ? '' : '?${queryKeys.join('&')}';
    return '${uri.scheme}://${uri.host}${uri.path}$query';
  }
}
