import { Routes, Route } from 'react-router-dom';
import './App.css';
import Home from './pages/Home';
import Airlines from './pages/Airlines';
import Flights from './pages/Flights';
import Navigation from './components/Navigation';
import { getWebInstrumentations, initializeFaro } from '@grafana/faro-web-sdk';
import { TracingInstrumentation } from '@grafana/faro-web-tracing';
import { ReplayInstrumentation } from '@grafana/faro-instrumentation-replay';

// Backend origins that should receive the W3C traceparent header, so browser spans
// link to the Flights/Airlines traces.
const escapeRegExp = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const backendOrigins = [
  process.env.REACT_APP_AIRLINES_API_URL,
  process.env.REACT_APP_FLIGHTS_API_URL,
]
  .filter(Boolean)
  .map((url) => new RegExp('^' + escapeRegExp(new URL(url).origin)));

initializeFaro({
  url: process.env.REACT_APP_FARO_URL,
  app: {
    name: 'pov-sim-frontend',
    version: '1.0.0',
    environment: 'production'
  },
  instrumentations: [
    // Mandatory, omits default instrumentation otherwise.
    ...getWebInstrumentations(),
    // Tracing package to get end-to-end visibility for HTTP requests.
    new TracingInstrumentation({
      instrumentationOptions: {
        propagateTraceHeaderCorsUrls: backendOrigins,
      },
    }),
    // Session replay package to record user interactions
    new ReplayInstrumentation({
      maskTextSelector: '.grafana-mask, [contenteditable]',
      blockSelector: '.grafana-block, input[type="hidden"]',
      ignoreSelector: '.grafana-ignore'
    }),
  ],
});

function App() {
  return (
    <div className="App">
      <header className="App-header">
        <Navigation />
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/flights" element={<Flights />} />
          <Route path="/airlines" element={<Airlines />} />
        </Routes>
      </header>
    </div>
  );
}

export default App;
