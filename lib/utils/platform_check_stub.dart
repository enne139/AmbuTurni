/// Versione web: mai desktop nativo (il DB qui usa sqflite_common_ffi_web,
/// selezionato altrove tramite kIsWeb, non da questo controllo).
bool get isDesktop => false;

/// Versione web: mai mobile nativo (niente canale platform per Android/iOS).
bool get isMobile => false;
