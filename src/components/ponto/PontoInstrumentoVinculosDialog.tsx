import { useMemo, useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Checkbox } from "@/components/ui/checkbox";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from "@/components/ui/dialog";
import { fromTable, rpcUntyped } from "@/integrations/supabase/untypedClient";
import { useTenant } from "@/hooks/useTenant";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { AlertTriangle, Ban, Info, Search } from "lucide-react";
import { toast } from "sonner";

/**
 * Vínculo de colaboradores a um instrumento coletivo (Fatia 1).
 *
 * O sistema SUGERE pelo CBO ou pelo cargo (cadastrados no instrumento) e o RH
 * confirma marcando. Sem vínculo, vale a convenção da atividade principal da
 * empresa. Mostra os avisos do vínculo (Súmula 374) e as restrições de banco
 * de horas de cada colaborador (aprendiz, menor, insalubre).
 */

interface Aviso { codigo: string; nivel: string; texto: string; base_legal: string }

const dataBr = (d?: string | null) => (d ? String(d).slice(0, 10).split("-").reverse().join("/") : "");
const hoje = () => new Date().toISOString().slice(0, 10);

export function AvisoLinha({ a }: { a: Aviso }) {
  const cor = a.nivel === "bloqueio" || a.nivel === "forte"
    ? "border-destructive/50 bg-destructive/5"
    : a.nivel === "atencao" ? "border-amber-500/50 bg-amber-50 dark:bg-amber-950/20" : "border-sky-500/40 bg-sky-50 dark:bg-sky-950/20";
  const Icone = a.nivel === "bloqueio" ? Ban : a.nivel === "info" ? Info : AlertTriangle;
  return (
    <Alert className={cor}>
      <Icone className="h-4 w-4" />
      <AlertDescription className="text-sm">
        {a.texto}
        {a.base_legal && <span className="block text-xs text-muted-foreground mt-0.5">{a.base_legal}</span>}
      </AlertDescription>
    </Alert>
  );
}

