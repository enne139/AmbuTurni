import 'package:flutter/material.dart';

/// Editor delle note a schermo intero: sostituisce il dialog piccolo
/// (AlertDialog con TextField a poche righe), troppo stretto per scrivere o
/// scorrere note lunghe, soprattutto ora che accettano markdown. Restituisce
/// il testo aggiornato al pop, o null se l'utente torna indietro senza salvare.
/// Condiviso tra il dettaglio turno e il dettaglio assistenza.
class NoteEditorScreen extends StatefulWidget {
  final String? notaIniziale;
  const NoteEditorScreen({super.key, this.notaIniziale});

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.notaIniziale ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _salva() => Navigator.pop(context, _ctrl.text.trim());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Note'),
        actions: [
          IconButton(icon: const Icon(Icons.check), tooltip: 'Salva', onPressed: _salva),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _ctrl,
          autofocus: true,
          expands: true,
          maxLines: null,
          minLines: null,
          textAlignVertical: TextAlignVertical.top,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(fontSize: 14),
          decoration: const InputDecoration(
            hintText: 'Note in markdown (es. **grassetto**, *corsivo*, - lista, # titolo)',
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }
}
