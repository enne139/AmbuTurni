import 'dart:io';

/// True su Windows/Linux/macOS (dove il DB usa sqflite_common_ffi), false
/// su Android/iOS (sqflite nativo) e sul web.
bool get isDesktop =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// True su Android/iOS, false su desktop e sul web. Usato per i plugin che
/// esistono solo su mobile (es. add_2_calendar, nessun canale nativo per
/// desktop né implementazione web).
bool get isMobile => Platform.isAndroid || Platform.isIOS;
