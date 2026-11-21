import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session.dart';
import '../../core/widgets.dart';
import '../legal/legal.dart';

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
  bool register = true, busy = false, accepted = false, adult = false, aiConsent = false;

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    if (register && !accepted) return toast(context, 'Devam etmek için Kullanım Koşulları ve Gizlilik Politikası\'nı onaylayın');
    if (register && !adult) return toast(context, 'Ucuza.com\'u kullanmak için 18 yaşından büyük olmalısınız');
    setState(() => busy = true);
    try {
      final a = ref.read(authProvider.notifier);
      register
          ? await a.register(email.text.trim(), pass.text, name.text.trim(), widget.interests,
              acceptTerms: accepted, ageConfirmed: adult, aiConsent: aiConsent)
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
          if (register) ...[
            CheckboxListTile(
              value: accepted,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (v) => setState(() => accepted = v ?? false),
              title: const Wrap(children: [
                LegalLink('kosullar'),
                Text("'nı ve "),
                LegalLink('gizlilik', label: 'Gizlilik Politikası / Aydınlatma Metni'),
                Text("'ni okudum, kabul ediyorum. (Zorunlu)"),
              ]),
            ),
            CheckboxListTile(
              value: adult,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (v) => setState(() => adult = v ?? false),
              title: const Text('18 yaşından büyüğüm. (Zorunlu)'),
            ),
            CheckboxListTile(
              value: aiConsent,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (v) => setState(() => aiConsent = v ?? false),
              title: const Wrap(children: [
                Text('Yorumlarımın, asistan mesajlarımın ve yüklediğim videoların yapay zeka analizi için yurt dışına '
                    'aktarılmasına '),
                LegalLink('acik-riza', label: 'açık rıza'),
                Text(' veriyorum. (İsteğe bağlı — sonra Profil\'den değiştirebilirsiniz)'),
              ]),
            ),
          ],
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
