import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/app_provider.dart';
import '../../utils/backend_api.dart';
import '../../utils/prefs_keys.dart';
import '../../utils/theme.dart';
import '../../widgets/accesso_richiesto.dart';

/// Tool "Repository formazione": un solo link condiviso (impostato
/// dall'admin sul backend condiviso, non configurabile qui) ai materiali di
/// formazione dell'associazione, aperto nel browser esterno. CONTENUTO
/// RISERVATO (vedi CLAUDE.md): il body è avvolto in AccessoRichiesto, che
/// mostra il login (o il cambio password obbligatorio) finché l'utente non
/// è autenticato.
class RepositoryFormazioneScreen extends StatelessWidget {
  const RepositoryFormazioneScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Repository formazione')),
      // Il Center/Padding avvolge solo il contenuto vero (post-login): gli
      // stati di login/cambio password si centrano già da soli dentro
      // AccessoRichiesto, avvolgerli anche qui raddoppierebbe solo il padding.
      body: AccessoRichiesto(
        builder: (context, token) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _RepositoryFormazioneContenuto(token: token),
          ),
        ),
      ),
    );
  }
}

/// Contenuto vero del tool, mostrato solo a login effettuato — non un
/// semplice redirect invisibile: se il link non è ancora configurato o il
/// server non risponde l'utente deve vedere un messaggio, non restare
/// bloccato su una schermata bianca, per questo resta uno stato vero con un
/// pulsante per riaprire il link a piacere.
class _RepositoryFormazioneContenuto extends StatefulWidget {
  final String token;
  const _RepositoryFormazioneContenuto({required this.token});

  @override
  State<_RepositoryFormazioneContenuto> createState() => _RepositoryFormazioneContenutoState();
}

class _RepositoryFormazioneContenutoState extends State<_RepositoryFormazioneContenuto> {
  bool _loading = true;
  String? _url;
  String? _errore;
  // Il link si apre da solo al primo caricamento riuscito, non ad ogni
  // "Riprova": altrimenti un utente che ricarica per un errore di rete si
  // ritroverebbe con un secondo tentativo di apertura del browser che non
  // ha chiesto.
  bool _apertoAutomaticamente = false;

  @override
  void initState() {
    super.initState();
    _carica();
  }

  Future<void> _carica() async {
    setState(() {
      _loading = true;
      _errore = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString(kPrefBackendUrl) ?? kBackendUrlDefault;
      final url = await BackendApi(baseUrl: baseUrl).getRepositoryFormazione(token: widget.token);
      if (!mounted) return;
      setState(() {
        _url = url;
        _loading = false;
      });
      if (url != null && !_apertoAutomaticamente) {
        _apertoAutomaticamente = true;
        _apri();
      }
    } catch (e) {
      if (!mounted) return;
      // Token scaduto/revocato: logout automatico invece di un errore
      // generico con un "Riprova" destinato a fallire di nuovo per sempre.
      // AccountProvider.logout() notifica AccessoRichiesto, che rimonta il
      // form di login al posto di questo widget — nessun setState locale da
      // fare qui, il widget sta per essere sostituito.
      if (e is BackendApiUnauthorized) {
        context.read<AccountProvider>().logout();
        return;
      }
      setState(() {
        _loading = false;
        _errore = messaggioErroreBackend(e);
      });
    }
  }

  Future<void> _apri() async {
    final url = _url;
    if (url == null) return;
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibile aprire il link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _loading ? const CircularProgressIndicator() : _contenuto();
  }

  Widget _contenuto() {
    if (_errore != null) {
      return _Messaggio(
        icona: Icons.wifi_off,
        testo: 'Impossibile contattare il server condiviso.\n$_errore',
        pulsante: OutlinedButton(onPressed: _carica, child: const Text('Riprova')),
      );
    }
    if (_url == null) {
      return const _Messaggio(
        icona: Icons.info_outline,
        testo: 'Nessun repository di formazione configurato.\n'
            'Chiedi a un amministratore di impostare il link dalla pagina admin del backend condiviso.',
      );
    }
    return _Messaggio(
      icona: Icons.school_outlined,
      iconaColore: kPrimary,
      testo: 'Il repository si apre nel browser.',
      pulsante: FilledButton.icon(
        onPressed: _apri,
        icon: const Icon(Icons.open_in_new),
        label: const Text('Apri di nuovo'),
        style: FilledButton.styleFrom(backgroundColor: kPrimary),
      ),
    );
  }
}

class _Messaggio extends StatelessWidget {
  final IconData icona;
  // Nullable (non un default costante) perché il colore "attenuato" di
  // default dipende dal tema attivo, noto solo a runtime tramite BuildContext.
  final Color? iconaColore;
  final String testo;
  final Widget? pulsante;

  const _Messaggio({
    required this.icona,
    this.iconaColore,
    required this.testo,
    this.pulsante,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icona, size: 48, color: iconaColore ?? coloreTesto(context, 0.38)),
        const SizedBox(height: 16),
        Text(testo, textAlign: TextAlign.center, style: TextStyle(color: coloreTesto(context, 0.7))),
        if (pulsante != null) ...[
          const SizedBox(height: 20),
          pulsante!,
        ],
      ],
    );
  }
}
