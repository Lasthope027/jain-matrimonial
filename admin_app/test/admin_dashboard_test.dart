import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jain_admin/auth_client.dart';
import 'package:jain_admin/admin_dashboard.dart';
import 'package:jain_admin/login_screen.dart';

Map<String, dynamic> stats(int count) => {
      'total_profiles': count,
      'pending_verification': 1,
      'approved_profiles': 1,
      'rejected_profiles': 0,
      'inactive_profiles': 0,
      'total_customers': 1,
      'active_customers': 1,
      'unassociated_profiles': 0,
      'active_proposals': 0,
      'pending_responses': 0,
      'mutually_accepted_proposals': 0,
      'generated_at': '2026-11-15T00:00:00Z'
    };
Map<String, dynamic> customer(
        {bool active = true,
        int version = 1,
        List<dynamic> profiles = const []}) =>
    {
      'id': 'customer-one',
      'email': 'office@example.test',
      'active': active,
      'version': version,
      'email_verified_at': null,
      'created_at': '2026-11-15T00:00:00Z',
      'updated_at': '2026-11-15T00:00:00Z',
      'profiles': profiles,
      'profile_count': profiles.length
    };
Map<String, dynamic> profile() => {
      'id': 'profile-one',
      'full_name': 'Asha Jain',
      'gender': 'FEMALE',
      'status': 'PENDING_VERIFICATION',
      'version': 3,
      'current_location': 'Pune',
      'community': 'Shwetambar'
    };
http.Response jsonResponse(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status,
        headers: {'Content-Type': 'application/json'});
Future<AuthClient> authenticated(
    Future<http.Response> Function(http.Request) handler) async {
  final client = AuthClient('http://127.0.0.1', administrator: true,
      transport: MockClient((request) async {
    if (request.url.path.endsWith('/login'))
      return jsonResponse(
          {'access_token': 'access', 'refresh_token': 'refresh'});
    if (request.url.path.endsWith('/session'))
      return jsonResponse(
          {'email': 'admin@example.test', 'role': 'ADMINISTRATOR'});
    return handler(request);
  }));
  await client.signIn('admin@example.test', 'test-password');
  return client;
}

Finder input(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label);
Future<void> finish(WidgetTester tester, AuthClient client) async {
  await tester.pumpWidget(const SizedBox());
  client.close();
}

