// Punto di importazione unico per il salvataggio/lettura di un file
// testuale scelto dall'utente (backup JSON, ma anche l'export .ics del Piano
// turni: salvaFilePiattaforma è generica, testo + nome file). backup.dart e
// gli altri chiamanti non devono mai importare dart:io direttamente (non
// compila sul target web), quindi la parte che tocca il filesystem/il
// picker vive in due implementazioni alternative, scelte in automatico in
// base alla piattaforma di compilazione — non da un if a runtime, che non
// basterebbe: l'import di dart:io in backup_file_io.dart farebbe fallire la
// build web anche se quel ramo di codice non venisse mai eseguito.
export 'backup_file_web.dart' if (dart.library.io) 'backup_file_io.dart';
