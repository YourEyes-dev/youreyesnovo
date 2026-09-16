import React, { Component, ErrorInfo } from "react";
import { AlertTriangle, RefreshCw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { registrarErro } from "@/lib/telemetriaErros";

interface Props {
  children: React.ReactNode;
  fallback?: React.ReactNode;
}

interface State {
  hasError: boolean;
  error: Error | null;
}

/**
 * Traduz mensagens de erro técnicas (geralmente em inglês) para uma
 * explicação clara em português, compreensível por usuário leigo.
 * Retorna null quando não há tradução conhecida.
 */
export function explicarErro(message: string): string | null {
  const m = (message || "").toLowerCase();
  if (m.includes("select.item") && m.includes("empty string")) {
    return "A planilha tem uma coluna sem nome no cabeçalho. Dê um nome a todas as colunas (ou remova as colunas vazias) e tente importar novamente.";
  }
  if (m.includes("planilha vazia")) {
    return "A planilha está vazia ou não tem linhas de dados. Verifique o arquivo e tente novamente.";
  }
  if (m.includes("network") || m.includes("failed to fetch")) {
    return "Falha de conexão. Verifique sua internet e tente novamente.";
  }
  if (m.includes("chunk") && m.includes("load")) {
    return "Uma atualização do sistema foi publicada. Recarregue a página para carregar a versão mais recente.";
  }
  return null;
}

export class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error("[ErrorBoundary]", error, errorInfo);
    // Tela que quebrou na cara do cliente é o caso mais grave: vai para a
    // Central como crítico. O envio nunca lança (ver telemetriaErros).
    void registrarErro({
      mensagem: error.message,
      stack: `${error.stack ?? ""}\n${errorInfo.componentStack ?? ""}`,
      tipo: error.name || "Error",
      acao: "tela quebrou (ErrorBoundary)",
      severidade: "critica",
    });
  }

  handleReset = () => {
    this.setState({ hasError: false, error: null });
  };

  render() {
    if (this.state.hasError) {
      if (this.props.fallback) return this.props.fallback;

      const amigavel = this.state.error ? explicarErro(this.state.error.message) : null;

      return (
        <div className="min-h-screen flex items-center justify-center bg-background p-6">
          <div className="max-w-md w-full text-center space-y-6">
            <div className="mx-auto w-16 h-16 rounded-full bg-destructive/10 flex items-center justify-center">
              <AlertTriangle className="w-8 h-8 text-destructive" />
            </div>
            <div className="space-y-2">
              <h1 className="text-2xl font-bold text-foreground">
                Algo deu errado
              </h1>
              <p className="text-muted-foreground text-sm">
                {amigavel || "Ocorreu um erro inesperado. Tente recarregar a página."}
              </p>
            </div>
            {this.state.error && (
              <details className="text-left">
                <summary className="text-xs text-muted-foreground cursor-pointer select-none">
                  Detalhes técnicos
                </summary>
                <pre className="text-xs text-left bg-muted p-3 rounded-lg overflow-auto max-h-32 text-muted-foreground mt-2">
                  {this.state.error.message}
                </pre>
              </details>
            )}
            <div className="flex gap-3 justify-center">
              <Button variant="outline" onClick={this.handleReset}>
                <RefreshCw className="w-4 h-4 mr-2" />
                Tentar novamente
              </Button>
              <Button onClick={() => window.location.reload()}>
                Recarregar página
              </Button>
            </div>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}
