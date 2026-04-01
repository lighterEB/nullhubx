import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [sveltekit()],
  build: {
    // Preserve the server bundle between SvelteKit's SSR and client passes.
    emptyOutDir: false
  },
  server: {
    proxy: {
      '/api': 'http://127.0.0.1:19800'
    }
  }
});
