import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AuthClient {
  AuthClient(this.baseUrl, {this.administrator = false, http.Client? transport})
      : _transport = transport ?? http.Client();
  final String baseUrl;
  final bool administrator;
  final http.Client _transport;
  Map<String, dynamic>? _tokens;
  Future<void>? _refreshing;

  Future<Map<String, dynamic>> _decode(http.Response response) async {
    Map<String, dynamic> data;
    try {
      data = response.body.isEmpty
          ? {}
          : jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const AuthException(
          'The service returned an unreadable response. Please try again.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(data['detail'] is String
          ? data['detail'] as String
          : 'Please check your details and try again.');
    }
    return data;
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    try {
      return await _decode(await _transport
          .post(Uri.parse('$baseUrl/api/v1$path'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 20)));
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException('Unable to connect. Please try again.');
    }
  }

  Future<Map<String, dynamic>> requestCode(String email) =>
      _post('/auth/otp/request', {'email': email.trim()});

  Future<Map<String, dynamic>> signIn(String email, String credential) async {
    _tokens = await _post(
        administrator ? '/auth/admin/login' : '/auth/otp/verify', {
      'email': email.trim(),
      administrator ? 'password' : 'code': credential
    });
    try {
      return await account();
    } catch (_) {
      // A credential for the wrong application must not remain usable locally.
      try {
        await signOut();
      } catch (_) {/* Local credentials are still cleared. */}
      rethrow;
    }
  }

  Future<void> _refresh() async {
    final refresh = _tokens?['refresh_token'];
    if (refresh == null) throw const AuthException('Please sign in again.');
    try {
      _tokens = await _post('/auth/refresh', {'refresh_token': refresh});
    } catch (_) {
      _tokens = null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> account() async {
    if (_tokens == null) throw const AuthException('Please sign in again.');
    final path = administrator ? '/admin/session' : '/customer/session';
    try {
      var response = await _transport.get(Uri.parse('$baseUrl/api/v1$path'),
          headers: {
            'Authorization': 'Bearer ${_tokens!['access_token']}'
          }).timeout(const Duration(seconds: 10));
      if (response.statusCode == 401) {
        final pending = _refreshing ??= _refresh();
        try {
          await pending;
        } finally {
          if (identical(_refreshing, pending)) _refreshing = null;
        }
        response = await _transport.get(Uri.parse('$baseUrl/api/v1$path'),
            headers: {
              'Authorization': 'Bearer ${_tokens!['access_token']}'
            }).timeout(const Duration(seconds: 10));
      }
      return await _decode(response);
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException('Unable to connect. Please try again.');
    }
  }

  Future<http.Response> _authorized(String method, String path,
      {Map<String, dynamic>? body,
      Uint8List? bytes,
      String? contentType}) async {
    if (_tokens == null) throw const AuthException('Please sign in again.');
    Future<http.Response> send() async {
      final request = http.Request(method, Uri.parse('$baseUrl/api/v1$path'));
      request.headers['Authorization'] = 'Bearer ${_tokens!['access_token']}';
      if (bytes != null) {
        request.headers['Content-Type'] = contentType!;
        request.bodyBytes = bytes;
      } else if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final streamed =
          await _transport.send(request).timeout(const Duration(seconds: 30));
      return http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 30));
    }

    try {
      var response = await send();
      if (response.statusCode == 401) {
        final pending = _refreshing ??= _refresh();
        try {
          await pending;
        } finally {
          if (identical(_refreshing, pending)) _refreshing = null;
        }
        response = await send();
      }
      return response;
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException('Unable to connect. Please try again.');
    }
  }

  Future<Map<String, dynamic>> request(String method, String path,
          {Map<String, dynamic>? body}) async =>
      _decode(await _authorized(method, path, body: body));

  Future<Map<String, dynamic>> upload(String profileId, int version,
      String filename, String kind, Uint8List bytes) async {
    final extension = filename.split('.').last.toLowerCase();
    final media = {
      'pdf': 'application/pdf',
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg'
    }[extension];
    if (media == null || bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      throw const AuthException('Choose a PDF, JPEG or PNG up to 10 MiB.');
    }
    final query = Uri(queryParameters: {
      'version': '$version',
      'filename': filename,
      'kind': kind
    }).query;
    return _decode(await _authorized(
        'POST', '/profiles/$profileId/documents?$query',
        bytes: bytes, contentType: media));
  }

  Future<Uint8List> download(String documentId) async {
    final response =
        await _authorized('GET', '/documents/$documentId/download');
    if (response.statusCode != 200) await _decode(response);
    return response.bodyBytes;
  }

  Future<Uint8List> downloadShared(String proposalId, String documentId) async {
    final response = await _authorized(
        'GET', '/proposals/$proposalId/documents/$documentId/download');
    if (response.statusCode != 200) await _decode(response);
    return response.bodyBytes;
  }

  Future<void> signOut() async {
    final refresh = _tokens?['refresh_token'];
    try {
      if (refresh != null)
        await _post('/auth/logout', {'refresh_token': refresh});
    } finally {
      _tokens = null;
    }
  }

  void close() {
    _tokens = null;
    _transport.close();
  }
}
