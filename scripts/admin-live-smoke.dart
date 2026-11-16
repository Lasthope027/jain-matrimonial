// Run against the disposable PostgreSQL-backed API only.
import 'dart:io';

import '../admin_app/lib/auth_client.dart' as administrator;
import '../customer_app/lib/auth_client.dart' as customer;

Future<void> main() async {
  final base = Platform.environment['TEST_API_URL'];
  final password = Platform.environment['TEST_ADMIN_PASSWORD'];
  if (base != 'http://127.0.0.1:8001' || password == null)
    throw StateError('Use the isolated test API and ephemeral administrator.');
  final admin = administrator.AuthClient(base!, administrator: true);
  final client = customer.AuthClient(base);
  try {
    await admin.signIn('http-admin@example.test', password);
    var account = await admin.request(
      'POST',
      '/admin/customers',
      body: {'email': 'office-live@example.test'},
    );
    if (account['email_verified_at'] != null)
      throw StateError('Administrator creation incorrectly verified email');
    final code = await client.requestCode('office-live@example.test');
    await client.signIn(
      'office-live@example.test',
      code['development_otp'] as String,
    );
    account = await admin.request('GET', '/admin/customers/${account['id']}');
    if (account['email_verified_at'] == null)
      throw StateError('Successful OTP verification was not recorded');
    final profile = await admin.request(
      'POST',
      '/admin/profiles',
      body: {
        'full_name': 'Live Dashboard Profile',
        'gender': 'FEMALE',
        'date_of_birth': '${DateTime.now().year - 30}-01-01',
        'community': 'Shwetambar',
        'current_location': 'Pune',
        'account_email': account['email'],
      },
    );
    final query = Uri(
      queryParameters: {
        'q': 'Live Dashboard',
        'gender': 'FEMALE',
        'location': 'pune',
        'age_min': '29',
        'age_max': '31',
        'community': 'shwet',
      },
    ).query;
    final found = await admin.request('GET', '/admin/profiles?$query');
    if (found['total'] != 1 || found['items'][0]['id'] != profile['id'])
      throw StateError('Combined profile filter failed');
    final stats = await admin.request('GET', '/admin/dashboard');
    if (stats['total_customers'] != 1 ||
        stats['total_profiles'] != 1 ||
        stats['pending_verification'] != 1)
      throw StateError('Dashboard did not reflect new records');
    final listing = await admin.request(
      'GET',
      '/admin/customers?q=office-live',
    );
    if (listing['items'][0]['profile_count'] != 1)
      throw StateError('Customer profile count incorrect');
    account = await admin.request(
      'PUT',
      '/admin/customers/${account['id']}/activation',
      body: {'version': account['version'], 'active': false},
    );
    var denied = false;
    try {
      await client.account();
    } on customer.AuthException {
      denied = true;
    }
    if (!denied)
      throw StateError('Deactivated customer session remained valid');
    await admin.request(
      'PUT',
      '/admin/customers/${account['id']}/activation',
      body: {'version': account['version'], 'active': true},
    );
    final audit = await admin.request(
      'GET',
      '/admin/audit-logs?q=CUSTOMER_DEACTIVATED',
    );
    if (audit['total'] != 1) throw StateError('Account mutation audit missing');
    await admin.signOut();
    stdout.writeln(
      'Live dashboard, profile filters, customer creation/verification, activation/revocation and audit checks passed.',
    );
  } finally {
    admin.close();
    client.close();
  }
}
