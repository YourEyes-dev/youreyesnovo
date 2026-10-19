import { useEffect, useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Loader2, Plus, Sparkles, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "@/hooks/useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { useDiasProfissao } from "@/hooks/useDiasProfissao";
import { buscarDiaProfissao, normalizarCargo } from "@/lib/diasProfissao";
import { mensagemDeErroDaFuncao } from "@/lib/erroFuncao";

interface Sugestao {
  cargo: string;
  profissao: string | null;
  nome_data: string | null;
  mes: number | null;
  dia: number | null;
  confianca: "alta" | "media" | "baixa" | null;
  base: string | null;
  observacao: string | null;
}

const POR_CHAMADA = 30;
const COR_CONFIANCA: Record<string, string> = {
  alta: "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400",
  media: "bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400",
  baixa: "bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400",
};
const dd = (n: number | null) => (n == null ? "" : String(n).padStart(2, "0"));

/**
 * A IA lê os cargos da empresa e SUGERE o dia comemorativo de cada profissão. Nada vale
 * até uma pessoa aprovar: IA erra data comemorativa. Só os NOMES dos cargos vão à IA.
 */
export const DiasProfissaoIA = () => {
  const { tenantId } = useAuth();
  const { empresaAtivaId, empresaAtiva } = useEmpresaAtiva();
  const { registros, decidir, remover } = useDiasProfissao();
  const [analisando, setAnalisando] = useState(false);
  const [sugestoes, setSugestoes] = useState<Sugestao[] | null>(null);
  const [edicao, setEdicao] = useState<Record<string, { nome: string; mes: string; dia: string }>>({});
  const [manual, setManual] = useState({ cargo: "", nome: "", mes: "", dia: "" });

  // Cargos da EMPRESA ATIVA (mesma regra do cadastro de cargos), nunca do grupo inteiro.
  // Sem empresa ativa não busca nada: melhor lista vazia do que cargos de outras empresas.
  const { data: cargosDaEmpresa = [] } = useQuery({
    queryKey: ["dias-profissao-cargos", tenantId, empresaAtivaId],
    queryFn: async (): Promise<string[]> => {
      type Linha = Record<string, string | null>;
      const lerTodos = async (montar: (de: number, ate: number) => PromiseLike<{ data: Linha[] | null; error: unknown }>) => {
        const linhas: Linha[] = [];
        for (let pagina = 0; pagina < 50; pagina++) {
          const { data, error } = await montar(pagina * 1000, pagina * 1000 + 999);
          if (error) throw error;
          linhas.push(...(data ?? []));
          if (!data || data.length < 1000) break;
        }
        return linhas;
      };
      const [cadastro, pessoas] = await Promise.all([
        lerTodos((de, ate) =>
          fromTable("cargos").select("nome").eq("tenant_id", tenantId).eq("empresa_id", empresaAtivaId).order("nome").range(de, ate),
        ),
        lerTodos((de, ate) =>
          fromTable("admissoes").select("cargo").eq("tenant_id", tenantId).eq("empresa_id", empresaAtivaId).eq("status", "concluido").order("id").range(de, ate),
        ),
      ]);
      const vistos = new Map<string, string>();
      [...cadastro.map((c) => c.nome), ...pessoas.map((p) => p.cargo)]
        .filter((n): n is string => !!n && !!n.trim())
        .forEach((n) => { if (!vistos.has(normalizarCargo(n))) vistos.set(normalizarCargo(n), n.trim()); });
      return [...vistos.values()].sort((a, b) => a.localeCompare(b, "pt-BR"));
    },
    enabled: !!tenantId && !!empresaAtivaId,
  });

  // Trocou de empresa: sugestões e edições da empresa anterior não podem ser aprovadas na nova.
  useEffect(() => {
    setSugestoes(null);
    setEdicao({});
    setManual({ cargo: "", nome: "", mes: "", dia: "" });
  }, [empresaAtivaId]);

  const chavesDaEmpresa = useMemo(() => new Set(cargosDaEmpresa.map(normalizarCargo)), [cargosDaEmpresa]);
  // As decisões são do grupo (a data de uma profissão é a mesma), mas aqui só aparecem as dos
  // cargos da empresa ativa; as demais ficam fora da lista e são contadas no aviso.
  const registrosDaEmpresa = useMemo(() => registros.filter((r) => chavesDaEmpresa.has(r.cargo_chave)), [registros, chavesDaEmpresa]);
  const ocultas = registros.length - registrosDaEmpresa.length;
  const decididos = useMemo(() => new Set(registros.map((r) => r.cargo_chave)), [registros]);
  const jaNoPadrao = cargosDaEmpresa.filter((c) => !decididos.has(normalizarCargo(c)) && buscarDiaProfissao(c));
  const paraAnalisar = cargosDaEmpresa.filter((c) => !decididos.has(normalizarCargo(c)) && !buscarDiaProfissao(c));

  const analisar = async () => {
    if (!empresaAtivaId) {
      toast.error("Selecione a empresa antes de analisar os cargos.");
      return;
    }
    setAnalisando(true);
    try {
      const todas: Sugestao[] = [];
      for (let i = 0; i < paraAnalisar.length; i += POR_CHAMADA) {
        const { data, error } = await supabase.functions.invoke("ai-cultura-dia-profissao", {
          body: { cargos: paraAnalisar.slice(i, i + POR_CHAMADA), empresaId: empresaAtivaId },
        });
        if (error || !data?.sugestoes) {
          toast.error(await mensagemDeErroDaFuncao(error, data, "analisar os cargos"));
          break;
        }
        todas.push(...(data.sugestoes as Sugestao[]));
      }
      if (todas.length) {
        setSugestoes(todas);
        setEdicao(Object.fromEntries(todas.filter((s) => s.mes).map((s) => [s.cargo, { nome: s.nome_data ?? "", mes: String(s.mes), dia: String(s.dia) }])));
      }
    } finally {
      setAnalisando(false);
    }
  };

  const tirarDaLista = (cargo: string) => setSugestoes((l) => (l ? l.filter((s) => s.cargo !== cargo) : l));

  const aprovar = async (s: Sugestao) => {
    const e = edicao[s.cargo];
    const mes = Number(e?.mes), dia = Number(e?.dia);
    if (!e?.nome.trim() || !(mes >= 1 && mes <= 12) || !(dia >= 1 && dia <= 31) || new Date(2024, mes - 1, dia).getMonth() !== mes - 1) {
      toast.error("Confira o nome da data, o dia e o mês antes de aprovar");
      return;
    }
    await decidir({ cargo: s.cargo, status: "aprovado", origem: "ia", nome_data: e.nome.trim(), mes, dia, confianca: s.confianca, base: s.base });
    tirarDaLista(s.cargo);
  };

  const descartar = async (s: Sugestao) => {
    await decidir({ cargo: s.cargo, status: "rejeitado", origem: "ia" });
    tirarDaLista(s.cargo);
  };

  const aprovarAltaConfianca = async () => {
    for (const s of (sugestoes ?? []).filter((x) => x.mes && x.confianca === "alta")) await aprovar(s);
  };

  const adicionarManual = async () => {
    const mes = Number(manual.mes), dia = Number(manual.dia);
    if (!manual.cargo.trim() || !manual.nome.trim() || !(mes >= 1 && mes <= 12) || !(dia >= 1 && dia <= 31) || new Date(2024, mes - 1, dia).getMonth() !== mes - 1) {
      toast.error("Informe o cargo, o nome da data, o dia e o mês");
      return;
    }
    if (!chavesDaEmpresa.has(normalizarCargo(manual.cargo))) {
      toast.error("Informe um cargo existente nesta empresa (escolha da lista).");
      return;
    }
    await decidir({ cargo: manual.cargo.trim(), status: "aprovado", origem: "manual", nome_data: manual.nome.trim(), mes, dia });
    setManual({ cargo: "", nome: "", mes: "", dia: "" });
    toast.success("Dia da profissão salvo");
  };

  const comData = (sugestoes ?? []).filter((s) => s.mes);
  const semData = (sugestoes ?? []).filter((s) => !s.mes);

  return (
    <div className="space-y-4" data-testid="dias-profissao">
      <Card className="p-6 space-y-3">
        <div className="flex items-start justify-between gap-3 flex-wrap">
          <div className="min-w-0">
            <h3 className="font-medium flex items-center gap-2"><Sparkles className="w-4 h-4" /> Dia da profissão por cargo</h3>
            <p className="text-xs text-muted-foreground mt-1 max-w-xl">
              A IA lê os cargos da empresa e sugere o dia comemorativo de cada profissão. Ela pode errar uma data:
              por isso nada entra no calendário sem a sua aprovação. Só os nomes dos cargos são enviados à IA,
              nunca dados de colaboradores.
            </p>
          </div>
          <Button onClick={analisar} disabled={analisando || !empresaAtivaId || paraAnalisar.length === 0} className="gap-1">
            {analisando ? <Loader2 className="h-4 w-4 animate-spin" /> : <Sparkles className="h-4 w-4" />}
            Analisar cargos com IA
          </Button>
        </div>
        <p className="text-xs text-muted-foreground">
          {!empresaAtivaId ? (
            "Selecione uma empresa para analisar os cargos dela."
          ) : (
            <>
              {empresaAtiva?.nome_fantasia || empresaAtiva?.razao_social ? <strong>{empresaAtiva?.nome_fantasia || empresaAtiva?.razao_social}: </strong> : null}
              {cargosDaEmpresa.length} cargo{cargosDaEmpresa.length === 1 ? "" : "s"} · {jaNoPadrao.length} já coberto
              {jaNoPadrao.length === 1 ? "" : "s"} pelo catálogo padrão · {registrosDaEmpresa.length} definido{registrosDaEmpresa.length === 1 ? "" : "s"} por você ·{" "}
              <strong>{paraAnalisar.length} para analisar</strong>
            </>
          )}
        </p>
      </Card>

      {comData.length > 0 && (
        <Card className="p-4 space-y-3">
          <div className="flex items-center justify-between gap-2 flex-wrap">
            <h4 className="text-sm font-medium">Sugestões para conferir ({comData.length})</h4>
            <Button size="sm" variant="outline" onClick={aprovarAltaConfianca} disabled={!comData.some((s) => s.confianca === "alta")}>
              Aprovar as de confiança alta
            </Button>
          </div>
          {comData.map((s) => {
            const e = edicao[s.cargo] ?? { nome: "", mes: "", dia: "" };
            const mudar = (campo: "nome" | "mes" | "dia", v: string) => setEdicao((x) => ({ ...x, [s.cargo]: { ...e, [campo]: v } }));
            return (
              <div key={s.cargo} className="rounded-lg border p-3 space-y-2">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="text-sm font-medium">{s.cargo}</span>
                  {s.confianca && <Badge className={`text-[10px] ${COR_CONFIANCA[s.confianca]}`}>Confiança {s.confianca}</Badge>}
                </div>
                <p className="text-xs text-muted-foreground">
                  {[s.profissao && `Profissão: ${s.profissao}`, s.base && `Base: ${s.base}`, s.observacao].filter(Boolean).join(" · ")}
                </p>
                <div className="flex items-end gap-2 flex-wrap">
                  <div className="flex-1 min-w-[10rem]">
                    <Label className="text-xs">Nome da data</Label>
                    <Input value={e.nome} onChange={(ev) => mudar("nome", ev.target.value)} aria-label={`Nome da data de ${s.cargo}`} />
                  </div>
                  <div>
                    <Label className="text-xs">Dia</Label>
                    <Input className="w-16" inputMode="numeric" value={e.dia} onChange={(ev) => mudar("dia", ev.target.value)} aria-label={`Dia de ${s.cargo}`} />
                  </div>
                  <div>
                    <Label className="text-xs">Mês</Label>
                    <Input className="w-16" inputMode="numeric" value={e.mes} onChange={(ev) => mudar("mes", ev.target.value)} aria-label={`Mês de ${s.cargo}`} />
                  </div>
                  <Button size="sm" onClick={() => aprovar(s)}>Aprovar</Button>
                  <Button size="sm" variant="ghost" onClick={() => descartar(s)}>Descartar</Button>
                </div>
              </div>
            );
          })}
        </Card>
      )}

      {semData.length > 0 && (
        <Card className="p-4 space-y-2">
          <h4 className="text-sm font-medium">Sem dia comemorativo conhecido ({semData.length})</h4>
          <p className="text-xs text-muted-foreground">A IA não encontrou uma data que ela garanta para estes cargos. Marque para não analisá-los de novo.</p>
          <div className="flex flex-wrap gap-2">
            {semData.map((s) => (
              <Button key={s.cargo} size="sm" variant="outline" className="h-7 text-xs" onClick={() => descartar(s)}>
                {s.cargo} · marcar sem dia
              </Button>
            ))}
          </div>
        </Card>
      )}

      <Card className="p-4 space-y-3">
        <h4 className="text-sm font-medium">Definidos pela empresa</h4>
        {registrosDaEmpresa.length === 0 ? (
          <p className="text-xs text-muted-foreground">Nenhuma definição ainda. Os cargos usam só o catálogo padrão.</p>
        ) : (
          <div className="space-y-1">
            {registrosDaEmpresa.map((r) => (
              <div key={r.id} className="flex items-center gap-2 text-sm p-1.5 rounded hover:bg-muted/40">
                <span className="font-medium truncate">{r.cargo_exemplo}</span>
                <span className="text-muted-foreground truncate">
                  {r.status === "aprovado" ? `${r.nome_data} · ${dd(r.dia)}/${dd(r.mes)}` : "sem dia da profissão"}
                </span>
                <Badge variant="outline" className="text-[10px] shrink-0">{r.origem === "ia" ? "IA aprovada" : "Manual"}</Badge>
                <Button size="icon" variant="ghost" className="h-7 w-7 ml-auto shrink-0 text-destructive" aria-label={`Remover ${r.cargo_exemplo}`} onClick={() => remover(r.id)}>
                  <Trash2 className="w-3.5 h-3.5" />
                </Button>
              </div>
            ))}
          </div>
        )}
        {ocultas > 0 && (
          <p className="text-[11px] text-muted-foreground">
            {ocultas} definição{ocultas === 1 ? "" : "ões"} de cargos que não existem nesta empresa {ocultas === 1 ? "fica oculta" : "ficam ocultas"} aqui.
          </p>
        )}
        <div className="pt-3 border-t space-y-2">
          <p className="text-xs text-muted-foreground">Informar à mão (cargo desta empresa):</p>
          <div className="flex items-end gap-2 flex-wrap">
            <div className="flex-1 min-w-[9rem]"><Label className="text-xs">Cargo</Label><Input list="dias-profissao-cargos" value={manual.cargo} onChange={(e) => setManual((m) => ({ ...m, cargo: e.target.value }))} /></div>
            <div className="flex-1 min-w-[9rem]"><Label className="text-xs">Nome da data</Label><Input value={manual.nome} placeholder="Dia do ..." onChange={(e) => setManual((m) => ({ ...m, nome: e.target.value }))} /></div>
            <div><Label className="text-xs">Dia</Label><Input className="w-16" inputMode="numeric" value={manual.dia} onChange={(e) => setManual((m) => ({ ...m, dia: e.target.value }))} /></div>
            <div><Label className="text-xs">Mês</Label><Input className="w-16" inputMode="numeric" value={manual.mes} onChange={(e) => setManual((m) => ({ ...m, mes: e.target.value }))} /></div>
            <Button size="sm" variant="outline" className="gap-1" onClick={adicionarManual}><Plus className="w-3.5 h-3.5" /> Adicionar</Button>
          </div>
          <datalist id="dias-profissao-cargos">{cargosDaEmpresa.map((c) => <option key={c} value={c} />)}</datalist>
        </div>
      </Card>
    </div>
  );
};
