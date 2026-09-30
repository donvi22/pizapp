import 'package:flutter/material.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onLogin, required this.onRegister});

  final Future<void> Function(String username, String password) onLogin;
  final Future<void> Function(String username, String email, String password) onRegister;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailController = TextEditingController();
  bool _registering = false;
  bool _hidePassword = true;

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_registering) {
        await widget.onRegister(
          _usernameController.text.trim(),
          _emailController.text.trim(),
          _passwordController.text,
        );
      } else {
        await widget.onLogin(_usernameController.text.trim(), _passwordController.text);
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error is Exception
            ? error.toString().replaceFirst('Exception: ', '')
            : 'No se pudo conectar con el servidor.';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Pizapp',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _registering ? 'Crea tu cuenta' : 'Accede a tus proyectos',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _usernameController,
                    enabled: !_loading,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(
                      labelText: 'Usuario',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        value == null || value.trim().isEmpty
                            ? 'Escribe tu usuario'
                            : null,
                  ),
                  const SizedBox(height: 16),
                  if (_registering) ...[
                    TextFormField(
                      controller: _emailController,
                      enabled: !_loading,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Correo electrónico', border: OutlineInputBorder(),
                      ),
                      validator: (value) => value == null ||
                          !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())
                          ? 'Escribe un correo válido' : null,
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _passwordController,
                    enabled: !_loading,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    obscureText: _hidePassword,
                    autofillHints: [_registering ? AutofillHints.newPassword : AutofillHints.password],
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: _hidePassword ? 'Mostrar contraseña' : 'Ocultar contraseña',
                        onPressed: _loading ? null : () => setState(() => _hidePassword = !_hidePassword),
                        icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      ),
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty
                            ? 'Escribe tu contraseña'
                            : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_registering ? 'Crear cuenta' : 'Entrar'),
                    ),
                  ),
                  TextButton(
                    onPressed: _loading ? null : () => setState(() {
                      _registering = !_registering;
                      _hidePassword = true;
                      _error = null;
                    }),
                    child: Text(_registering ? 'Ya tengo cuenta' : 'Crear una cuenta'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
