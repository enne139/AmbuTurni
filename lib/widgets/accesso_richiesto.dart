import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../screens/shared/cambia_password_screen.dart';
import '../utils/backend_api.dart';
import '../utils/theme.dart';

/// Avvolge un contenuto riservato (tool Repository formazione, Archivio
/// comunicati): mostra il form di login se non si è autenticati, il cambio
/// password obbligatorio se la password è ancora quella provvisoria data
/// dall'admin, altrimenti [builder] con il token da passare alle chiamate
/// API. Nessuno Scaffold/AppBar propri: il chiamante (una screens/tools/*)
/// fornisce già la sua cornice con il titolo del tool, questo widget riempie
/// solo il body — evita che l'utente debba fare un giro da Impostazioni per
/// sbloccare il contenuto che ha appena aperto.
class AccessoRichiesto extends StatelessWidget {
  final Widget Function(BuildContext context, String token) builder;
  const AccessoRichiesto({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountProvider>();
    if (!account.caricato) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!account.loggedIn) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: LoginForm(),
        ),
      );
    }
    if (account.deveCambiarePassword) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: CambiaPasswordForm(forzato: true),
      );
    }
    return builder(context, account.token!);
  }
}

/// Form di login condiviso tra [AccessoRichiesto] e la sezione Account di
/// Impostazioni (stesso campo, stesso comportamento, evita di duplicarlo).
/// Le credenziali sono create SOLO dalla pagina admin del backend condiviso
/// (mai da questa app): qui si può solo accedere con quelle già ricevute.
class LoginForm extends StatefulWidget {
  const LoginForm({super.key});

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _accedendo = false;
  String? _errore;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _accedi() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _accedendo = true;
      _errore = null;
    });
    try {
      await context.read<AccountProvider>().login(_usernameCtrl.text.trim(), _passwordCtrl.text);
      // Nessuna navigazione da fare qui: AccountProvider.login() notifica i
      // listener, AccessoRichiesto (o la sezione Account) si aggiorna da sé.
    } catch (e) {
      if (mounted) {
        setState(() {
          _accedendo = false;
          _errore = messaggioErroreBackend(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.lock_outline, size: 40, color: coloreTesto(context, 0.38)),
          const SizedBox(height: 12),
          Text(
            "Contenuto riservato: accedi con le credenziali fornite dall'associazione.",
            textAlign: TextAlign.center,
            style: TextStyle(color: coloreTesto(context, 0.7)),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _usernameCtrl,
            enabled: !_accedendo,
            autofillHints: const [AutofillHints.username],
            decoration: const InputDecoration(labelText: 'Utente'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo richiesto' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordCtrl,
            enabled: !_accedendo,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(labelText: 'Password'),
            validator: (v) => (v == null || v.isEmpty) ? 'Campo richiesto' : null,
            onFieldSubmitted: (_) => _accedi(),
          ),
          if (_errore != null) ...[
            const SizedBox(height: 12),
            Text(_errore!, style: const TextStyle(color: kPrimary, fontSize: 13)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _accedendo ? null : _accedi,
            style: FilledButton.styleFrom(backgroundColor: kPrimary),
            child: _accedendo
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Accedi'),
          ),
        ],
      ),
    );
  }
}
