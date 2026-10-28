import { defineConfig } from 'vite';
export default defineConfig({
  base: './',
  // WKWebView loads the bundled page with file://. A single classic script
  // avoids module-origin/CORS restrictions while keeping all resources offline.
  build: { target: 'safari17', rollupOptions: { output: { format: 'iife', inlineDynamicImports: true } } },
  plugins: [{
    name: 'offline-classic-script',
    apply: 'build',
    transformIndexHtml: {
      order: 'post',
      handler: html => html.replace(/ type="module"/g, ' defer').replace(/ crossorigin/g, '')
    }
  }]
});
