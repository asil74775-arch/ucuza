import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/session.dart';
import '../../core/widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.interests = const []});
  final List<String> interests;
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  final pass = TextEditingController();
  final name = TextEditingController();
  bool register = true, busy = false, accepted = false;

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    if (register && !accepted) return toast(context, 'Devam etmek için gizlilik politikasını onaylayın');
    setState(() => busy = true);
    try {
      final a = ref.read(authProvider.notifier);
      register
          ? await a.register(email.text.trim(), pass.text, name.text.trim(), widget.interests)
          : await a.login(email.text.trim(), pass.text);
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(register ? 'Hesap oluştur' : 'Giriş yap')),
      body: Form(
        key: form,
        child: ListView(padding: const EdgeInsets.all(24), children: [
          if (register) ...[
            TextFormField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Ad Soyad', prefixIcon: Icon(Icons.person)),
              validator: (v) => (v ?? '').trim().length < 2 ? 'Adınızı girin' : null,
            ),
            const SizedBox(height: 12),
          ],
          TextFormField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'E-posta', prefixIcon: Icon(Icons.email)),
            validator: (v) => (v ?? '').contains('@') ? null : 'Geçerli bir e-posta girin',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: pass,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Şifre', prefixIcon: Icon(Icons.lock)),
            validator: (v) => (v ?? '').length < 8 ? 'En az 8 karakter' : null,
          ),
          if (register)
            CheckboxListTile(
              value: accepted,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (v) => setState(() => accepted = v ?? false),
              title: Wrap(children: [
                const Text('Kullanım koşullarını ve '),
                GestureDetector(
                  onTap: () => launchUrl(Uri.parse('https://kiyaslio.com/gizlilik')),
                  child: Text('Gizlilik Politikası', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                ),
                const Text("'nı kabul ediyorum."),
              ]),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy ? null : submit,
            child: busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Text(register ? 'Kayıt ol' : 'Giriş yap'),
          ),
          TextButton(
            onPressed: () => setState(() => register = !register),
            child: Text(register ? 'Zaten hesabım var' : 'Yeni hesap oluştur'),
          ),
        ]),
      ),
    );
  }
}
