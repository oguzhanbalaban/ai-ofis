import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Backend 127.0.0.1:8000'de çalışır. (AI Ekip paneli 8765-8774 aralığını kullanır; oraya dokunmuyoruz.)
const BACKEND = process.env.MASAL_BACKEND || 'http://127.0.0.1:8000'

export default defineConfig({
  plugins: [react()],
  server: {
    host: '127.0.0.1',
    port: 5173,
    strictPort: true,
    proxy: {
      '/api': BACKEND,
      '/media': BACKEND,
      '/ws': { target: BACKEND.replace(/^http/, 'ws'), ws: true },
    },
  },
  build: { outDir: 'dist', emptyOutDir: true },
})
