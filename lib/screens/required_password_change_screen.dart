import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/localization/ui_strings.dart';

class RequiredPasswordChangeScreen extends StatefulWidget {
  const RequiredPasswordChangeScreen({super.key});

  @override
  State<RequiredPasswordChangeScreen> createState() =>
      _RequiredPasswordChangeScreenState();
}

class _RequiredPasswordChangeScreenState
    extends State<RequiredPasswordChangeScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String _error = '';

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_password.text.length < 8) {
      setState(() => _error = 'Use at least 8 characters.');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final client = Supabase.instance.client;
      final response = await client.functions.invoke(
        'fpc-user-admin',
        headers: {
          'Authorization':
              'Bearer ${client.auth.currentSession?.accessToken ?? ''}',
        },
        body: {'action': 'change_password', 'password': _password.text},
      );
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : const <String, dynamic>{};
      if (data['success'] == false) {
        throw Exception('${data['error'] ?? 'Password change failed.'}');
      }
      await client.auth.refreshSession();
      final role = '${client.auth.currentUser?.appMetadata['role'] ?? ''}'
          .toLowerCase();
      Get.offAllNamed(role == 'field_officer' ? '/field' : '/fpo');
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.password_rounded, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    UiStrings.fromEnglish('Create your permanent password'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    UiStrings.fromEnglish(
                      'Your temporary password can be used only for the first login.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: UiStrings.fromEnglish('New password'),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirm,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: UiStrings.fromEnglish('Confirm password'),
                    ),
                  ),
                  if (_error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _loading ? null : _save,
                    child: Text(_loading ? 'Saving…' : 'Save and continue'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
