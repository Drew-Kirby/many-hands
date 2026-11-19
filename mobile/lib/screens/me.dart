import 'package:material_ui/material_ui.dart';

import '../store.dart';
import '../util.dart';
import '../widgets.dart';
import 'auth.dart';
import 'members.dart';

class MeScreen extends StatelessWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final me = store.member(auth.currentUser?.uid);
        return Scaffold(
          appBar: AppBar(title: const Text('Me'), actions: [
            TextButton(
              onPressed: () async {
                if (await confirm(context, 'Log out of Many Hands?', yes: 'Log out')) await auth.signOut();
              },
              child: const Text('Log out'),
            ),
          ]),
          body: me == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(children: [
                  const SizedBox(height: 16),
                  Center(child: Avatar(me.name, size: 72)),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(me.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  Center(
                    child: TextButton.icon(
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit profile'),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfile())),
                    ),
                  ),
                  ContactTile(icon: Icons.email_outlined, text: me.email),
                  ContactTile(icon: Icons.phone_outlined, text: me.phone),
                  ...memberTaskSections(context, me),
                ]),
        );
      },
    );
  }
}

// Name and phone only. Changing the login email needs re-authentication, so that stays on the website.
class EditProfile extends StatefulWidget {
  const EditProfile({super.key});
  @override
  State<EditProfile> createState() => _EditProfileState();
}

class _EditProfileState extends State<EditProfile> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: store.member(auth.currentUser!.uid)?.name);
  late final _phone = TextEditingController(text: formatPhone(store.member(auth.currentUser!.uid)?.phone ?? ''));
  bool _busy = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final ok = await attempt(context,
        () => Api.updateMember(auth.currentUser!.uid, name: _name.text.trim(), phone: _phone.text),
        success: 'Profile saved.');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Edit profile')),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            TextFormField(
              controller: _name,
              maxLength: 80,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Your name'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your name' : null,
            ),
            const SizedBox(height: 8),
            PhoneField(controller: _phone),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              child: Text(_busy ? 'Saving…' : 'Save'),
            ),
          ]),
        ),
      );
}
