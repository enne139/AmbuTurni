// Punto di ingresso registrato in package.json ("main": "index.ts").
import { registerRootComponent } from 'expo';
import App from './App';

// registerRootComponent chiama AppRegistry.registerComponent('main', () => App)
// e gestisce sia l'ambiente Expo Go sia le build native.
registerRootComponent(App);
