import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jain_admin/auth_client.dart';
import 'package:jain_admin/admin_proposals.dart';
import 'package:jain_admin/admin_dashboard.dart';

Map<String, dynamic> profile(
        String id, String name, String email, int version) =>
    {
      'id': id,
      'full_name': name,
      'account_email': email,
      'status': 'APPROVED',
      'version': version,
      'snapshot_version': version
    };
final one = profile('profile-one', 'First Name', 'one@example.test', 3),
    two = profile('profile-two', 'Second Name', 'two@example.test', 5);
Map<String, dynamic> detail(
        {String status = 'PENDING', List<dynamic> grants = const []}) =>
    {
      'id': 'proposal-one',
      'version': 3,
      'status': status,
      'eligible': status != 'CANCELLED',
      'created_at': '2026-11-15T00:00:00Z',
      'closure_reason': null,
      'profiles': [one, two],
      'responses': [],
      'documents': [
        {
          'id': 'doc-one',
          'profile_id': 'profile-one',
          'original_name': 'one.pdf',
          'kind': 'BIODATA'
        },
        {
          'id': 'doc-two',
          'profile_id': 'profile-two',
          'original_name': 'two.pdf',
          'kind': 'BIODATA'
        }
      ],
      'sharing_records': grants
    };
http.Response response(Object data, [int status = 200]) =>
    http.Response(jsonEncode(data), status,
        headers: {'Content-Type': 'application/json'});
Future<AuthClient> login(
    Future<http.Response> Function(http.Request) handle) async {
  final client = AuthClient('http://127.0.0.1', administrator: true,
      transport: MockClient((request) async {
    if (request.url.path.endsWith('/login'))
      return response({'access_token': 'access', 'refresh_token': 'refresh'});
    if (request.url.path.endsWith('/session'))
      return response({'email': 'admin@example.test', 'role': 'ADMINISTRATOR'});
    return handle(request);
  }));
  await client.signIn('admin@example.test', 'password');
  return client;
}

Future<void> finish(WidgetTester tester, AuthClient client) async {
  await tester.pumpWidget(const SizedBox());
  client.close();
}

void main() {
  testWidgets('Proposal navigation opens manual management in the dashboard',
      (tester) async {
    final client = await login((request) async =>
        request.url.path.endsWith('/dashboard')
            ? response({'generated_at': null})
            : response({'items': [], 'total': 0, 'next_offset': null}));
    await tester.pumpWidget(MaterialApp(home: AdminDashboard(client: client)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Proposals').last);
    await tester.pumpAndSettle();
    expect(find.text('Proposal management'), findsOneWidget);
    expect(find.text('Create proposal'), findsOneWidget);
    await finish(tester, client);
  });
  testWidgets(
      'Manual creation selects two approved profiles and submits their versions',
      (tester) async {
    Map<String, dynamic>? body;
    final client = await login((request) async {
      if (request.url.path == '/api/v1/admin/proposals' &&
          request.method == 'POST') {
        body = jsonDecode(request.body);
        return response(detail(), 201);
      }
      if (request.url.path == '/api/v1/admin/proposals')
        return response({'items': [], 'total': 0, 'next_offset': null});
      if (request.url.path == '/api/v1/admin/profiles')
        return response({
          'items': [one, two],
          'total': 2,
          'next_offset': null
        });
      if (request.url.path == '/api/v1/profiles/profile-one')
        return response(one);
      if (request.url.path == '/api/v1/profiles/profile-two')
        return response(two);
      return response(detail());
    });
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: AdminProposalsPanel(client: client))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create proposal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('First Name').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second Name').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create proposal').last);
    await tester.pumpAndSettle();
    expect(body, {
      'profile_a_id': 'profile-one',
      'profile_b_id': 'profile-two',
      'profile_a_version': 3,
      'profile_b_version': 5
    });
    await finish(tester, client);
  });
  testWidgets('Pending proposals cannot release documents', (tester) async {
    final client = await login((_) async => response(detail()));
    await tester.pumpWidget(MaterialApp(
        home: AdminProposalDetail(client: client, proposalId: 'proposal-one')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Authorise selected files'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Authorise selected files'))
            .onPressed,
        isNull);
    for (final tile
        in tester.widgetList<CheckboxListTile>(find.byType(CheckboxListTile))) {
      expect(tile.onChanged, isNull);
    }
    await finish(tester, client);
  });
  testWidgets(
      'Mutual sharing requires file selection and an explicit confirmation',
      (tester) async {
    Map<String, dynamic>? body;
    final client = await login((request) async {
      if (request.method == 'POST') body = jsonDecode(request.body);
      return response(detail(status: 'MUTUALLY_ACCEPTED'));
    });
    await tester.pumpWidget(MaterialApp(
        home: AdminProposalDetail(client: client, proposalId: 'proposal-one')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('one.pdf'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('one.pdf'));
    await tester.ensureVisible(find.text('two.pdf'));
    await tester.tap(find.text('two.pdf'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Authorise selected files'));
    await tester.tap(find.text('Authorise selected files'));
    await tester.pumpAndSettle();
    expect(body, isNull);
    await tester.tap(find.text('Authorise sharing'));
    await tester.pumpAndSettle();
    expect(body!['version'], 3);
    expect(body!['document_ids'], containsAll(['doc-one', 'doc-two']));
    await finish(tester, client);
  });
  testWidgets('Closing a proposal records a private reason after confirmation',
      (tester) async {
    Map<String, dynamic>? body;
    var closed = false;
    final client = await login((request) async {
      if (request.method == 'POST') {
        body = jsonDecode(request.body);
        closed = true;
      }
      return response(
          detail(status: closed ? 'CANCELLED' : 'MUTUALLY_ACCEPTED'));
    });
    await tester.pumpWidget(MaterialApp(
        home: AdminProposalDetail(client: client, proposalId: 'proposal-one')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.text('Close proposal / revoke access'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Close proposal / revoke access'));
    await tester.pumpAndSettle();
    expect(body, isNull);
    await tester.enterText(find.byType(TextFormField), 'Internal reason');
    await tester.tap(find.text('Close proposal'));
    await tester.pumpAndSettle();
    expect(body, {'version': 3, 'reason': 'Internal reason'});
    expect(find.text('Close proposal / revoke access'), findsNothing);
    await finish(tester, client);
  });
}