export function PontoInstrumentoVinculosDialog({
  instrumento, open, onOpenChange,
}: { instrumento: any; open: boolean; onOpenChange: (o: boolean) => void }) {
  const { tenantId } = useTenant();
  const qc = useQueryClient();
  const [busca, setBusca] = useState("");
  const [marcados, setMarcados] = useState<string[]>([]);
  const [inicio, setInicio] = useState(hoje());
  const [salvando, setSalvando] = useState(false);

  const { data: avisosInstr = [] } = useQuery({
    queryKey: ["ponto-instr-avisos", tenantId, instrumento?.id],
    queryFn: async () => {
      const { data } = await rpcUntyped("ponto_instrumento_avisos_vinculo", {
        p_tenant: tenantId, p_instrumento_id: instrumento.id,
      });
      return (data || []) as Aviso[];
    },
    enabled: !!tenantId && !!instrumento?.id && open,
  });

  const { data: vinculos = [] } = useQuery({
    queryKey: ["ponto-instr-vinculos", tenantId, instrumento?.id],
    queryFn: async () => {
      const { data } = await fromTable("ponto_instrumento_colaborador")
        .select("id, admissao_id, data_inicio, data_fim, admissoes(nome_completo, cargo, cbo, contrato_aprendiz)")
        .eq("tenant_id", tenantId).eq("instrumento_id", instrumento.id)
        .order("data_inicio", { ascending: false }) as { data: any[] | null };
      return data || [];
    },
    enabled: !!tenantId && !!instrumento?.id && open,
  });

  const { data: sugestoes = [] } = useQuery({
    queryKey: ["ponto-instr-sugestoes", tenantId, instrumento?.id],
    queryFn: async () => {
      const { data } = await rpcUntyped("ponto_instrumento_sugestoes", {
        p_tenant: tenantId, p_instrumento_id: instrumento.id,
      });
      return (data || []) as any[];
    },
    enabled: !!tenantId && !!instrumento?.id && open,
  });

  const { data: encontrados = [] } = useQuery({
    queryKey: ["ponto-instr-busca", tenantId, busca],
    queryFn: async () => {
      const termo = busca.trim().replace(/[%,()]/g, " ");
      if (termo.length < 3) return [];
      const { data } = await fromTable("admissoes")
        .select("id, nome_completo, cargo, cbo, contrato_aprendiz")
        .eq("tenant_id", tenantId).eq("status", "concluido")
        .or(`nome_completo.ilike.%${termo}%,cargo.ilike.%${termo}%`)
        .order("nome_completo").limit(20) as { data: any[] | null };
      return (data || []).map((a: any) => ({
        admissao_id: a.id, nome: a.nome_completo, cargo: a.cargo, cbo: a.cbo,
        motivo: "Busca", ja_vinculado: false, aprendiz: !!a.contrato_aprendiz,
      }));
    },
    enabled: !!tenantId && open && busca.trim().length >= 3,
  });

  const vinculadosAtivos = useMemo(
    () => new Set(vinculos.filter((v: any) => !v.data_fim || v.data_fim >= hoje()).map((v: any) => v.admissao_id)),
    [vinculos],
  );
  const candidatos = useMemo(() => {
    const mapa = new Map<string, any>();
    [...sugestoes, ...encontrados].forEach((c: any) => { if (!mapa.has(c.admissao_id)) mapa.set(c.admissao_id, c); });
    return Array.from(mapa.values()).filter((c: any) => !vinculadosAtivos.has(c.admissao_id));
  }, [sugestoes, encontrados, vinculadosAtivos]);

  // Restrições de banco de horas dos marcados (aprendiz, menor, insalubre)
  const { data: restricoes = {} } = useQuery({
    queryKey: ["ponto-instr-restricoes", tenantId, marcados.join(",")],
    queryFn: async () => {
      const out: Record<string, Aviso[]> = {};
      for (const id of marcados) {
        const { data } = await rpcUntyped("ponto_banco_avisos_colaborador", { p_tenant: tenantId, p_admissao_id: id });
        out[id] = (data || []) as Aviso[];
      }
      return out;
    },
    enabled: !!tenantId && marcados.length > 0,
  });

  const alternar = (id: string, on: boolean) =>
    setMarcados(p => (on ? [...p, id] : p.filter(x => x !== id)));

  const confirmar = async () => {
    if (marcados.length === 0) return;
    setSalvando(true);
    let ok = 0;
    const erros: string[] = [];
    for (const id of marcados) {
      const { error } = await fromTable("ponto_instrumento_colaborador").insert({
        tenant_id: tenantId, admissao_id: id, instrumento_id: instrumento.id, data_inicio: inicio,
      });
      if (error) {
        const c = candidatos.find((x: any) => x.admissao_id === id);
        erros.push(`${c?.nome || "Colaborador"}: ${error.message}`);
      } else ok++;
    }
    setSalvando(false);
    if (ok) toast.success(`${ok} colaborador(es) vinculado(s)`);
    if (erros.length) toast.error(erros.join("\n"));
    setMarcados([]);
    qc.invalidateQueries({ queryKey: ["ponto-instr-vinculos"] });
    qc.invalidateQueries({ queryKey: ["ponto-instr-sugestoes"] });
  };

  const encerrar = async (v: any) => {
    const fim = hoje() < v.data_inicio ? v.data_inicio : hoje();
    const { error } = await fromTable("ponto_instrumento_colaborador").update({ data_fim: fim }).eq("id", v.id);
    if (error) { toast.error(error.message); return; }
    toast.success("Vínculo encerrado");
    qc.invalidateQueries({ queryKey: ["ponto-instr-vinculos"] });
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-3xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Colaboradores vinculados — {instrumento.titulo}</DialogTitle>
          <DialogDescription>
            Vincule quem segue esta convenção em vez da convenção da atividade principal da empresa
            (por exemplo, uma categoria diferenciada). O sistema sugere pelo CBO ou pelo cargo; você confirma.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          {avisosInstr.map((a) => <AvisoLinha key={a.codigo} a={a} />)}

          <div>
            <h4 className="text-sm font-medium mb-2">Vinculados</h4>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Colaborador</TableHead>
                  <TableHead>Cargo</TableHead>
                  <TableHead className="text-center">Período</TableHead>
                  <TableHead />
                </TableRow>
              </TableHeader>
              <TableBody>
                {vinculos.length === 0 ? (
                  <TableRow><TableCell colSpan={4} className="text-center text-muted-foreground py-4">Ninguém vinculado.</TableCell></TableRow>
                ) : vinculos.map((v: any) => (
                  <TableRow key={v.id}>
                    <TableCell>
                      {v.admissoes?.nome_completo || "—"}
                      {v.admissoes?.contrato_aprendiz && (
                        <Badge variant="destructive" className="ml-1" title="CLT art. 432">aprendiz: sem banco de horas</Badge>
                      )}
                    </TableCell>
                    <TableCell className="text-xs">{v.admissoes?.cargo || "—"}</TableCell>
                    <TableCell className="text-center text-xs">{dataBr(v.data_inicio)} — {v.data_fim ? dataBr(v.data_fim) : "atual"}</TableCell>
                    <TableCell className="text-right">
                      {!v.data_fim && <Button variant="ghost" size="sm" onClick={() => encerrar(v)}>Encerrar</Button>}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>

          <div className="space-y-2">
            <h4 className="text-sm font-medium">Adicionar</h4>
            <div className="relative">
              <Search className="w-4 h-4 absolute left-2 top-3 text-muted-foreground" />
              <Input className="pl-8" placeholder="Buscar por nome ou cargo (3 letras ou mais)" value={busca} onChange={e => setBusca(e.target.value)} />
            </div>
            {sugestoes.length === 0 && busca.trim().length < 3 && (
              <p className="text-xs text-muted-foreground">
                Sem sugestões: cadastre CBOs ou palavras do cargo no instrumento, ou use a busca.
              </p>
            )}
            {candidatos.length > 0 && (
              <div className="rounded-md border max-h-64 overflow-y-auto divide-y">
                {candidatos.map((c: any) => (
                  <label key={c.admissao_id} className="flex items-center gap-2 p-2 text-sm cursor-pointer">
                    <Checkbox checked={marcados.includes(c.admissao_id)} onCheckedChange={(v) => alternar(c.admissao_id, !!v)} />
                    <span className="flex-1">
                      {c.nome} <span className="text-xs text-muted-foreground">· {c.cargo || "sem cargo"}{c.cbo ? ` · CBO ${c.cbo}` : ""}</span>
                    </span>
                    {c.motivo !== "Busca" && <Badge variant="outline" className="text-[10px]">sugerido: {c.motivo}</Badge>}
                    {c.aprendiz && <Badge variant="destructive" className="text-[10px]" title="CLT art. 432">aprendiz</Badge>}
                  </label>
                ))}
              </div>
            )}
            {marcados.length > 0 && (
              <div className="space-y-2">
                {marcados.flatMap((id) => ((restricoes as Record<string, Aviso[]>)[id] || []).map((a) => {
                  const nome = candidatos.find((c: any) => c.admissao_id === id)?.nome || "";
                  return <AvisoLinha key={id + a.codigo} a={{ ...a, texto: `${nome}: ${a.texto}` }} />;
                }))}
                <div className="flex items-end gap-2">
                  <div className="space-y-1">
                    <Label className="text-xs">Vale a partir de</Label>
                    <Input type="date" value={inicio} onChange={e => setInicio(e.target.value)} />
                  </div>
                </div>
              </div>
            )}
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Fechar</Button>
          <Button onClick={confirmar} disabled={salvando || marcados.length === 0}>
            {salvando ? "Vinculando..." : `Confirmar ${marcados.length || ""} vínculo(s)`}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
