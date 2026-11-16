import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'auth_client.dart';
import 'profile_workspace.dart';
import 'admin_dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.client});
  final AuthClient client;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final credential = TextEditingController();
  final form = GlobalKey<FormState>();
  bool busy = false;
  bool codeSent = false;
  String? message;
  String? developmentCode;
  Map<String, dynamic>? user;
  DateTime? resendAt;
  Timer? ticker;
  int get cooldown => resendAt == null
      ? 0
      : resendAt!.difference(DateTime.now()).inSeconds.clamp(0, 60);

  @override
  void dispose() {
    ticker?.cancel();
    email.dispose();
    credential.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() operation) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await operation();
    } on AuthException catch (error) {
      if (mounted) setState(() => message = error.message);
    } catch (_) {
      if (mounted)
        setState(() =>
            message = 'Unable to complete the request. Please try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> sendCode() async {
    if (!codeSent && !form.currentState!.validate()) return;
    await run(() async {
      final result = await widget.client.requestCode(email.text);
      if (!mounted) return;
      setState(() {
        codeSent = true;
        credential.clear();
        developmentCode = result['development_otp'] as String?;
        resendAt = DateTime.now().add(
            Duration(seconds: (result['resend_after'] as num?)?.toInt() ?? 60));
        message =
            'Check your email for a six-digit code. It expires in five minutes.';
      });
      ticker?.cancel();
      ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || cooldown == 0) timer.cancel();
        if (mounted) setState(() {});
      });
    });
  }

  Future<void> signIn() async {
    if (!form.currentState!.validate()) return;
    await run(() async {
      final account = await widget.client.signIn(email.text, credential.text);
      if (!mounted) return;
      setState(() {
        user = account;
        developmentCode = null;
        credential.clear();
      });
      ticker?.cancel();
    });
  }

  Future<void> signOut() async {
    await run(() async {
      try {
        await widget.client.signOut();
      } on AuthException {
        if (mounted)
          setState(() => message =
              'Signed out on this device. The server could not be reached.');
      } finally {
        if (mounted)
          setState(() {
            user = null;
            codeSent = false;
            credential.clear();
            developmentCode = null;
          });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final admin = widget.client.administrator;
    return Scaffold(
      appBar: AppBar(
          title: Text(admin ? 'Jain Consultancy Admin' : 'Jain Matrimonial')),
      body: Center(
          child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
              child: Padding(
            padding: const EdgeInsets.all(28),
            child: user != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        Text(
                            admin
                                ? 'Administrator account'
                                : 'Welcome to your consultancy',
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 16),
                        Text(user!['email'] as String),
                        const SizedBox(height: 16),
                        const Text('You are signed in. Your account is ready.'),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                            onPressed: busy
                                ? null
                                : () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                        builder: (_) => admin
                                            ? AdminDashboard(
                                                client: widget.client)
                                            : ProfileWorkspace(
                                                client: widget.client))),
                            icon: const Icon(Icons.people_outline),
                            label:
                                Text(admin ? 'Open dashboard' : 'My profiles')),
                        if (message != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Text(message!)),
                        const SizedBox(height: 24),
                        OutlinedButton(
                            onPressed: busy ? null : signOut,
                            child: const Text('Sign out')),
                      ])
                : Form(
                    key: form,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                              admin
                                  ? 'Administrator sign in'
                                  : 'Sign in or register',
                              style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 12),
                          Text(admin
                              ? 'Use your consultancy administrator account.'
                              : 'Use your email to manage matrimonial profiles for your family.'),
                          const SizedBox(height: 24),
                          TextFormField(
                              controller: email,
                              enabled: !busy && !codeSent,
                              decoration: const InputDecoration(
                                  labelText: 'Email address',
                                  border: OutlineInputBorder()),
                              keyboardType: TextInputType.emailAddress,
                              autocorrect: false,
                              autofillHints: const [AutofillHints.email],
                              validator: (value) => value != null &&
                                      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                          .hasMatch(value.trim())
                                  ? null
                                  : 'Enter your email address'),
                          if (admin || codeSent) ...[
                            const SizedBox(height: 16),
                            TextFormField(
                                controller: credential,
                                enabled: !busy,
                                decoration: InputDecoration(
                                    labelText:
                                        admin ? 'Password' : 'Six-digit code',
                                    border: const OutlineInputBorder()),
                                obscureText: admin,
                                autocorrect: false,
                                enableSuggestions: false,
                                keyboardType: admin
                                    ? TextInputType.visiblePassword
                                    : TextInputType.number,
                                inputFormatters: admin
                                    ? null
                                    : [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(6)
                                      ],
                                autofillHints: admin
                                    ? const [AutofillHints.password]
                                    : const [AutofillHints.oneTimeCode],
                                validator: (value) => admin
                                    ? ((value?.isNotEmpty ?? false)
                                        ? null
                                        : 'Enter your password')
                                    : (RegExp(r'^[0-9]{6}$')
                                            .hasMatch(value ?? '')
                                        ? null
                                        : 'Enter the six-digit code')),
                          ],
                          if (message != null)
                            Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Semantics(
                                    liveRegion: true, child: Text(message!))),
                          if (kDebugMode && developmentCode != null)
                            Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child:
                                    Text('Development code: $developmentCode')),
                          const SizedBox(height: 24),
                          FilledButton(
                              onPressed: busy
                                  ? null
                                  : (admin || codeSent ? signIn : sendCode),
                              child: Text(busy
                                  ? 'Please wait…'
                                  : (admin || codeSent
                                      ? 'Sign in'
                                      : 'Send sign-in code'))),
                          if (!admin && codeSent) ...[
                            const SizedBox(height: 8),
                            TextButton(
                                onPressed:
                                    busy || cooldown > 0 ? null : sendCode,
                                child: Text(cooldown > 0
                                    ? 'Resend in ${cooldown}s'
                                    : 'Resend code')),
                            TextButton(
                                onPressed: busy
                                    ? null
                                    : () {
                                        ticker?.cancel();
                                        setState(() {
                                          codeSent = false;
                                          developmentCode = null;
                                          message = null;
                                          credential.clear();
                                        });
                                      },
                                child: const Text('Use another email')),
                          ],
                        ])),
          )),
        ),
      )),
    );
  }
}
