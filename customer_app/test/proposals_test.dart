import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jain_customer/auth_client.dart';
import 'package:jain_customer/proposal_screens.dart';

Map<String, dynamic> detail(
        {String status = 'PENDING',
        String? own,
        List<dynamic> files = const []}) =>
    {
      'id': 'proposal-one',
      'version': 1,
      'status': status,
      'created_at': '2026-11-15T00:00:00Z',
      'own_profile': {'id': 'own-profile', 'full_name': 'Own Name'},
      'match': {
        'age': 30,
        'height_cm': 165,
        'community': 'Shwetambar',
        'location': 'Pune',
        'education': 'M.Com',
        'profession': 'Accountant'
      },
      'own_response': own,
      'other_response': status == 'MUTUALLY_ACCEPTED' ? 'ACCEPTED' : null,
      'can_respond': status == 'PENDING' && own == null,
      'shared_documents': files,
      'closure_reason':
          status == 'CANCELLED' ? 'This proposal was closed.' : null
    };
http.Response response(Object data, [int status = 200]) =>
    http.Response(jsonEncode(data), status,
        headers: {'Content-Type': 'application/json'});
Future<AuthClient> login(
    Future<http.Response> Function(http.Request) handle) async {
  final client =
      AuthClient('http://127.0.0.1', transport: MockClient((request) async {
    if (request.url.path.endsWith('/verify'))
      return response({'access_token': 'access', 'refresh_token': 'refresh'});
    if (request.url.path.endsWith('/session'))
      return response({'email': 'one@example.test', 'role': 'CUSTOMER'});
    return handle(request);
  }));
  await client.signIn('one@example.test', '123456');
  return client;
}

Future<void> finish(WidgetTester tester, AuthClient client) async {
  await tester.pumpWidget(const SizedBox());
  client.close();
}

void main() {
  testWidgets(
      'Proposal tabs request pending, full history and specifically shared biodata',
      (tester) async {
    final queries = <Map<String, String>>[];
    final client = await login((request) async {
      queries.add(request.url.queryParameters);
      return response({
        'items': [detail()],
        'total': 1,
        'next_offset': null
      });
    });
    await tester.pumpWidget(MaterialApp(home: ProposalsScreen(client: client)));
    await tester.pumpAndSettle();
    expect(queries.last['status'], 'PENDING');
    expect(find.textContaining('Own Name'), findsOneWidget);
    await tester.tap(find.text('Proposal history'));
    await tester.pumpAndSettle();
    expect(queries.last.containsKey('status'), isFalse);
    await tester.tap(find.text('Shared biodata'));
    await tester.pumpAndSettle();
    expect(queries.last['shared_only'], 'true');
    expect(queries.last['status'], 'MUTUALLY_ACCEPTED');
    await finish(tester, client);
  });
  testWidgets(
      'Acceptance requires confirmation and responds only for the own profile',
      (tester) async {
    Map<String, dynamic>? body;
    var accepted = false;
    final client = await login((request) async {
      if (request.method == 'POST') {
        body = jsonDecode(request.body);
        accepted = true;
      }
      return response(detail(own: accepted ? 'ACCEPTED' : null));
    });
    await tester.pumpWidget(MaterialApp(
        home:
            ProposalDetailScreen(client: client, proposalId: 'proposal-one')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Accept proposal'));
    await tester.tap(find.text('Accept proposal'));
    await tester.pumpAndSettle();
    expect(body, isNull);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(body, {'profile_id': 'own-profile', 'response': 'ACCEPTED'});
    expect(find.text('Accept proposal'), findsNothing);
    await finish(tester, client);
  });
  testWidgets('Mutual acceptance alone does not display file download controls',
      (tester) async {
    final client = await login((_) async =>
        response(detail(status: 'MUTUALLY_ACCEPTED', own: 'ACCEPTED')));
    await tester.pumpWidget(MaterialApp(
        home:
            ProposalDetailScreen(client: client, proposalId: 'proposal-one')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.text(
            'Both parties accepted. Biodata awaits consultancy authorisation.'),
        300,
        scrollable: find.byType(Scrollable).first);
    expect(find.byTooltip('Save shared biodata'), findsNothing);
    expect(find.text('Accept proposal'), findsNothing);
    await finish(tester, client);
  });
  testWidgets(
      'Authorised files are shown while closed proposals have no response controls',
      (tester) async {
    var closed = false;
    final client = await login((_) async => response(detail(
        status: closed ? 'CANCELLED' : 'MUTUALLY_ACCEPTED',
        own: 'ACCEPTED',
        files: closed
            ? []
            : [
                {
                  'id': 'doc-one',
                  'original_name': 'shared.pdf',
                  'authorised_at': '2026-11-15T00:00:00Z'
                }
              ])));
    await tester.pumpWidget(MaterialApp(
        home:
            ProposalDetailScreen(client: client, proposalId: 'proposal-one')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('shared.pdf'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.byTooltip('Save shared biodata'), findsOneWidget);
    closed = true;
    await tester.tap(find.byTooltip('Refresh proposal'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Save shared biodata'), findsNothing);
    expect(find.text('Accept proposal'), findsNothing);
    await finish(tester, client);
  });
  testWidgets('Private notifications can be marked read and filtered',
      (tester) async {
    var read = false;
    final paths = <String>[];
    final client = await login((request) async {
      paths.add(request.url.path);
      if (request.method == 'PUT') {
        read = true;
        return response(
            {'id': 'notice-one', 'read_at': '2026-11-15T00:00:00Z'});
      }
      return response({
        'items': [
          {
            'id': 'notice-one',
            'event': 'NEW_PROPOSAL',
            'message': 'A proposal awaits your response.',
            'read_at': read ? '2026-11-15T00:00:00Z' : null,
            'created_at': '2026-11-15T00:00:00Z',
            'proposal_id': null
          }
        ],
        'total': 1,
        'unread_count': read ? 0 : 1,
        'next_offset': null
      });
    });
    await tester
        .pumpWidget(MaterialApp(home: NotificationsScreen(client: client)));
    await tester.pumpAndSettle();
    expect(find.text('1 unread'), findsOneWidget);
    await tester.tap(find.byTooltip('Mark as read'));
    await tester.pumpAndSettle();
    expect(paths, contains('/api/v1/notifications/notice-one/read'));
    expect(find.text('0 unread'), findsOneWidget);
    await finish(tester, client);
  });
  test('Shared download uses a proposal-scoped bearer-authenticated endpoint',
      () async {
    final client = await login((request) async {
      expect(request.url.path,
          '/api/v1/proposals/proposal-one/documents/doc-one/download');
      expect(request.headers['Authorization'], 'Bearer access');
      return http.Response.bytes([1, 2, 3], 200);
    });
    expect(await client.downloadShared('proposal-one', 'doc-one'), [1, 2, 3]);
    client.close();
  });
}
