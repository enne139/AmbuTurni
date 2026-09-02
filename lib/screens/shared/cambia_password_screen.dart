import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../utils/backend_api.dart';
import '../../utils/theme.dart';

/// Pagina di cambio password volontario (Impostazioni → Account, pulsante
/// "Cambia password"): wrapper Scaffold+AppBar attorno a [CambiaPasswordForm].
/// Il caso forzato (primo login con la password provvisoria data dall'admin)
/// riusa [CambiaPasswordForm] direttamente, inline, da
/// widgets/accesso_richiesto.dart — niente Scaffold annidato lì, la cornice
/// la mette già il tool che ospita il contenuto riservato.
class CambiaPasswordScreen extends StatelessWidget {
  const CambiaPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cambia password')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: CambiaPasswordForm(forzato: false),
      ),
    );
  }
}

/// Form di cambio password, riusato nei due contesti sopra. Verifica sempre
/// la password attuale lato server (AccountProvider.cambiaPassword →
/// PUT /api/utenti/password), anche nel caso forzato: stesso schema di
/// sicurezza del login, nessuna scorciatoia solo perché il token è appena
/// stato emesso.
class CambiaPasswordForm extends StatefulWidget {
  final bool forzato;
  const CambiaPasswordForm({super.key, required this.forzato});

  @override
  State<CambiaPasswordForm> createState() => _CambiaPasswordFormState();
}

class _CambiaPasswordFormState extends State<CambiaPasswordForm> {
  final _formKey = GlobalKey<FormState>();
  final _attualeCtrl = TextEditingController();
  final _nuovaCtrl = TextEditingController();
  final _confermaCtrl = TextEditingController();
  bool _salvando = false;
  String? _errore;

  @override
  void dispose() {
    _attualeCtrl.dispose();
    _nuovaCtrl.dispose();
    _confermaCtrl.dispose();
    super.dispose();
  }

  Future<void> _salva() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _salvando = true;
      _errore = null;
    });
    try {
      await context.read<AccountProvider>().cambiaPassword(_attualeCtrl.text, _nuovaCtrl.text);
      // Caso forzato: AccountProvider.deveCambiarePassword torna false e
      // notifica i listener — AccessoRichiesto passa da solo al contenuto
      // vero, questo widget sparisce senza bisogno di alcuna navigazione.
      // Caso volontario: questa schermata è stata aperta con Navigator.push,
      // va chiusa esplicitamente con un feedback.
      if (!widget.forzato && mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password cambiata.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _salvando = false;
          _errore = messaggioErroreBackend(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.forzato) ...[
              const Icon(Icons.password_outlined, size: 40, color: Colors.white38),
              const SizedBox(height: 12),
              const Text(
                "La password è ancora quella provvisoria assegnata "
                "dall'amministratore: impostane una nuova per continuare.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
            ],
            TextFormField(
              controller: _attualeCtrl,
              enabled: !_salvando,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: 'Password attuale'),
              validator: (v) => (v == null || v.isEmpty) ? 'Campo richiesto' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nuovaCtrl,
              enabled: !_salvando,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(labelText: 'Nuova password (almeno 8 caratteri)'),
              validator: (v) => (v == null || v.length < 8) ? 'Almeno 8 caratteri' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confermaCtrl,
              enabled: !_salvando,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Conferma nuova password'),
              validator: (v) => v != _nuovaCtrl.text ? 'Le password non coincidono' : null,
            ),
            if (_errore != null) ...[
              const SizedBox(height: 12),
              Text(_errore!, style: const TextStyle(color: kPrimary, fontSize: 13)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _salvando ? null : _salva,
              style: FilledButton.styleFrom(backgroundColor: kPrimary),
              child: _salvando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Cambia password'),
            ),
            // Solo nel caso forzato: mai un vicolo cieco per chi non vuole
            // cambiarla adesso. Nel caso volontario si può già tornare
            // indietro con il pulsante dell'AppBar.
            if (widget.forzato) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: _salvando ? null : () => context.read<AccountProvider>().logout(),
                child: const Text('Esci'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
