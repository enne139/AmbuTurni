// Astrazione minima su Platform.isX di dart:io: su web l'import diretto di
// dart:io non compila (non è un'eccezione a runtime, è un errore del
// compilatore), quindi ogni file che deve distinguere desktop/mobile senza
// rompere la build web passa da qui invece di importare dart:io direttamente.
// Import condizionale: platform_check_io.dart (usa dart:io) su Android/desktop,
// platform_check_stub.dart (nessun dart:io) sul target web.
export 'platform_check_stub.dart' if (dart.library.io) 'platform_check_io.dart';
