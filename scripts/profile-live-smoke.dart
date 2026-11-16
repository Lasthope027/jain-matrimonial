// Integration verification against the disposable PostgreSQL-backed API only.
import 'dart:io';

import '../customer_app/lib/auth_client.dart' as customer;
import '../admin_app/lib/auth_client.dart' as administrator;

Future<void> main() async {
  final base = Platform.environment['TEST_API_URL'];
  final password = Platform.environment['TEST_ADMIN_PASSWORD'];
  final photo = Platform.environment['TEST_PHOTO'];
  if (base != 'http://127.0.0.1:8001' || password == null || photo == null) {
    throw StateError(
      'Provide the isolated test API, ephemeral password and image fixture.',
    );
  }
  final a = customer.AuthClient(base!);
  final b = customer.AuthClient(base);
  final admin = administrator.AuthClient(base, administrator: true);
  try {
    for (final entry in {
      a: 'profile-a@example.test',
      b: 'profile-b@example.test',
    }.entries) {
      final code = await entry.key.requestCode(entry.value);
      await entry.key.signIn(entry.value, code['development_otp'] as String);
    }
    await admin.signIn('http-admin@example.test', password);
    final body = <String, dynamic>{
      'full_name': 'Integration Profile',
      'gender': 'FEMALE',
      'date_of_birth': '1996-05-12',
      'education': {'qualification': 'M.Com'},
      'family': {'siblings': 1},
      'preferences': {
        'locations': ['Pune'],
      },
    };
    var profile = await a.request('POST', '/profiles', body: body);
    final id = profile['id'];
    if ((await b.request('GET', '/profiles'))['items'].isNotEmpty)
      throw StateError('Cross-account listing leak');
    profile = await admin.request(
      'PUT',
      '/admin/profiles/$id/verification',
      body: {'version': profile['version'], 'status': 'APPROVED'},
    );
    final uploaded = await a.upload(
      id as String,
      profile['version'] as int,
      'photo.png',
      'PHOTO',
      await File(photo).readAsBytes(),
    );
    final docId = uploaded['document']['id'] as String;
    final downloaded = await a.download(docId);
    if (downloaded.length != (await File(photo).length()))
      throw StateError('File did not round-trip');
    profile = await a.request('GET', '/profiles/$id');
    if (profile['status'] != 'PENDING_VERIFICATION')
      throw StateError('Document change did not require verification');
    profile = await admin.request(
      'PUT',
      '/admin/profiles/$id/account',
      body: {'version': profile['version'], 'email': 'profile-b@example.test'},
    );
    var denied = false;
    try {
      await a.download(docId);
    } on customer.AuthException {
      denied = true;
    }
    if (!denied) throw StateError('Former owner still has document access');
    await b.download(docId);
    await b.request(
      'DELETE',
      '/documents/$docId?version=${profile['version']}',
    );
    final manual = await admin.request('POST', '/admin/profiles', body: body);
    if (manual['account_email'] != null)
      throw StateError('Manual profile unexpectedly has an owner');
    await a.signOut();
    await b.signOut();
    await admin.signOut();
    stdout.writeln(
      'Live profile creation, verification, upload/download, reassignment, removal and manual creation passed.',
    );
  } finally {
    a.close();
    b.close();
    admin.close();
  }
}
