import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

import '../store.dart';
import '../util.dart';
import '../widgets.dart';

class AuthScreen extends StatefulWidget {
  final String communityName;
  const AuthScreen({super.key, required this.communityName});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _login = true;
  bool _showPassword = false;
  bool _busy = false;
  String? _error;
  String? _notice;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = _notice = null;
    });
    try {
      final email = _email.text.trim();
      if (_login) {
        await auth.signInWithEmailAndPassword(email: email, password: _password.text);
      } else {
        signingUp.value = true;
        try {
          final cred = await auth.createUserWithEmailAndPassword(email: email, password: _password.text);
          await Api.saveNewMember(cred.user!.uid, _name.text.trim(), cred.user!.email ?? email, _phone.text);
        } finally {
          signingUp.value = false;
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email above first, and we can send you a reset link.');
      return;
    }
    try {
      await auth.sendPasswordResetEmail(email: email);
      setState(() {
        _error = null;
        _notice = 'If $email has an account, a reset link is on its way.';
      });
    } on FirebaseAuthException catch (e) {
      setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Icon(Icons.back_hand_outlined, size: 56, color: brand),
                  const SizedBox(height: 12),
                  Text(_login ? 'Welcome back.' : 'Join Many Hands.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                  Text(widget.communityName, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
                  const SizedBox(height: 24),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Log in')),
                      ButtonSegment(value: false, label: Text('Sign up')),
                    ],
                    selected: {_login},
                    onSelectionChanged: (s) => setState(() {
                      _login = s.first;
                      _error = _notice = null;
                    }),
                  ),
                  const SizedBox(height: 20),
                  if (!_login) ...[
                    TextFormField(
                      controller: _name,
                      maxLength: 80,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.name],
                      decoration: const InputDecoration(labelText: 'Your name'),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your name' : null,
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (v) => (v ?? '').contains('@') ? null : 'Enter your email',
                  ),
                  const SizedBox(height: 16),
                  if (!_login) ...[
                    PhoneField(controller: _phone),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _password,
                    obscureText: !_showPassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: [_login ? AutofillHints.password : AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'Password',
                      helperText: _login ? null : 'At least 8 characters.',
                      suffixIcon: TextButton(
                        onPressed: () => setState(() => _showPassword = !_showPassword),
                        child: Text(_showPassword ? 'Hide' : 'Show'),
                      ),
                    ),
                    validator: (v) {
                      if ((v ?? '').isEmpty) return 'Enter your password';
                      if (!_login && v!.length < 8) return 'Use at least 8 characters';
                      return null;
                    },
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  if (_notice != null) ...[
                    const SizedBox(height: 12),
                    Text(_notice!, style: const TextStyle(color: brand)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    child: Text(_busy ? 'One moment…' : _login ? 'Log in' : 'Create account'),
                  ),
                  const SizedBox(height: 8),
                  if (_login)
                    TextButton(onPressed: _forgot, child: const Text('Forgot your password?'))
                  else
                    Text('Other members will see your name, email and phone. Only you can change them.',
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PhoneField extends StatelessWidget {
  final TextEditingController controller;
  const PhoneField({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: TextInputType.phone,
        autofillHints: const [AutofillHints.telephoneNumber],
        inputFormatters: [PhoneFormatter()],
        decoration: const InputDecoration(labelText: 'Phone', hintText: '(555) 123-4567', helperText: '10-digit US number.'),
        validator: (v) => isValidPhone(v ?? '') ? null : 'Enter a 10-digit phone number',
      );
}

// Someone signed in whose profile is missing (for example, sign-up was interrupted).
class FinishProfile extends StatefulWidget {
  final User user;
  const FinishProfile({super.key, required this.user});
  @override
  State<FinishProfile> createState() => _FinishProfileState();
}

class _FinishProfileState extends State<FinishProfile> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _busy = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    await attempt(context,
        () => Api.saveNewMember(widget.user.uid, _name.text.trim(), widget.user.email ?? '', _phone.text));
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Finish your profile'), actions: [
          TextButton(onPressed: () => auth.signOut(), child: const Text('Log out')),
        ]),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(24), children: [
            const Text('Add your name and phone so the group can reach you.'),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Your name'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your name' : null,
            ),
            const SizedBox(height: 8),
            PhoneField(controller: _phone),
            const SizedBox(height: 24),
            FilledButton(onPressed: _busy ? null : _save, child: const Text('Save and continue')),
          ]),
        ),
      );
}
