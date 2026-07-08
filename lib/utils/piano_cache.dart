// Cache locale del Piano turni: un piano decodificato per mese. Serve a
// mostrare subito l'ultimo piano all'apertura del tool (anche offline):
// l'endpoint export di Google genera l'XLSX al momento e il package excel
// decodifica l'intero workbook — insieme costano diversi secondi a ogni
// caricamento, per dati che tra un'apertura e l'altra quasi non cambiano. Il
// download resta comunque: la cache è solo la prima cosa mostrata, i dati
// freschi la sostituiscono.
//
// Due backend a seconda della piattaforma (mai dart:io in questo file: deve
// restare compilabile anche sul target web, l'import condizionale sceglie
// piano_cache_io.dart fuori dal web): file JSON per mese nella directory di
// supporto su Android/desktop (piano_cache_io.dart), shared_preferences
// (localStorage del browser) su web (piano_cache_web.dart) perché
// path_provider non ha lì una directory persistente utilizzabile allo stesso modo.
export 'piano_cache_web.dart' if (dart.library.io) 'piano_cache_io.dart';
