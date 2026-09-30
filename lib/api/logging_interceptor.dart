import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flashshare/logs/log_store.dart';

/// Logs every HTTP call the app makes — request, response, and failure — into
/// the in-app [LogStore], so the log screen is a complete picture of a session
/// rather than just the errors that reached a widget.
///
/// Secrets never reach the log: presigned R2 URLs (which carry signatures in
/// their query string) are reduced to their path, and credential headers plus
/// password bodies are redacted.
class LogStoreInterceptor extends Interceptor {
  LogStoreInterceptor({this.source = 'api'});

  /// Where the request started, so onError can report a duration too.
  static const _kStart = 'logStartMs';

  final String source;

  /// Headers are never logged at all — the ones that matter here
  /// (Authorization, X-Owner-Token, X-Visitor-Token, Cookie) are credentials,
  /// and "log the whole request" is how tokens end up in a copied bug report.

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_kStart] = DateTime.now().millisecondsSinceEpoch;
    AppLog.debug(
      '→ ${options.method} ${_safeUri(options.uri.toString())}',
      source: source,
    );
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final o = response.requestOptions;
    AppLog.info(
      '← ${response.statusCode} ${o.method} ${_safeUri(o.uri.toString())} '
      '${_elapsedMs(o)}',
      source: source,
    );
    // 2xx that still says "error" in the body is a server-side bug worth a
    // warning line — the client-side caller would otherwise swallow it.
    final body = response.data;
    if (body is Map && body['error'] != null) {
      AppLog.warning(
        'API returned error payload for ${o.path}: ${body['error']}',
        source: source,
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final o = err.requestOptions;
    final target = '${o.method} ${_safeUri(o.uri.toString())}';
    if (err.type == DioExceptionType.cancel) {
      AppLog.debug('↩ cancelled $target', source: source);
    } else {
      final status = err.response?.statusCode;
      AppLog.error(
        '✕ ${status == null ? err.type.name : status} $target '
        '${_elapsedMs(o)} — ${_redactBody(err.response?.data ?? err.message)}',
        stack: err.stackTrace,
        source: source,
      );
    }
    handler.next(err);
  }

  String _elapsedMs(RequestOptions o) {
    final start = o.extra[_kStart];
    if (start is! int) return '';
    return '(${DateTime.now().millisecondsSinceEpoch - start}ms)';
  }

  /// Drop the query string: presigned R2 URLs embed credentials in it.
  String _safeUri(String uri) {
    final q = uri.indexOf('?');
    return q == -1 ? uri : '${uri.substring(0, q)}?<signed>';
  }

  /// Body preview with credential-ish keys stripped, truncated so a large
  /// error page doesn't bloat the log ring.
  String _redactBody(Object? data) {
    if (data == null) return 'no body';
    String raw;
    if (data is Map || data is List) {
      raw = jsonEncode(_redactMap(data));
    } else {
      raw = data.toString();
    }
    final clipped = raw.length > 300 ? '${raw.substring(0, 300)}…' : raw;
    return clipped.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Object? _redactMap(Object? value) {
    if (value is Map) {
      return <String, Object?>{
        for (final e in value.entries)
          e.key.toString(): _sensitive(e.key.toString())
              ? '[redacted]'
              : _redactMap(e.value),
      };
    }
    if (value is List) return value.map(_redactMap).toList();
    return value;
  }

  bool _sensitive(String key) {
    final k = key.toLowerCase();
    return k.contains('token') ||
        k.contains('password') ||
        k.contains('secret') ||
        k.contains('key');
  }
}
