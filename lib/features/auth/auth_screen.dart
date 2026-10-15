import 'dart:async';

import '../../core/auth_links.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/session.dart';
import '../../core/design.dart';

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
  StreamSubscription<String>? _linkErrors;
  @override
  void initState() {
    super.initState();
    _linkErrors = AuthLinks.errors.stream.listen((message) {
      if (mounted)
        setState(() {
          _message = message;
          _busy = false;
        });
    });
  }

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final opened = await ref
          .read(sessionProvider)
          .client
          .auth
          .signInWithOAuth(
            OAuthProvider.google,
            redirectTo: AuthLinks.redirect,
            authScreenLaunchMode: LaunchMode.externalApplication,
          );
      if (!opened) throw StateError('Browser unavailable');
      if (mounted)
        setState(
          () => _message = 'Finish signing in with Google, then return to Us.',
        );
    } on AuthException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (_) {
      if (mounted)
        setState(
          () => _message = 'Could not open Google sign-in. Please try again.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final email = _email.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _message = 'Enter your email address first.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref
          .read(sessionProvider)
          .client
          .auth
          .resend(
            type: OtpType.signup,
            email: email,
            emailRedirectTo: 'com.jerrish18.us://login-callback',
          );
      if (mounted)
        setState(
          () => _message =
              'Check your inbox and spam folder for the confirmation email.',
        );
    } on AuthException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (_) {
      if (mounted)
        setState(() => _message = 'Could not resend. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final client = ref.read(sessionProvider).client;
      if (_signup) {
        final response = await client.auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          emailRedirectTo: 'com.jerrish18.us://login-callback',
        );
        if (mounted && response.session == null) {
          setState(
            () => _message =
                'Check your email to confirm your account, then sign in.',
          );
        }
      } else {
        await client.auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (_) {
      if (mounted)
        setState(() => _message = 'Could not connect. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _linkErrors?.cancel();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: UsTokens.page,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: UsTokens.s440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PageEntrance(
                  child: TintedTile(
                    accent: Accent.pink,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Us',
                                style: TextStyle(
                                  fontSize: UsTokens.s56,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -2,
                                ),
                              ),
                              Text('A little space, just for two.'),
                            ],
                          ),
                        ),
                        FlowerBadge(accent: Accent.coral, size: UsTokens.s80),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: UsTokens.s24),
                GlassCard(
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _signup ? 'Make yourself at home' : 'Welcome back',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: UsTokens.s20),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _google,
                          icon: const Icon(Icons.account_circle_rounded),
                          label: const Text('Continue with Google'),
                        ),
                        const SizedBox(height: UsTokens.s16),
                        const Center(child: Text('or use your email')),
                        const SizedBox(height: UsTokens.s16),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.alternate_email_rounded),
                          ),
                          validator: (v) =>
                              v != null &&
                                  RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                      .hasMatch(v.trim())
                              ? null
                              : 'Enter a valid email',
                        ),
                        const SizedBox(height: UsTokens.s12),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          autofillHints: [
                            _signup
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              tooltip: _obscure
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_rounded
                                    : Icons.visibility_off_rounded,
                              ),
                            ),
                          ),
                          validator: (v) =>
                              v != null && v.length >= (_signup ? 8 : 1)
                              ? null
                              : 'Use at least 8 characters',
                        ),
                        if (_message != null)
                          Padding(
                            padding: const EdgeInsets.only(top: UsTokens.s16),
                            child: Text(_message!),
                          ),
                        const SizedBox(height: UsTokens.s24),
                        ExpressiveButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  width: UsTokens.s24,
                                  height: UsTokens.s24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(_signup ? 'Create account' : 'Sign in'),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _signup = !_signup;
                                  _message = null;
                                }),
                          child: Text(
                            _signup
                                ? 'Already have an account? Sign in'
                                : 'New here? Create an account',
                          ),
                        ),
                        TextButton(
                          onPressed: _busy ? null : _resend,
                          child: const Text('Resend confirmation email'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: UsTokens.s24),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
