// Run only against the disposable test API and test database.
import 'dart:io';

import '../customer_app/lib/auth_client.dart' as customer;
import '../admin_app/lib/auth_client.dart' as administrator;

Future<void> main() async {
  final base = Platform.environment['TEST_API_URL'];
  final password = Platform.environment['TEST_ADMIN_PASSWORD'];
  if (base != 'http://127.0.0.1:8001' || password == null) {
    throw StateError(
      'Provide the disposable test API and ephemeral administrator password.',
    );
  }
  final client = customer.AuthClient(base!);
  final admin = administrator.AuthClient(base, administrator: true);
  try {
    final otp = await client.requestCode('http-smoke@example.test');
    final account = await client.signIn(
      'http-smoke@example.test',
      otp['development_otp'] as String,
    );
    if (account['role'] != 'CUSTOMER')
      throw StateError('Customer role mismatch');
    await client.signOut();
    final adminAccount = await admin.signIn(
      'http-admin@example.test',
      password,
    );
    if (adminAccount['role'] != 'ADMINISTRATOR')
      throw StateError('Administrator role mismatch');
    await admin.signOut();
    stdout.writeln(
      'Customer and administrator live HTTP sign-in/logout passed.',
    );
  } finally {
    client.close();
    admin.close();
  }
}
