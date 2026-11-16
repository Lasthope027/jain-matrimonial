// Complete two-customer workflow against the isolated test API only.
import 'dart:io';
import 'dart:convert';

import '../admin_app/lib/auth_client.dart' as administrator;
import '../customer_app/lib/auth_client.dart' as customer;

Future<void> main() async {
  final base = Platform.environment['TEST_API_URL'],
      password = Platform.environment['TEST_ADMIN_PASSWORD'],
      photo = Platform.environment['TEST_PHOTO'];
  if (base != 'http://127.0.0.1:8001' || password == null || photo == null)
    throw StateError('Use isolated test configuration.');
  final admin = administrator.AuthClient(base!, administrator: true),
      a = customer.AuthClient(base),
      b = customer.AuthClient(base);
  final bytes = await File(photo).readAsBytes();
  try {
    await admin.signIn('http-admin@example.test', password);
    final profiles = <Map<String, dynamic>>[], docs = <String>[];
    for (final item in [
      (a, 'proposal-a@example.test', 'Private First'),
      (b, 'proposal-b@example.test', 'Private Second'),
    ]) {
      final code = await item.$1.requestCode(item.$2);
      await item.$1.signIn(item.$2, code['development_otp'] as String);
      var p = await item.$1.request(
        'POST',
        '/profiles',
        body: {
          'full_name': item.$3,
          'gender': 'FEMALE',
          'date_of_birth': '1996-05-12',
          'current_location': 'Pune',
          'education': {
            'qualification': 'M.Com',
            'profession': 'Accountant',
            'company': 'PRIVATE EMPLOYER',
          },
          'family': {'father_name': 'PRIVATE FAMILY'},
        },
      );
      final file = await item.$1.upload(
        p['id'] as String,
        p['version'] as int,
        '${item.$3}-biodata.png',
        'BIODATA',
        bytes,
      );
      docs.add(file['document']['id'] as String);
      p = await admin.request(
        'PUT',
        '/admin/profiles/${p['id']}/verification',
        body: {'version': file['profile_version'], 'status': 'APPROVED'},
      );
      profiles.add(p);
    }
    Future<Map<String, dynamic>> create() => admin.request(
      'POST',
      '/admin/proposals',
      body: {
        'profile_a_id': profiles[0]['id'],
        'profile_b_id': profiles[1]['id'],
        'profile_a_version': profiles[0]['version'],
        'profile_b_version': profiles[1]['version'],
      },
    );
    var p = await create();
    final id = p['id'] as String;
    var own = await a.request('GET', '/proposals/$id');
    if (jsonEncode(own).contains('Private Second') ||
        jsonEncode(own).contains('PRIVATE EMPLOYER') ||
        (own['shared_documents'] as List).isNotEmpty)
      throw StateError('Premature private data exposure');
    Future<void> denied() async {
      var rejected = false;
      try {
        await a.downloadShared(id, docs[1]);
      } on customer.AuthException {
        rejected = true;
      }
      if (!rejected) throw StateError('Premature shared download');
    }

    await denied();
    p = await a.request(
      'POST',
      '/proposals/$id/responses',
      body: {'profile_id': profiles[0]['id'], 'response': 'ACCEPTED'},
    );
    if (p['status'] != 'PENDING')
      throw StateError('One acceptance incorrectly finalised proposal');
    p = await b.request(
      'POST',
      '/proposals/$id/responses',
      body: {'profile_id': profiles[1]['id'], 'response': 'ACCEPTED'},
    );
    if (p['status'] != 'MUTUALLY_ACCEPTED')
      throw StateError('Mutual acceptance missing');
    await denied();
    p = await admin.request(
      'POST',
      '/admin/proposals/$id/sharing',
      body: {'version': p['version'], 'document_ids': docs},
    );
    if ((p['sharing_records'] as List).length != 2)
      throw StateError('Sharing audit missing');
    if (base64Encode(await a.downloadShared(id, docs[1])) !=
        base64Encode(bytes))
      throw StateError('Biodata bytes changed');
    await b.downloadShared(id, docs[0]);
    final notices = await a.request('GET', '/notifications');
    final notice = (notices['items'] as List).firstWhere(
      (e) => e['event'] == 'BIODATA_SHARED',
    );
    await a.request('PUT', '/notifications/${notice['id']}/read');
    profiles[0] = await a.request(
      'PUT',
      '/profiles/${profiles[0]['id']}',
      body: {
        'version': profiles[0]['version'],
        'full_name': 'UPDATED PRIVATE NAME',
        'gender': 'FEMALE',
        'date_of_birth': '1996-05-12',
      },
    );
    own = await b.request('GET', '/proposals/$id');
    if (own['status'] != 'CANCELLED' ||
        jsonEncode(own).contains('UPDATED PRIVATE NAME'))
      throw StateError('Consent invalidation or snapshot privacy failed');
    await denied();
    p = await admin.request('GET', '/proposals/$id');
    if ((p['sharing_records'] as List).any((e) => e['revoked_at'] == null))
      throw StateError('Sharing remained active after profile edit');
    profiles[0] = await admin.request(
      'PUT',
      '/admin/profiles/${profiles[0]['id']}/verification',
      body: {'version': profiles[0]['version'], 'status': 'APPROVED'},
    );
    p = await create();
    await a.request(
      'POST',
      '/proposals/${p['id']}/responses',
      body: {'profile_id': profiles[0]['id'], 'response': 'REJECTED'},
    );
    var rejectionFinal = false;
    try {
      await b.request(
        'POST',
        '/proposals/${p['id']}/responses',
        body: {'profile_id': profiles[1]['id'], 'response': 'ACCEPTED'},
      );
    } on customer.AuthException {
      rejectionFinal = true;
    }
    if (!rejectionFinal)
      throw StateError('Rejection did not finalise proposal');
    await create(); // Leave one pending record to verify legacy migration withdrawal.
    await a.signOut();
    await b.signOut();
    await admin.signOut();
    stdout.writeln(
      'Live proposal creation, private previews, independent responses, explicit sharing, exact-byte downloads, notifications, revocation and final rejection passed.',
    );
  } finally {
    admin.close();
    a.close();
    b.close();
  }
}
