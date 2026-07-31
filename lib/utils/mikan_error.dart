import 'package:dio/dio.dart';

String mikanErrorMessage(Object error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) {
      return 'Mikan 登录状态已失效或没有操作权限，请重新登录';
    }
    if (status == 404) return '没有找到对应的 Mikan 页面或资源';
    if (status == 429) return 'Mikan 请求过于频繁，请稍后再试';
    if (status != null && status >= 500) {
      return 'Mikan 服务暂时不可用（$status），请稍后重试或切换站点';
    }
    if (status != null) return 'Mikan 请求失败（$status）';

    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => '连接 Mikan 超时，请重试或切换站点',
      DioExceptionType.connectionError => '无法连接 Mikan，请检查网络或切换站点',
      DioExceptionType.badCertificate => 'Mikan 站点证书验证失败',
      DioExceptionType.cancel => 'Mikan 请求已取消',
      _ => 'Mikan 网络请求失败，请稍后重试',
    };
  }
  if (error is FormatException) {
    return 'Mikan 返回的数据格式发生变化，请稍后再试';
  }
  final message = error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
  return message.isEmpty ? 'Mikan 操作失败，请稍后重试' : message;
}
