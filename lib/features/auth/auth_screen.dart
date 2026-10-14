import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/session.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}
class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signup = false, _busy = false, _obscure = true;
  String? _message;
  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _busy = true; _message = null; });
    try {
      final client = ref.read(sessionProvider).client;
      if (_signup) {
        final response = await client.auth.signUp(email: _email.text.trim(), password: _password.text);
        if (mounted && response.session == null) {
          setState(() => _message = 'Check your email to confirm your account, then sign in.');
        }
      } else {
        await client.auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not connect. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  @override
  void dispose() { _email.dispose(); _password.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(child:
    SingleChildScrollView(padding: const EdgeInsets.all(28), child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440), child: Form(key: _form, child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Icon(Icons.favorite_rounded, size: 66, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 20),
          Text('Us', textAlign: TextAlign.center, style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: 8),
          const Text('A little space, just for two.', textAlign: TextAlign.center),
          const SizedBox(height: 36),
          Text(_signup ? 'Make yourself at home' : 'Welcome back', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 20),
          TextFormField(controller: _email, keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email], decoration: const InputDecoration(labelText: 'Email'),
            validator: (v) => v != null && RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v.trim()) ? null : 'Enter a valid email'),
          const SizedBox(height: 14),
          TextFormField(controller: _password, obscureText: _obscure,
            autofillHints: [_signup ? AutofillHints.newPassword : AutofillHints.password],
            decoration: InputDecoration(labelText: 'Password', suffixIcon: IconButton(
              tooltip: _obscure ? 'Show password' : 'Hide password',
              onPressed: () => setState(() => _obscure = !_obscure), icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off))),
            validator: (v) => v != null && v.length >= (_signup ? 8 : 1) ? null : 'Use at least 8 characters'),
          if (_message != null) Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(_message!)),
          const SizedBox(height: 24),
          FilledButton(onPressed: _busy ? null : _submit, child: _busy
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(_signup ? 'Create account' : 'Sign in')),
          TextButton(onPressed: _busy ? null : () => setState(() { _signup = !_signup; _message = null; }),
            child: Text(_signup ? 'Already have an account? Sign in' : 'New here? Create an account')),
        ],
      )),
    )),
  )));
}
