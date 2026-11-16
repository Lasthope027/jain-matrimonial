import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jain_admin/main.dart';

void main() {
  testWidgets('Pending request disables retries and reports readiness',
      (tester) async {
    final pending = Completer<http.Response>();
    final client = MockClient((request) {
      expect(request.url.path, '/api/v1/ready');
      return pending.future;
    });
    await tester
        .pumpWidget(MaterialApp(home: ConnectionScreen(client: client)));
    await tester.tap(find.text('Check connection'));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    pending.complete(http.Response('{"status":"ready"}', 200));
    await tester.pumpAndSettle();
    expect(find.text('Connected to the consultancy.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    client.close();
  });
  testWidgets('Unavailable service allows retry', (tester) async {
    final client = MockClient((_) async => http.Response('{}', 503));
    await tester
        .pumpWidget(MaterialApp(home: ConnectionScreen(client: client)));
    await tester.tap(find.text('Check connection'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'The consultancy service is not ready. Please try again later.'),
        findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    client.close();
  });
}
