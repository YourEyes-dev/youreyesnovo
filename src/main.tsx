import React from "react";
import { createRoot } from "react-dom/client";
import App from "./App.tsx";
import "./index.css";
import { instalarCapturaDeErros } from "./lib/telemetriaErros";

const abortMessagePattern = /signal is aborted without reason|AbortError/i;

if (typeof window !== "undefined") {
  window.addEventListener("unhandledrejection", (event) => {
    const reason = event.reason;
    const message = typeof reason === "string" ? reason : reason?.message;
    const name = typeof reason === "object" && reason ? reason.name : undefined;

    if (name === "AbortError" || abortMessagePattern.test(message ?? "")) {
      event.preventDefault();
    }
  });

  window.addEventListener("error", (event) => {
    const message = event.message || event.error?.message || "";
    const name = event.error?.name;

    if (name === "AbortError" || abortMessagePattern.test(message)) {
      event.preventDefault();
    }
  });
}

// Captura de erros da Central de Controle de Clientes: liga cedo, para
// pegar também o que quebra antes da primeira tela aparecer.
instalarCapturaDeErros();

createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
