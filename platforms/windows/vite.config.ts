import { defineConfig } from "vite";

// Tauri expects a fixed dev port and a relative base so the production
// bundle loads correctly from the app's embedded asset server.
export default defineConfig({
  base: "./",
  clearScreen: false,
  server: {
    // Bind IPv4 explicitly. On Windows, `localhost` can resolve to IPv6 (::1)
    // while the Tauri dev-server probe connects over IPv4 (127.0.0.1), which
    // makes `tauri dev` hang on "Waiting for your frontend dev server".
    host: "127.0.0.1",
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
