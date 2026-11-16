import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jain_customer/auth_client.dart';
import 'package:jain_customer/profile_workspace.dart';

Map<String, dynamic> profile({int version = 2, String status = 'APPROVED'}) => {
      'id': 'profile-one',
      'version': version,
      'status': status,
      'full_name': 'Asha Jain',
      'gender': 'FEMALE',
      'date_of_birth': '1996-05-12',
      'height_cm': 165,
      'marital_status': 'NEVER_MARRIED',
      'community': 'Shwetambar',
      'sub_community': 'Sthanakvasi',
      'mother_tongue': 'Hindi',
      'current_location': 'Pune',
      'native_place': 'Indore',
      'verification_note': null,
      'education': {'qualification': 'M.Com', 'annual_income': '600000.00'},
      'family': {'father_name': 'Parent', 'siblings': 1},
      'preferences': {
        'age_min': 27,
        'age_max': 35,
        'locations': ['Pune'],
        'communities': ['Shwetambar'],
        'marital_statuses': ['NEVER_MARRIED']
      },
      'account_email': null,
    };

Future<AuthClient> loggedIn(
    Future<http.Response> Function(http.Request) handler,
    {bool admin = false}) async {
  final client = AuthClient('http://127.0.0.1', administrator: admin,
      transport: MockClient((request) async {
    if (request.url.path.endsWith('/verify') ||
        request.url.path.endsWith('/login')) {
      return http.Response(
          '{"access_token":"access","refresh_token":"refresh"}', 200);
    }
    if (request.url.path.endsWith('/session'))
      return http.Response(
          jsonEncode({
            'email': 'family@example.test',
            'role': admin ? 'ADMINISTRATOR' : 'CUSTOMER'
          }),
          200);
    return handler(request);
  }));
  await client.signIn('family@example.test', admin ? 'password' : '123456');
  return client;
}

Finder input(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label);

void main() {
  testWidgets(
      'Customer workspace lists authorised profiles and opens full biodata',
      (tester) async {
    final client = await loggedIn((request) async {
      if (request.url.path == '/api/v1/profiles')
        return http.Response(
            jsonEncode({
              'items': [profile()],
              'next_offset': null
            }),
            200);
      if (request.url.path.endsWith('/documents'))
        return http.Response('{"items":[]}', 200);
      return http.Response(jsonEncode(profile()), 200);
    });
    await tester
        .pumpWidget(MaterialApp(home: ProfileWorkspace(client: client)));
    await tester.pumpAndSettle();
    expect(find.text('Asha Jain'), findsOneWidget);
    await tester.tap(find.text('Asha Jain'));
    await tester.pumpAndSettle();
    expect(find.text('Profile details'), findsOneWidget);
    expect(input('Full name'), findsOneWidget);
    expect(find.text('Consultancy administration'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets(
      'Edit saves all biodata with a version and displays reverification',
      (tester) async {
    Map<String, dynamic>? submitted;
    final client = await loggedIn((request) async {
      if (request.url.path.endsWith('/documents'))
        return http.Response('{"items":[]}', 200);
      if (request.method == 'PUT') {
        submitted = jsonDecode(request.body) as Map<String, dynamic>;
        final result = profile(version: 3, status: 'PENDING_VERIFICATION');
        result['full_name'] = 'Updated Name';
        return http.Response(jsonEncode(result), 200);
      }
      return http.Response(jsonEncode(profile()), 200);
    });
    await tester.pumpWidget(MaterialApp(
        home: ProfileEditor(client: client, profileId: 'profile-one')));
    await tester.pumpAndSettle();
    await tester.enterText(input('Full name'), 'Updated Name');
    await tester.tap(find.text('Save profile'));
    await tester.pumpAndSettle();
    expect(submitted, isNotNull,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .join(' | '));
    expect(submitted!['version'], 2);
    expect(submitted!['full_name'], 'Updated Name');
    expect((submitted!['education'] as Map)['qualification'], 'M.Com');
    expect((submitted!['preferences'] as Map)['locations'], ['Pune']);
    expect(submitted!.containsKey('status'), isFalse);
    expect(find.text('Pending verification'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets(
      'Customer cannot edit inactive profiles or use administrator controls',
      (tester) async {
    final client = await loggedIn((request) async =>
        request.url.path.endsWith('/documents')
            ? http.Response('{"items":[]}', 200)
            : http.Response(jsonEncode(profile(status: 'INACTIVE')), 200));
    await tester.pumpWidget(MaterialApp(
        home: ProfileEditor(client: client, profileId: 'profile-one')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Save profile'))
            .onPressed,
        isNull);
    expect(find.text('Link customer account'), findsNothing);
    expect(find.text('Verification'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets('Administrator confirms verification against the current version',
      (tester) async {
    Map<String, dynamic>? submitted;
    final client = await loggedIn((request) async {
      if (request.url.path.endsWith('/documents'))
        return http.Response('{"items":[]}', 200);
      if (request.url.path.endsWith('/verification')) {
        submitted = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
            jsonEncode(profile(version: 3, status: 'APPROVED')), 200);
      }
      return http.Response(
          jsonEncode(profile(status: 'PENDING_VERIFICATION')), 200);
    }, admin: true);
    await tester.pumpWidget(MaterialApp(
        home: ProfileEditor(client: client, profileId: 'profile-one')));
    await tester.pumpAndSettle();
    final approve = find.widgetWithText(OutlinedButton, 'Approved');
    await tester.ensureVisible(approve);
    await tester.tap(approve);
    await tester.pumpAndSettle();
    expect(submitted, isNull);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(submitted!['status'], 'APPROVED');
    expect(submitted!['version'], 2);
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets('Unsaved edits cannot be discarded by document removal',
      (tester) async {
    var removed = false;
    final client = await loggedIn((request) async {
      if (request.method == 'DELETE') removed = true;
      if (request.url.path.endsWith('/documents'))
        return http.Response(
            '{"items":[{"id":"doc-one","original_name":"bio.pdf","kind":"BIODATA"}]}',
            200);
      return http.Response(jsonEncode(profile()), 200);
    });
    await tester.pumpWidget(MaterialApp(
        home: ProfileEditor(client: client, profileId: 'profile-one')));
    await tester.pumpAndSettle();
    await tester.enterText(input('Full name'), 'Unsaved Name');
    expect(find.byTooltip('Remove document'), findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .join(' | '));
    await tester.ensureVisible(find.byTooltip('Remove document'));
    await tester.tap(find.byTooltip('Remove document'));
    await tester.pumpAndSettle();
    expect(removed, isFalse);
    expect(
        find.text(
            'Save profile changes before managing documents, accounts or verification.'),
        findsOneWidget);
    expect(tester.widget<TextField>(input('Full name')).controller!.text,
        'Unsaved Name');
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  test('Document client sends authenticated binary uploads and downloads',
      () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final client = await loggedIn((request) async {
      expect(request.headers['Authorization'], 'Bearer access');
      if (request.method == 'POST') {
        expect(request.url.queryParameters['version'], '2');
        expect(request.url.queryParameters['filename'], 'photo.png');
        expect(request.bodyBytes, bytes);
        expect(request.headers['Content-Type'], 'image/png');
        return http.Response(
            '{"document":{"id":"doc-one"},"profile_version":3}', 201);
      }
      return http.Response.bytes(bytes, 200);
    });
    expect(
        (await client.upload(
            'profile-one', 2, 'photo.png', 'PHOTO', bytes))['profile_version'],
        3);
    expect(await client.download('doc-one'), bytes);
    client.close();
  });
}
