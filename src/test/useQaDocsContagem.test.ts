import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { createElement, type ReactNode } from "react";

// ============================================================
// Regressão: a contagem de casos por módulo na árvore da
// Documentação de Testes.
//
// A leitura antiga trazia qa_casos_teste de uma vez só. A API corta a
// resposta em 1.000 linhas, e a documentação já passou disso — os módulos
// cujas linhas caíam fora da primeira página vinham com contagem zero e
// PERDIAM o número na árvore. Zero por truncamento se lê como "módulo sem
// casos", que é a conclusão errada.
//
// O teste monta 1.059 linhas: 1.000 do módulo antigo e 59 do módulo novo
// (os de Usuários & Permissões, que foi onde o defeito apareceu). Só passa
// se a leitura buscar a segunda página.
// ============================================================

const MODULO_ANTIGO = "modulo-antigo";
const MODULO_NOVO = "modulo-novo";

const linhas = [
  ...Array.from({ length: 1000 }, () => ({ modulo_id: MODULO_ANTIGO })),
  ...Array.from({ length: 59 }, () => ({ modulo_id: MODULO_NOVO })),
];

const { fromTableMock, chamadasDeRange } = vi.hoisted(() => {
  const chamadasDeRange: Array<[number, number]> = [];

  // Construtor encadeável que imita o do Supabase: só resolve no await,
  // e o .range() recorta como o servidor recortaria.
  const construtor = (tabela: string) => {
    let de = 0;
    let ate = 999; // o corte padrão da API, que é a origem do defeito

    const alvo = {
      select: () => alvo,
      eq: () => alvo,
      order: () => alvo,
      range: (inicio: number, fim: number) => {
        chamadasDeRange.push([inicio, fim]);
        de = inicio;
        ate = fim;
        return alvo;
      },
      then: (resolve: (r: unknown) => unknown) => {
        if (tabela !== "qa_casos_teste") return resolve({ data: [], error: null });
        return resolve({ data: linhas.slice(de, ate + 1), error: null });
      },
    };

    return alvo;
  };

  return { fromTableMock: vi.fn(construtor), chamadasDeRange };
});

vi.mock("@/integrations/supabase/untypedClient", () => ({
  fromTable: fromTableMock,
}));

vi.mock("@/hooks/useAuth", () => ({
  useAuth: () => ({ user: { id: "superadmin" } }),
}));

import { useQaDocs } from "@/hooks/useQaDocs";

function comProvider() {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return ({ children }: { children: ReactNode }) =>
    createElement(QueryClientProvider, { client }, children);
}

describe("useQaDocs — contagem de casos por módulo", () => {
  beforeEach(() => {
    chamadasDeRange.length = 0;
    fromTableMock.mockClear();
  });

  it("conta os casos que ficam além da primeira página", async () => {
    const { result } = renderHook(() => useQaDocs(null), { wrapper: comProvider() });

    await waitFor(() => {
      expect(result.current.contagem[MODULO_NOVO]).toBe(59);
    });

    // O módulo antigo continua certo — a paginação não pode contar a mais.
    expect(result.current.contagem[MODULO_ANTIGO]).toBe(1000);
  });

  it("para de buscar assim que a página vem incompleta", async () => {
    const { result } = renderHook(() => useQaDocs(null), { wrapper: comProvider() });

    await waitFor(() => {
      expect(result.current.contagem[MODULO_NOVO]).toBe(59);
    });

    // Duas páginas bastam para 1.059 linhas: a segunda volta incompleta.
    expect(chamadasDeRange).toEqual([
      [0, 999],
      [1000, 1999],
    ]);
  });
});
