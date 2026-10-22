import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { EpiForm } from "@/components/epi/EpiForm";
import type { EpiCompleto } from "@/types/epi";

// O Switch do Radix mede o próprio tamanho; o jsdom não tem ResizeObserver.
globalThis.ResizeObserver ??= class {
  observe() {}
  unobserve() {}
  disconnect() {}
} as unknown as typeof ResizeObserver;

vi.mock("@/hooks/useEpiLocais", () => ({
  useEpiLocais: () => ({ locaisAtivos: [] }),
}));

// A consulta de CA duplicado do formulário: cadeia que termina sem achar nada.
vi.mock("@/integrations/supabase/client", () => {
  const cadeia: Record<string, unknown> = {};
  for (const m of ["select", "eq", "neq", "limit"]) cadeia[m] = () => cadeia;
  cadeia.maybeSingle = () => Promise.resolve({ data: null, error: null });
  return { supabase: { from: () => cadeia } };
});

const epi = {
  id: "epi-1",
  tipo_id: "tipo-1",
  tenant_id: "t-1",
  ca: "12345",
  codigo: "LOTE-1",
  marca: "3M",
  modelo: "X1",
  data_fabricacao: null,
  data_validade: "2030-01-01",
  quantidade_estoque: 10,
  quantidade_minima: 5,
  custo_unitario: null,
  localizacao: null,
  observacoes: null,
  tipo: {
    id: "tipo-1",
    nome: "Protetor Auricular",
    categoria: "Proteção Auditiva",
    unidade_medida: "unidade",
    tipo_durabilidade: "duravel",
    periodicidade_troca_dias: 180,
    fabricante: "3M do Brasil",
    controla_tamanho: false,
  },
} as unknown as EpiCompleto;

function montar(extra: Partial<React.ComponentProps<typeof EpiForm>> = {}) {
  const props = {
    open: true,
    onOpenChange: vi.fn(),
    onSubmit: vi.fn().mockResolvedValue(undefined),
    onCreateTipo: vi.fn().mockResolvedValue(undefined),
    tipos: [],
    ...extra,
  };
  render(<EpiForm {...props} />);
  return props;
}

describe("EpiForm: edição x cadastro", () => {
  beforeEach(() => vi.clearAllMocks());

  it("editar chama onSubmit com o que é de cada tabela e NÃO cadastra outro EPI", async () => {
    const props = montar({ epi });
    fireEvent.change(screen.getByPlaceholderText(/Protetor Auricular/), {
      target: { value: "Protetor Auricular Plus" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Salvar Alterações" }));

    await waitFor(() => expect(props.onSubmit).toHaveBeenCalledTimes(1));
    expect(props.onCreateTipo).not.toHaveBeenCalled();

    const payload = props.onSubmit.mock.calls[0][0];
    expect(payload.tipo.nome).toBe("Protetor Auricular Plus");
    expect(payload.tipo.ca_numero).toBe("12345");
    expect(payload.tipo.ca_validade).toBe("2030-01-01");
    expect(payload.epi.ca).toBe("12345");
    expect(payload.epi.quantidade_minima).toBe(5);
    // Estoque não é editável aqui: muda por Ajustar Estoque, com motivo.
    expect(payload.epi).not.toHaveProperty("quantidade_estoque");
    expect(props.onOpenChange).toHaveBeenCalledWith(false);
  });

  it("na edição a quantidade em estoque fica travada", () => {
    montar({ epi });
    const campos = screen.getAllByRole("spinbutton") as HTMLInputElement[];
    expect(campos.some((c) => c.disabled && c.value === "10")).toBe(true);
  });

  it("se a gravação da edição falhar, o formulário continua aberto", async () => {
    const onSubmit = vi.fn().mockRejectedValue(new Error("falhou"));
    const props = montar({ epi, onSubmit });
    vi.spyOn(console, "error").mockImplementation(() => {});
    fireEvent.click(screen.getByRole("button", { name: "Salvar Alterações" }));
    await waitFor(() => expect(onSubmit).toHaveBeenCalled());
    expect(props.onOpenChange).not.toHaveBeenCalledWith(false);
  });

  it("na edição somem a grade de tamanho e o local; no cadastro novo continuam", () => {
    const { unmount } = render(
      <EpiForm open onOpenChange={vi.fn()} onSubmit={vi.fn()} onCreateTipo={vi.fn()} tipos={[]} epi={epi} />
    );
    expect(screen.queryByText("Controlar por Tamanho")).toBeNull();
    expect(screen.queryByText("Local de Estoque")).toBeNull();
    unmount();

    montar({ epi: null });
    expect(screen.getByText("Cadastrar Novo EPI")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Cadastrar" })).toBeInTheDocument();
    expect(screen.getByText("Controlar por Tamanho")).toBeInTheDocument();
    expect(screen.getByText("Local de Estoque")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Salvar Alterações" })).toBeNull();
  });
});
