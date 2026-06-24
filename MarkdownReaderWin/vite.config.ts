import { defineConfig } from "vite";

// Tauri expects a fixed dev port and a relative base so the production
// bundle loads correctly from the app's embedded asset server.
export default defineConfig({
  base: "./",
  clearScreen: false,
  server: {
    port: 5179,
    strictPort: true,
  },
  build: {
    target: "es2021",
    outDir: "dist",
    emptyOutDir: true,
    sourcemap: false,
  },
});