void main() {
  testWidgets(
      'Wide desktop layout uses a sidebar and renders searchable profile rows',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = await authenticated(
        (request) async => request.url.path.endsWith('/dashboard')
            ? jsonResponse(stats(1))
            : jsonResponse({
                'items': [profile()],
                'total': 1,
                'next_offset': null
              }));
    await tester.pumpWidget(MaterialApp(home: AdminDashboard(client: client)));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    await tester.tap(find.text('Profiles').last);
    await tester.pumpAndSettle();
    expect(find.text('Asha Jain'), findsOneWidget);
    expect(find.byType(DataTable), findsOneWidget);
    await finish(tester, client);
  });
  testWidgets('Overview shows live database counts and refreshes automatically',
      (tester) async {
    var count = 2, calls = 0;
    final client = await authenticated((request) async {
      calls++;
      expect(request.url.path, '/api/v1/admin/dashboard');
      return jsonResponse(stats(count));
    });
    await tester.pumpWidget(MaterialApp(home: AdminDashboard(client: client)));
    await tester.pumpAndSettle();
    expect(find.text('Consultancy overview'), findsOneWidget);
    expect(find.text('Total profiles'), findsOneWidget);
    expect(calls, 1);
    count = 3;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(calls, 2);
    final card = find.ancestor(
        of: find.text('Total profiles'), matching: find.byType(Card));
    expect(find.descendant(of: card, matching: find.text('3')), findsOneWidget);
    await finish(tester, client);
  });

  testWidgets(
      'Dashboard navigation opens protected customer and activity sections',
      (tester) async {
    final paths = <String>[];
    final client = await authenticated((request) async {
      paths.add(request.url.path);
      return request.url.path.endsWith('/dashboard')
          ? jsonResponse(stats(0))
          : jsonResponse({'items': [], 'total': 0, 'next_offset': null});
    });
    await tester.pumpWidget(MaterialApp(home: AdminDashboard(client: client)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customers').last);
    await tester.pumpAndSettle();
    expect(find.text('Customer accounts'), findsOneWidget);
    await tester.tap(find.text('Activity').last);
    await tester.pumpAndSettle();
    expect(find.text('System activity'), findsOneWidget);
    expect(paths, contains('/api/v1/admin/customers'));
    expect(paths, contains('/api/v1/admin/audit-logs'));
    await finish(tester, client);
  });

  testWidgets('Profile filters submit search and reset the visible selection',
      (tester) async {
    final queries = <Map<String, String>>[];
    final client = await authenticated((request) async {
      queries.add(request.url.queryParameters);
      return jsonResponse({'items': [], 'total': 0, 'next_offset': null});
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AdminProfilesPanel(
                client: client, initialStatus: 'APPROVED'))));
    await tester.pumpAndSettle();
    await tester.enterText(input('Name or profile ID'), 'asha');
    await tester.ensureVisible(find.byKey(const ValueKey('gender-null')));
    await tester.tap(find.byKey(const ValueKey('gender-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Female').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Apply filters'));
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    expect(queries.last['q'], 'asha');
    expect(queries.last['gender'], 'FEMALE');
    expect(queries.last['status'], 'APPROVED');
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(queries.last.containsKey('gender'), isFalse);
    expect(queries.last.containsKey('status'), isFalse);
    expect(find.byKey(const ValueKey('gender-null')), findsOneWidget);
    await finish(tester, client);
  });

  testWidgets('Customer creation uses email and lists an unverified account',
      (tester) async {
    var created = false;
    Map<String, dynamic>? body;
    final client = await authenticated((request) async {
      if (request.method == 'POST') {
        body = jsonDecode(request.body);
        created = true;
        return jsonResponse(customer(), 201);
      }
      return jsonResponse({
        'items': created ? [customer()] : [],
        'total': created ? 1 : 0,
        'next_offset': null
      });
    });
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: CustomersPanel(client: client))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create customer'));
    await tester.pumpAndSettle();
    await tester.enterText(input('Customer email'), 'office@example.test');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(body, {'email': 'office@example.test'});
    expect(find.text('office@example.test'), findsOneWidget);
    expect(find.text('Not yet verified'), findsOneWidget);
    await finish(tester, client);
  });

  testWidgets(
      'Deactivation requires confirmation and sends the current version',
      (tester) async {
    var active = true, version = 1;
    Map<String, dynamic>? change;
    final client = await authenticated((request) async {
      if (request.method == 'PUT') {
        change = jsonDecode(request.body);
        active = false;
        version = 2;
      }
      return jsonResponse(customer(active: active, version: version));
    });
    await tester.pumpWidget(MaterialApp(
        home: CustomerDetail(client: client, customerId: 'customer-one')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deactivate account'));
    await tester.pumpAndSettle();
    expect(change, isNull);
    expect(find.text('Deactivate customer account?'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(change, {'version': 1, 'active': false});
    expect(find.text('Inactive'), findsOneWidget);
    expect(find.text('Activate account'), findsOneWidget);
    await finish(tester, client);
  });

  testWidgets(
      'Account linking chooses an unassociated profile and uses its version',
      (tester) async {
    var linked = false;
    Map<String, dynamic>? body;
    final client = await authenticated((request) async {
      if (request.url.path == '/api/v1/admin/profiles') {
        expect(request.url.queryParameters['unassociated_only'], 'true');
        return jsonResponse({
          'items': [profile()],
          'total': 1,
          'next_offset': null
        });
      }
      if (request.method == 'PUT') {
        body = jsonDecode(request.body);
        linked = true;
        return jsonResponse(profile());
      }
      return jsonResponse(customer(profiles: linked ? [profile()] : []));
    });
    await tester.pumpWidget(MaterialApp(
        home: CustomerDetail(client: client, customerId: 'customer-one')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Link existing profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asha Jain'));
    await tester.pumpAndSettle();
    expect(body, {'version': 3, 'email': 'office@example.test'});
    expect(find.text('Asha Jain'), findsOneWidget);
    await finish(tester, client);
  });

  testWidgets('Activity viewer displays immutable actor and event details',
      (tester) async {
    final client = await authenticated((request) async => jsonResponse({
          'items': [
            {
              'id': 'event-one',
              'action': 'CUSTOMER_CREATED',
              'actor_email': 'admin@example.test',
              'created_at': '2026-11-15T00:00:00Z',
              'entity_type': 'customer',
              'entity_id': 'customer-one',
              'details': {'from_active': true, 'to_active': false}
            }
          ],
          'total': 1,
          'next_offset': null
        }));
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ActivityPanel(client: client))));
    await tester.pumpAndSettle();
    expect(find.text('CUSTOMER_CREATED'), findsOneWidget);
    await tester.ensureVisible(find.text('Details'));
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await finish(tester, client);
  });

  testWidgets('Failed dashboard requests show retry without fabricated counts',
      (tester) async {
    var fail = true;
    final client = await authenticated((request) async => fail
        ? jsonResponse({'detail': 'Service temporarily unavailable'}, 503)
        : jsonResponse(stats(4)));
    await tester.pumpWidget(MaterialApp(home: AdminDashboard(client: client)));
    await tester.pumpAndSettle();
    expect(find.text('Service temporarily unavailable'), findsOneWidget);
    expect(find.text('Total profiles'), findsNothing);
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Total profiles'), findsOneWidget);
    await finish(tester, client);
  });

  testWidgets(
      'Administrator sign-in opens the dashboard from its account screen',
      (tester) async {
    final client =
        await authenticated((request) async => jsonResponse(stats(0)));
    await tester.pumpWidget(MaterialApp(home: LoginScreen(client: client)));
    await tester.enterText(input('Email address'), 'admin@example.test');
    await tester.enterText(input('Password'), 'test-password');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open dashboard'));
    await tester.pumpAndSettle();
    expect(find.text('Consultancy overview'), findsOneWidget);
    await finish(tester, client);
  });
}
