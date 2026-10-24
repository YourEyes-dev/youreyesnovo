import { defineConfig, loadEnv } from "vite";
import react from "@vitejs/plugin-react-swc";
import path from "path";
import fs from "fs";
import { componentTagger } from "lovable-tagger";

/** Projeto Supabase de PRODUÇÃO. Nenhum outro ambiente pode apontar para ele. */
const PROJETO_PRODUCAO = "diayjpsrcerycycyaxst";

/**
 * Trava de ambiente.
 *
 * O acidente que ela impede é específico e caro: um build de teste ou de
 * homologação apontando para o banco de produção. Não é hipótese — o
 * .env.staging traz o aviso escrito ("NUNCA aponte para a URL de produção:
 * os links de convite e redefinição de senha gerados no staging levariam o
 * usuário para o app real"), e aviso em comentário só protege quem lê.
 *
 * Com três ambientes o risco cresce: são três arquivos parecidos, e copiar
 * um para começar o outro é o caminho natural. Aqui o build simplesmente
 * não nasce.
 */
function exigirAmbienteCoerente(mode: string, env: Record<string, string>) {
  if (mode === "production" || mode === "development") return;

  const url = env.VITE_SUPABASE_URL ?? "";
  if (url.includes(PROJETO_PRODUCAO)) {
    throw new Error(
      `[ambiente] O build "${mode}" está apontando para o Supabase de PRODUÇÃO ` +
        `(${PROJETO_PRODUCAO}). Corrija VITE_SUPABASE_URL em .env.${mode} antes de continuar. ` +
        `Publicar um ambiente de teste sobre o banco real é o acidente que esta trava existe para impedir.`,
    );
  }
}


/**
 * Arquivos WASM do MediaPipe (verificação de presença do EPI).
 *
 * Não ficam no repositório (~19 MB): saem de node_modules e são copiados para o
 * build, em `mediapipe/wasm`, na pasta de saída de CADA build (teste, homologação
 * e produção usam saídas e subcaminhos diferentes). No desenvolvimento, o servidor
 * os entrega direto de node_modules. O modelo (.task) fica em public/mediapipe.
 */
function copiarMediapipe() {
  const origem = path.resolve(__dirname, "node_modules/@mediapipe/tasks-vision/wasm");
  let saida = path.resolve(__dirname, "dist");
  return {
    name: "copiar-mediapipe-wasm",
    configResolved(config: { root: string; build: { outDir: string } }) {
      saida = path.resolve(config.root, config.build.outDir);
    },
    configureServer(server: { middlewares: { use: (rota: string, fn: (req: { url?: string }, res: { setHeader: (k: string, v: string) => void; end: (b?: Buffer) => void; statusCode: number }, next: () => void) => void) => void } }) {
      server.middlewares.use("/mediapipe/wasm", (req, res, next) => {
        const nome = path.basename((req.url || "").split("?")[0]);
        const arquivo = path.join(origem, nome);
        if (!nome || !fs.existsSync(arquivo)) return next();
        res.setHeader("Content-Type", nome.endsWith(".wasm") ? "application/wasm" : "text/javascript");
        res.end(fs.readFileSync(arquivo));
      });
    },
    closeBundle() {
      if (!fs.existsSync(origem)) return;
      const destino = path.join(saida, "mediapipe", "wasm");
      fs.mkdirSync(destino, { recursive: true });
      for (const nome of fs.readdirSync(origem)) {
        fs.copyFileSync(path.join(origem, nome), path.join(destino, nome));
      }
    },
  };
}

// https://vitejs.dev/config/
export default defineConfig(({ mode }) => {
  exigirAmbienteCoerente(mode, loadEnv(mode, process.cwd(), ""));
  return {
  server: {
    host: "::",
    port: 8080,
    hmr: {
      overlay: false,
    },
  },
  plugins: [react(), mode === "development" && componentTagger(), copiarMediapipe()].filter(Boolean),
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
    dedupe: ["react", "react-dom", "react/jsx-runtime"],
  },
  optimizeDeps: {
    include: ["react", "react-dom", "@tanstack/react-query", "react/jsx-runtime"],
    force: true,
  },
  build: {
    commonjsOptions: {
      include: [/node_modules/],
    },
  },
  define: {
    "import.meta.env.VITE_APP_BUILD_TIME": JSON.stringify(new Date().toISOString()),
    // Versão base vem do package.json (fonte única da verdade).
    // Builds fora de produção ganham sufixo de pré-lançamento (SemVer),
    // ex.: 1.0.0-teste.20260817 — mesma base, origem inconfundível.
    //
    // O modo `staging` carimbava "homolog", de quando havia dois ambientes e
    // os nomes eram intercambiáveis. Com a homologação existindo de verdade,
    // o rótulo passou a apontar para o ambiente errado: quem lesse
    // "1.0.0-homolog" num relatório de bug estaria olhando o de TESTE.
    "import.meta.env.VITE_APP_VERSION": JSON.stringify(
      (() => {
        const base = process.env.npm_package_version || "1.0.0";
        if (mode === "production") return base;
        const carimbo = new Date().toISOString().slice(0, 10).replace(/-/g, "");
        const rotulo =
          mode === "staging" ? "teste" : mode === "homologacao" ? "homolog" : mode;
        return `${base}-${rotulo}.${carimbo}`;
      })(),
    ),
    },
  };
});
