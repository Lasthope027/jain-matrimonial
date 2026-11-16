import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jain_admin/auth_client.dart';
import 'package:jain_admin/login_screen.dart';

http.Response tokens(String suffix) => http.Response(
    jsonEncode({
      'access_token': 'access-$suffix',
      'refresh_token': 'refresh-$suffix',
      'token_type': 'bearer',
      'expires_in': 900,
    }),
    200);

void main() {
  testWidgets('Customer can request, verify, and revoke a session',
      (tester) async {
    final paths = <String>[];
    final client =
        AuthClient('http://127.0.0.1', transport: MockClient((request) async {
      paths.add(request.url.path);
      switch (request.url.path) {
        case '/api/v1/auth/otp/request':
          return http.Response(
              '{"resend_after":60,"development_otp":"123456"}', 202);
        case '/api/v1/auth/otp/verify':
          expect(jsonDecode(request.body)['code'], '123456');
          return tokens('one');
        case '/api/v1/customer/session':
          expect(request.headers['Authorization'], 'Bearer access-one');
          return http.Response(
              '{"email":"family@example.test","role":"CUSTOMER"}', 200);
        case '/api/v1/auth/logout':
          expect(jsonDecode(request.body)['refresh_token'], 'refresh-one');
          return http.Response('', 204);
        default:
          return http.Response('{}', 404);
      }
    }));
    await tester.pumpWidget(MaterialApp(home: LoginScreen(client: client)));
    await tester.enterText(
        find.byType(TextFormField).first, 'family@example.test');
    await tester.tap(find.text('Send sign-in code'));
    await tester.pumpAndSettle();
    final resend = find.byWidgetPredicate(
        (widget) => widget is TextButton && widget.onPressed == null);
    expect(resend, findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(1), '123456');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(
        find.text('You are signed in. Your account is ready.'), findsOneWidget);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Send sign-in code'), findsOneWidget);
    expect(paths.last, '/api/v1/auth/logout');
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets('Administrator screen submits password to the separate login',
      (tester) async {
    final client = AuthClient('http://127.0.0.1', administrator: true,
        transport: MockClient((request) async {
      if (request.url.path == '/api/v1/auth/admin/login') {
        final body = jsonDecode(request.body);
        expect(body['password'], 'a-long-password');
        expect(body.containsKey('code'), isFalse);
        return tokens('admin');
      }
      expect(request.url.path, '/api/v1/admin/session');
      return http.Response(
          '{"email":"admin@example.test","role":"ADMINISTRATOR"}', 200);
    }));
    await tester.pumpWidget(MaterialApp(home: LoginScreen(client: client)));
    expect(find.text('Send sign-in code'), findsNothing);
    final password = tester.widget<TextField>(find.descendant(
        of: find.byType(TextFormField).at(1),
        matching: find.byType(TextField)));
    expect(password.obscureText, isTrue);
    await tester.enterText(
        find.byType(TextFormField).first, 'admin@example.test');
    await tester.enterText(find.byType(TextFormField).at(1), 'a-long-password');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Administrator account'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets(
      'Failed credentials keep sign-in available and display safe feedback',
      (tester) async {
    final client = AuthClient('http://127.0.0.1',
        administrator: true,
        transport: MockClient((_) async =>
            http.Response('{"detail":"Invalid login credentials"}', 401)));
    await tester.pumpWidget(MaterialApp(home: LoginScreen(client: client)));
    await tester.enterText(
        find.byType(TextFormField).first, 'admin@example.test');
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Invalid login credentials'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  test(
      'Expired access rotates the refresh token; logout uses the rotated credential',
      () async {
    var expire = false;
    var refreshes = 0;
    final client =
        AuthClient('http://127.0.0.1', transport: MockClient((request) async {
      if (request.url.path.endsWith('/otp/verify')) return tokens('one');
      if (request.url.path.endsWith('/refresh')) {
        refreshes++;
        expect(jsonDecode(request.body)['refresh_token'], 'refresh-one');
        return tokens('two');
      }
      if (request.url.path.endsWith('/logout')) {
        expect(jsonDecode(request.body)['refresh_token'], 'refresh-two');
        return http.Response('', 204);
      }
      if (expire && request.headers['Authorization'] == 'Bearer access-one') {
        return http.Response('{"detail":"Authentication required"}', 401);
      }
      return http.Response(
          '{"email":"family@example.test","role":"CUSTOMER"}', 200);
    }));
    await client.signIn('family@example.test', '123456');
    expire = true;
    expect((await client.account())['role'], 'CUSTOMER');
    expect(refreshes, 1);
    await client.signOut();
    await expectLater(client.account(), throwsA(isA<AuthException>()));
    client.close();
  });

  test('Wrong application role rejects login and revokes the issued session',
      () async {
    var revoked = false;
    final client = AuthClient('http://127.0.0.1', administrator: true,
        transport: MockClient((request) async {
      if (request.url.path.endsWith('/login')) return tokens('wrong');
      if (request.url.path.endsWith('/logout')) {
        revoked = true;
        return http.Response('', 204);
      }
      return http.Response('{"detail":"Access denied"}', 403);
    }));
    await expectLater(client.signIn('family@example.test', 'password'),
        throwsA(isA<AuthException>()));
    expect(revoked, isTrue);
    await expectLater(client.account(), throwsA(isA<AuthException>()));
    client.close();
  });
}
