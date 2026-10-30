import { useEffect, useMemo, useState } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Switch } from "@/components/ui/switch";
import { Checkbox } from "@/components/ui/checkbox";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from "@/components/ui/dialog";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { fromTable, rpcUntyped } from "@/integrations/supabase/untypedClient";
import { useTenant } from "@/hooks/useTenant";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Settings2, Plus, Edit, Trash2, Lock } from "lucide-react";
import { toast } from "sonner";
import { confirm as confirmDialog } from "@/components/ui/confirm-dialog";
import { AvisoLinha } from "./PontoInstrumentoVinculosDialog";

/**
 * Configurações de Banco de Horas — Banco configurável, Fatia 1.
 *
 * Os campos novos (modalidade, ciclo, fim do ciclo, rescisão, o que debita,
 * fatores, extrato) são CADASTRO: ainda não mudam o cálculo. A tela diz isso
 * com o selo "em breve no cálculo". Bloqueios só para o que a lei proíbe em
 * qualquer caso; o resto vira aviso (ponto_banco_config_avisos_previa).
 */

type Desc = "zerar" | "descontar";
type Destino = "banco" | "folha" | "banco_se_houver_saldo";

interface BHForm {
  tipo: "sem_banco" | "semanal" | "mensal" | "individual" | "coletivo";
  prazo_compensacao_dias: number;
  permite_saldo_positivo: boolean;
  permite_saldo_negativo: boolean;
  limite_acumulo_horas: number;
  forma_compensacao: string;
  exige_acordo_individual: boolean;
  exige_cct_act: boolean;
  acordo_id: string | null;
  escala_id: string | null;
  data_inicio: string | null;
  data_fim: string | null;
  ativo: boolean;
  // Fatia 1 (cadastro)
  modalidade: "mensal" | "semestral" | "anual";
  tipo_ciclo: "fixo" | "admissao";
  meses_fechamento: number[];
  instrumento_id: string | null;
  negativo_fim_ciclo: "zerar" | "descontar" | "transportar";
  negativo_rescisao_sem_justa_causa: Desc;
  negativo_rescisao_pedido_demissao: Desc;
  negativo_rescisao_justa_causa: Desc;
  negativo_rescisao_acordo_484a: Desc;
  negativo_rescisao_fim_contrato: Desc;
  teto_desconto_rescisao_uma_remuneracao: boolean;
  falta_injustificada_destino: Destino;
  atraso_destino: Destino;
  saida_antecipada_destino: Destino;
  limite_saldo_negativo_min: number | null;
  negativo_acima_limite_acao: "alertar" | "folha";
  fator_credito_util: number;
  fator_credito_domingo: number;
  fator_credito_feriado: number;
  fator_credito_noturno: number;
  teto_credito_diario_min: number;
  limite_saldo_acao: "alertar" | "reter_excedente";
  extrato_mensal: boolean;
}

const TODOS_MESES = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
const NOME_MES = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"];
const MAX_MESES: Record<string, number> = { mensal: 1, semestral: 6, anual: 12 };

const defaultForm: BHForm = {
  tipo: "mensal",
  prazo_compensacao_dias: 180,
  permite_saldo_positivo: true,
  permite_saldo_negativo: false,
  limite_acumulo_horas: 60,
  forma_compensacao: "folga",
  exige_acordo_individual: false,
  exige_cct_act: false,
  acordo_id: null,
  escala_id: null,
  data_inicio: null,
  data_fim: null,
  ativo: true,
  modalidade: "mensal",
  tipo_ciclo: "fixo",
  meses_fechamento: TODOS_MESES,
  instrumento_id: null,
  negativo_fim_ciclo: "zerar",
  negativo_rescisao_sem_justa_causa: "zerar",
  negativo_rescisao_pedido_demissao: "zerar",
  negativo_rescisao_justa_causa: "zerar",
  negativo_rescisao_acordo_484a: "zerar",
  negativo_rescisao_fim_contrato: "zerar",
  teto_desconto_rescisao_uma_remuneracao: true,
  falta_injustificada_destino: "folha",
  atraso_destino: "banco",
  saida_antecipada_destino: "banco",
  limite_saldo_negativo_min: null,
  negativo_acima_limite_acao: "alertar",
  fator_credito_util: 1,
  fator_credito_domingo: 1,
  fator_credito_feriado: 1,
  fator_credito_noturno: 1,
  teto_credito_diario_min: 120,
  limite_saldo_acao: "alertar",
  extrato_mensal: true,
};

/** Maior intervalo (em meses) entre fechamentos de um ciclo fixo. */
function maiorCiclo(meses: number[]): number {
  const m = Array.from(new Set(meses)).sort((a, b) => a - b);
  if (m.length === 0) return 99;
  let gap = 12 - m[m.length - 1] + m[0];
  for (let i = 0; i < m.length - 1; i++) gap = Math.max(gap, m[i + 1] - m[i]);
  return gap;
}

/** Erros que BLOQUEIAM a gravação (o banco recusa as mesmas coisas). */
function errosBloqueio(f: BHForm): string[] {
  const e: string[] = [];
  if (f.teto_credito_diario_min < 0 || f.teto_credito_diario_min > 120) {
    e.push("O teto de crédito por dia vai de 0 a 120 minutos: a jornada não pode passar de 10 horas por dia (CLT art. 59).");
  }
  if (f.tipo_ciclo === "fixo" && maiorCiclo(f.meses_fechamento) > MAX_MESES[f.modalidade]) {
    e.push(`Com esses meses de fechamento, um ciclo passaria do máximo do banco ${f.modalidade} (${MAX_MESES[f.modalidade]} ${MAX_MESES[f.modalidade] === 1 ? "mês" : "meses"} — CLT art. 59).`);
  }
  if (f.data_inicio && f.data_fim && f.data_fim < f.data_inicio) e.push("A data de fim não pode ser antes da data de início.");
  for (const k of ["fator_credito_util", "fator_credito_domingo", "fator_credito_feriado", "fator_credito_noturno"] as const) {
    if (!(f[k] >= 1 && f[k] <= 3)) { e.push("Os fatores de crédito vão de 1 a 3."); break; }
  }
  if (f.limite_saldo_negativo_min !== null && f.limite_saldo_negativo_min < 0) e.push("O limite do saldo negativo não pode ser negativo.");
  return e;
}

function EmBreve() {
  return (
    <Badge variant="outline" className="ml-2 text-[10px] font-normal border-sky-500/60 text-sky-700 dark:text-sky-300"
      title="Já pode ser cadastrado, mas o cálculo ainda não usa esta regra.">
      em breve no cálculo
    </Badge>
  );
}

function Grupo({ titulo, emBreve, children }: { titulo: string; emBreve?: boolean; children: React.ReactNode }) {
  return (
    <fieldset className="rounded-md border p-3 space-y-3">
      <legend className="px-1 text-sm font-medium">{titulo}{emBreve && <EmBreve />}</legend>
      {children}
    </fieldset>
  );
}

function SelZerarDesc({ label, value, onChange }: { label: string; value: Desc; onChange: (v: Desc) => void }) {
  return (
    <div className="space-y-1">
      <Label className="text-xs">{label}</Label>
      <Select value={value} onValueChange={(v: Desc) => onChange(v)}>
        <SelectTrigger><SelectValue /></SelectTrigger>
        <SelectContent>
          <SelectItem value="zerar">Zerar (não descontar)</SelectItem>
          <SelectItem value="descontar">Descontar na rescisão</SelectItem>
        </SelectContent>
      </Select>
    </div>
  );
}

function SelDestino({ label, value, onChange }: { label: string; value: Destino; onChange: (v: Destino) => void }) {
  return (
    <div className="space-y-1">
      <Label className="text-xs">{label}</Label>
      <Select value={value} onValueChange={(v: Destino) => onChange(v)}>
        <SelectTrigger><SelectValue /></SelectTrigger>
        <SelectContent>
          <SelectItem value="banco">Debitar do banco</SelectItem>
          <SelectItem value="banco_se_houver_saldo">Do banco até zerar o saldo; o resto na folha</SelectItem>
          <SelectItem value="folha">Descontar na folha</SelectItem>
        </SelectContent>
      </Select>
    </div>
  );
}

export function PontoBancoHorasConfigTab() {
  const { tenantId } = useTenant();
  const { empresaAtivaId } = useEmpresaAtiva();
  const qc = useQueryClient();
  const [open, setOpen] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState<BHForm>(defaultForm);
  const [saving, setSaving] = useState(false);
  const [formDebounced, setFormDebounced] = useState<BHForm>(defaultForm);

  useEffect(() => {
    const t = setTimeout(() => setFormDebounced(form), 400);
    return () => clearTimeout(t);
  }, [form]);

  const { data: configs = [], isLoading } = useQuery({
    queryKey: ["ponto-bh-config", tenantId, empresaAtivaId],
    queryFn: async () => {
      if (!tenantId) return [];
      let q = fromTable("ponto_banco_horas_config").select("*").eq("tenant_id", tenantId);
      if (empresaAtivaId) q = q.or(`empresa_id.eq.${empresaAtivaId},empresa_id.is.null`);
      const { data } = await q.order("created_at", { ascending: false }) as { data: any[] | null };
      return data || [];
    },
    enabled: !!tenantId,
  });

  const { data: escalas = [] } = useQuery({
    queryKey: ["ponto-escalas-list", tenantId, empresaAtivaId],
    queryFn: async () => {
      if (!tenantId) return [];
      let q = fromTable("ponto_escalas").select("id,nome,tipo").eq("tenant_id", tenantId);
      if (empresaAtivaId) q = q.or(`empresa_id.eq.${empresaAtivaId},empresa_id.is.null`);
      const { data } = await q as { data: any[] | null };
      return data || [];
    },
    enabled: !!tenantId,
  });

  const { data: acordos = [] } = useQuery({
    queryKey: ["ponto-acordos-list", tenantId],
    queryFn: async () => {
      if (!tenantId) return [];
      const { data } = await fromTable("ponto_acordos").select("id,titulo,tipo,ativo,colaborador_cpf")
        .eq("tenant_id", tenantId).eq("ativo", true) as { data: any[] | null };
      return data || [];
    },
    enabled: !!tenantId,
  });

  const payloadAvisos = useMemo(
    () => ({ ...formDebounced, empresa_id: empresaAtivaId || null }),
    [formDebounced, empresaAtivaId],
  );
  const { data: avisos = [] } = useQuery({
    queryKey: ["ponto-bh-avisos", tenantId, JSON.stringify(payloadAvisos)],
    queryFn: async () => {
      const { data, error } = await rpcUntyped("ponto_banco_config_avisos_previa", { p_tenant: tenantId, p_config: payloadAvisos });
      if (error) return [];
      return (data || []) as any[];
    },
    enabled: !!tenantId && open,
  });

  const bloqueios = errosBloqueio(form);
  const avisosDe = (prefixos: string[]) => avisos.filter((a: any) => prefixos.some(p => a.codigo.startsWith(p)));

  const upd = <K extends keyof BHForm>(k: K, v: BHForm[K]) => setForm(p => ({ ...p, [k]: v }));

  const onNovo = () => { setForm(defaultForm); setEditId(null); setOpen(true); };
  const onEditar = (c: any) => {
    const f: BHForm = { ...defaultForm };
    (Object.keys(defaultForm) as (keyof BHForm)[]).forEach((k) => {
      if (c[k] !== undefined && c[k] !== null) (f as any)[k] = c[k];
    });
    f.limite_saldo_negativo_min = c.limite_saldo_negativo_min ?? null;
    f.limite_acumulo_horas = Number(c.limite_acumulo_horas ?? 60);
    ["fator_credito_util", "fator_credito_domingo", "fator_credito_feriado", "fator_credito_noturno"].forEach(k => {
      (f as any)[k] = Number(c[k] ?? 1);
    });
    f.data_inicio = c.data_inicio ? String(c.data_inicio).slice(0, 10) : null;
    f.data_fim = c.data_fim ? String(c.data_fim).slice(0, 10) : null;
    setForm(f);
    setEditId(c.id);
    setOpen(true);
  };

  const onSalvar = async () => {
    if (!tenantId) return;
    if (bloqueios.length) { toast.error(bloqueios[0]); return; }
    setSaving(true);
    try {
      const payload = {
        ...form,
        // Saldo positivo no fim do prazo é sempre pago como hora extra (CLT art. 59).
        forma_pagamento_vencer: "horas_extras",
        data_inicio: form.data_inicio || null,
        data_fim: form.data_fim || null,
        tenant_id: tenantId,
        empresa_id: empresaAtivaId || null,
      };
      const { error } = editId
        ? await fromTable("ponto_banco_horas_config").update(payload).eq("id", editId)
        : await fromTable("ponto_banco_horas_config").insert(payload);
      if (error) throw error;
      toast.success(editId ? "Configuração atualizada" : "Configuração criada");
      qc.invalidateQueries({ queryKey: ["ponto-bh-config"] });
      setOpen(false);
    } catch (e: any) {
      toast.error(e.message || "Erro ao salvar");
    } finally {
      setSaving(false);
    }
  };

  const onExcluir = async (c: any) => {
    const ok = await confirmDialog({
      title: "Excluir configuração",
      description: `Confirma exclusão? Prefira preencher a data de fim para guardar o histórico. Digite EXCLUIR para confirmar.`,
      requiredWord: "EXCLUIR",
      variant: "destructive",
    });
    if (!ok) return;
    await fromTable("ponto_banco_horas_config").delete().eq("id", c.id);
    qc.invalidateQueries({ queryKey: ["ponto-bh-config"] });
    toast.success("Removido");
  };

  const tipoLabel = (t: string) => ({
    sem_banco: "Sem Banco", semanal: "Semanal", mensal: "Mensal", individual: "Individual", coletivo: "Coletivo",
  } as any)[t] || t;
  const modLabel = (m: string) => ({ mensal: "Mensal", semestral: "Semestral", anual: "Anual" } as any)[m] || "Mensal";
  const dataBr = (d?: string | null) => (d ? String(d).slice(0, 10).split("-").reverse().join("/") : "");

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-2 flex-wrap">
        <div>
          <h3 className="text-lg font-semibold flex items-center gap-2">
            <Settings2 className="w-5 h-5 text-primary" /> Configurações de Banco de Horas
          </h3>
          <p className="text-sm text-muted-foreground">
            Regras do banco por empresa ou escala, com vigência. As convenções ficam em Compliance → Convenções e acordos.
          </p>
        </div>
        <Button onClick={onNovo}><Plus className="w-4 h-4 mr-2" /> Nova Configuração</Button>
      </div>

      <Card>
        <CardContent className="p-0 overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Tipo</TableHead>
                <TableHead>Modalidade</TableHead>
                <TableHead>Escala</TableHead>
                <TableHead className="text-center">Vigência</TableHead>
                <TableHead className="text-center">Prazo (dias)</TableHead>
                <TableHead className="text-center">Acordo</TableHead>
                <TableHead className="text-center">Status</TableHead>
                <TableHead className="text-center">Ações</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {isLoading ? (
                <TableRow><TableCell colSpan={8} className="text-center py-8">Carregando...</TableCell></TableRow>
              ) : configs.length === 0 ? (
                <TableRow><TableCell colSpan={8} className="text-center py-8 text-muted-foreground">Nenhuma configuração: sem regra de banco, as horas vão para a folha.</TableCell></TableRow>
              ) : configs.map((c: any) => {
                const esc = escalas.find((e: any) => e.id === c.escala_id);
                const ac = acordos.find((a: any) => a.id === c.acordo_id);
                return (
                  <TableRow key={c.id}>
                    <TableCell><Badge variant="outline">{tipoLabel(c.tipo)}</Badge></TableCell>
                    <TableCell className="text-sm">{c.tipo === "sem_banco" ? "—" : modLabel(c.modalidade)}</TableCell>
                    <TableCell>{esc?.nome || <span className="text-muted-foreground text-xs">Todas</span>}</TableCell>
                    <TableCell className="text-center text-xs">
                      {c.data_inicio || c.data_fim
                        ? `${dataBr(c.data_inicio) || "…"} — ${dataBr(c.data_fim) || "sem fim"}`
                        : <span className="text-muted-foreground">—</span>}
                    </TableCell>
                    <TableCell className="text-center">{c.prazo_compensacao_dias}</TableCell>
                    <TableCell className="text-center text-xs">{ac?.titulo || "—"}</TableCell>
                    <TableCell className="text-center">{c.ativo ? <Badge>Ativo</Badge> : <Badge variant="outline">Inativo</Badge>}</TableCell>
                    <TableCell className="text-center">
                      <div className="flex items-center justify-center gap-1">
                        <Button variant="ghost" size="icon" onClick={() => onEditar(c)}><Edit className="w-4 h-4" /></Button>
                        <Button variant="ghost" size="icon" className="text-destructive" onClick={() => onExcluir(c)}><Trash2 className="w-4 h-4" /></Button>
                      </div>
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-3xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{editId ? "Editar Configuração" : "Nova Configuração de Banco de Horas"}</DialogTitle>
            <DialogDescription>
              Os grupos com o selo <EmBreve /> já podem ser preenchidos, mas o cálculo ainda segue a regra atual
              (fechamento mensal) até a próxima etapa. Os avisos aparecem enquanto você preenche e não impedem salvar.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            {/* Básico: o que o cálculo já usa hoje */}
            <Grupo titulo="Regra e vigência">
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div className="space-y-1">
                  <Label className="text-xs">Tipo *</Label>
                  <Select value={form.tipo} onValueChange={(v: any) => upd("tipo", v)}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="sem_banco">Sem banco de horas (horas vão para a folha)</SelectItem>
                      <SelectItem value="semanal">Semanal</SelectItem>
                      <SelectItem value="mensal">Mensal</SelectItem>
                      <SelectItem value="individual">Individual</SelectItem>
                      <SelectItem value="coletivo">Coletivo</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div className="flex items-end gap-2">
                  <Switch checked={form.ativo} onCheckedChange={v => upd("ativo", v)} id="bh-ativo" />
                  <Label htmlFor="bh-ativo">Ativo</Label>
                </div>
                <div className="space-y-1">
                  <Label className="text-xs">Escala (opcional)</Label>
                  <Select value={form.escala_id || "todas"} onValueChange={v => upd("escala_id", v === "todas" ? null : v)}>
                    <SelectTrigger><SelectValue placeholder="Todas" /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="todas">Todas as escalas</SelectItem>
                      {escalas.map((e: any) => <SelectItem key={e.id} value={e.id}>{e.nome}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-1">
                  <Label className="text-xs">Acordo que autoriza o banco (opcional)</Label>
                  <Select value={form.acordo_id || "nenhum"} onValueChange={v => upd("acordo_id", v === "nenhum" ? null : v)}>
                    <SelectTrigger><SelectValue placeholder="Nenhum" /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="nenhum">Nenhum</SelectItem>
                      {acordos.map((a: any) => <SelectItem key={a.id} value={a.id}>{a.titulo}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-1">
                  <Label className="text-xs">Vale a partir de</Label>
                  <Input type="date" value={form.data_inicio || ""} onChange={e => upd("data_inicio", e.target.value || null)} />
                </div>
                <div className="space-y-1">
                  <Label className="text-xs">Vale até (opcional)</Label>
                  <Input type="date" value={form.data_fim || ""} onChange={e => upd("data_fim", e.target.value || null)} />
                </div>
              </div>
              <p className="text-xs text-muted-foreground">
                O banco só acumula dentro da vigência; fora dela, as horas vão para a folha. Para trocar a regra a partir
                de uma data, preencha "Vale até" nesta e crie outra — o histórico fica guardado. Depois, reapure as
                competências (Banco de Horas → "Apurar agora").
              </p>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div className="space-y-1">
                  <Label className="text-xs">Prazo de compensação (dias)</Label>
                  <Input type="number" value={form.prazo_compensacao_dias} onChange={e => upd("prazo_compensacao_dias", Number(e.target.value))} />
                </div>
                <div className="space-y-1">
                  <Label className="text-xs">Alerta de acúmulo (horas)</Label>
                  <Input type="number" value={form.limite_acumulo_horas} onChange={e => upd("limite_acumulo_horas", Number(e.target.value))} />
                </div>
                <div className="flex items-center gap-2"><Switch checked={form.permite_saldo_positivo} onCheckedChange={v => upd("permite_saldo_positivo", v)} /><Label className="text-sm">Permite saldo positivo</Label></div>
                <div className="flex items-center gap-2"><Switch checked={form.permite_saldo_negativo} onCheckedChange={v => upd("permite_saldo_negativo", v)} /><Label className="text-sm">Permite saldo negativo</Label></div>
                <div className="flex items-center gap-2"><Switch checked={form.exige_acordo_individual} onCheckedChange={v => upd("exige_acordo_individual", v)} /><Label className="text-sm">Exige acordo individual</Label></div>
                <div className="flex items-center gap-2"><Switch checked={form.exige_cct_act} onCheckedChange={v => upd("exige_cct_act", v)} /><Label className="text-sm">Exige CCT/ACT</Label></div>
              </div>
              {avisosDe(["APRENDIZ", "MENORES", "INSALUBRES", "REGRA_POR"]).map((a: any) => <AvisoLinha key={a.codigo} a={a} />)}
            </Grupo>

            {form.tipo !== "sem_banco" && (
              <>
                <Grupo titulo="Modalidade e ciclo" emBreve>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <div className="space-y-1">
                      <Label className="text-xs">Modalidade</Label>
                      <Select value={form.modalidade} onValueChange={(v: any) => {
                        upd("modalidade", v);
                        if (v === "mensal") upd("meses_fechamento", TODOS_MESES);
                        if (v === "semestral" && maiorCiclo(form.meses_fechamento) > 6) upd("meses_fechamento", [6, 12]);
                      }}>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="mensal">Mensal (compensa no mesmo mês)</SelectItem>
                          <SelectItem value="semestral">Semestral (até 6 meses — acordo individual escrito)</SelectItem>
                          <SelectItem value="anual">Anual (até 12 meses — só com CCT/ACT)</SelectItem>
                        </SelectContent>
                      </Select>
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs">Ciclo</Label>
                      <Select value={form.tipo_ciclo} onValueChange={(v: any) => upd("tipo_ciclo", v)}>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="fixo">Fixo para todos (meses de fechamento)</SelectItem>
                          <SelectItem value="admissao">Individual, contado da admissão</SelectItem>
                        </SelectContent>
                      </Select>
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs">Convenção a que esta regra se aplica (opcional)</Label>
                      <Select value={form.instrumento_id || "nenhum"} onValueChange={v => upd("instrumento_id", v === "nenhum" ? null : v)}>
                        <SelectTrigger><SelectValue placeholder="Todas" /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="nenhum">Todos os colaboradores da empresa/escala</SelectItem>
                          {acordos.filter((a: any) => a.tipo !== "individual").map((a: any) => <SelectItem key={a.id} value={a.id}>{a.titulo}</SelectItem>)}
                        </SelectContent>
                      </Select>
                    </div>
                  </div>
                  {form.tipo_ciclo === "fixo" && form.modalidade !== "mensal" && (
                    <div className="space-y-1">
                      <Label className="text-xs">Meses em que o ciclo fecha</Label>
                      <div className="flex flex-wrap gap-3">
                        {TODOS_MESES.map(m => (
                          <label key={m} className="flex items-center gap-1 text-sm">
                            <Checkbox checked={form.meses_fechamento.includes(m)}
                              onCheckedChange={(c) => upd("meses_fechamento",
                                c ? [...form.meses_fechamento, m].sort((a, b) => a - b) : form.meses_fechamento.filter(x => x !== m))} />
                            {NOME_MES[m - 1]}
                          </label>
                        ))}
                      </div>
                    </div>
                  )}
                  {avisosDe(["ANUAL", "SEMESTRAL", "PRAZO"]).map((a: any) => <AvisoLinha key={a.codigo} a={a} />)}
                </Grupo>

                <Grupo titulo="Fim do ciclo" emBreve>
                  <div className="flex items-center gap-2 text-sm">
                    <Lock className="w-4 h-4 text-muted-foreground" />
                    Saldo positivo: pago como hora extra, com adicional. Não existe opção de levar para o próximo ciclo
                    <span className="text-xs text-muted-foreground">(CLT art. 59, §§2º e 5º)</span>
                  </div>
                  <div className="space-y-1 max-w-sm">
                    <Label className="text-xs">Saldo negativo</Label>
                    <Select value={form.negativo_fim_ciclo} onValueChange={(v: any) => upd("negativo_fim_ciclo", v)}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="zerar">Zerar (sempre permitido)</SelectItem>
                        <SelectItem value="descontar">Descontar no salário</SelectItem>
                        <SelectItem value="transportar">Levar para o próximo ciclo</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                  {avisosDe(["NEGATIVO_FIM"]).map((a: any) => <AvisoLinha key={a.codigo} a={a} />)}
                </Grupo>

                <Grupo titulo="Rescisão: saldo negativo" emBreve>
                  <p className="text-xs text-muted-foreground">Saldo positivo na rescisão é sempre pago como hora extra (CLT art. 59, §3º).</p>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <SelZerarDesc label="Dispensa sem justa causa" value={form.negativo_rescisao_sem_justa_causa} onChange={v => upd("negativo_rescisao_sem_justa_causa", v)} />
                    <SelZerarDesc label="Fim de experiência / prazo determinado" value={form.negativo_rescisao_fim_contrato} onChange={v => upd("negativo_rescisao_fim_contrato", v)} />
                    <SelZerarDesc label="Pedido de demissão" value={form.negativo_rescisao_pedido_demissao} onChange={v => upd("negativo_rescisao_pedido_demissao", v)} />
                    <SelZerarDesc label="Justa causa" value={form.negativo_rescisao_justa_causa} onChange={v => upd("negativo_rescisao_justa_causa", v)} />
                    <SelZerarDesc label="Acordo entre as partes (art. 484-A)" value={form.negativo_rescisao_acordo_484a} onChange={v => upd("negativo_rescisao_acordo_484a", v)} />
                    <div className="flex items-end gap-2">
                      <Switch checked={form.teto_desconto_rescisao_uma_remuneracao} onCheckedChange={v => upd("teto_desconto_rescisao_uma_remuneracao", v)} id="bh-teto-resc" />
                      <Label htmlFor="bh-teto-resc" className="text-sm">Descontos limitados a uma remuneração (art. 477, §5º)</Label>
                    </div>
                  </div>
                  {avisosDe(["RESCISAO", "TETO_RESCISAO"]).map((a: any) => <AvisoLinha key={a.codigo} a={a} />)}
                </Grupo>

                <Grupo titulo="O que debita" emBreve>
                  <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                    <SelDestino label="Atraso" value={form.atraso_destino} onChange={v => upd("atraso_destino", v)} />
                    <SelDestino label="Saída antecipada" value={form.saida_antecipada_destino} onChange={v => upd("saida_antecipada_destino", v)} />
                    <SelDestino label="Falta sem justificativa" value={form.falta_injustificada_destino} onChange={v => upd("falta_injustificada_destino", v)} />
                  </div>
                  <p className="text-xs text-muted-foreground flex items-center gap-1">
                    <Lock className="w-3 h-3" /> Ausências legais (CLT art. 473) e atestados nunca debitam do banco — não há opção para isso.
                    Horas em que a empresa dispensou o colaborador podem ser repostas, mas nunca descontadas.
                  </p>
                  {form.permite_saldo_negativo && (
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                      <div className="space-y-1">
                        <Label className="text-xs">Limite do saldo negativo (horas; vazio = sem limite)</Label>
                        <Input type="number" min={0} step="0.5"
                          value={form.limite_saldo_negativo_min === null ? "" : form.limite_saldo_negativo_min / 60}
                          onChange={e => upd("limite_saldo_negativo_min", e.target.value === "" ? null : Math.round(Number(e.target.value) * 60))} />
                      </div>
                      <div className="space-y-1">
                        <Label className="text-xs">Acima do limite</Label>
                        <Select value={form.negativo_acima_limite_acao} onValueChange={(v: any) => upd("negativo_acima_limite_acao", v)}>
                          <SelectTrigger><SelectValue /></SelectTrigger>
                          <SelectContent>
                            <SelectItem value="alertar">Só avisar o RH</SelectItem>
                            <SelectItem value="folha">O que passar vai para a folha</SelectItem>
                          </SelectContent>
                        </Select>
                      </div>
                    </div>
                  )}
                  {avisosDe(["FALTA_NO_BANCO", "NEGATIVO_SEM_LIMITE"]).map((a: any) => <AvisoLinha key={a.codigo} a={a} />)}
                </Grupo>

                <Grupo titulo="Fatores e limites" emBreve>
                  <p className="text-xs text-muted-foreground">
                    Quanto vale 1 hora trabalhada no banco. Padrão 1 (uma por uma); a convenção pode prever 1,5 ou 2.
                  </p>
                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
                    {([
                      ["fator_credito_util", "Dia útil"],
                      ["fator_credito_domingo", "Domingo"],
                      ["fator_credito_feriado", "Feriado"],
                      ["fator_credito_noturno", "Hora noturna"],
                    ] as const).map(([k, l]) => (
                      <div key={k} className="space-y-1">
                        <Label className="text-xs">{l}</Label>
                        <Input type="number" min={1} max={3} step="0.1" value={form[k]} onChange={e => upd(k, Number(e.target.value))} />
                      </div>
                    ))}
                  </div>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <div className="space-y-1">
                      <Label className="text-xs">Teto de crédito por dia (minutos, 0 a 120)</Label>
                      <Input type="number" min={0} max={120} value={form.teto_credito_diario_min}
                        onChange={e => upd("teto_credito_diario_min", Number(e.target.value))} />
                      <p className="text-[11px] text-muted-foreground">
                        A jornada não pode passar de 10 horas por dia (CLT art. 59). O teto limita o que entra no banco,
                        nunca a batida de ponto. Na 12x36 vale a regra própria (art. 59-A).
                      </p>
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs">Ao passar do alerta de acúmulo</Label>
                      <Select value={form.limite_saldo_acao} onValueChange={(v: any) => upd("limite_saldo_acao", v)}>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="alertar">Só avisar o RH (como hoje)</SelectItem>
                          <SelectItem value="reter_excedente">Separar o excedente como "a pagar"</SelectItem>
                        </SelectContent>
                      </Select>
                    </div>
                  </div>
                </Grupo>

                <Grupo titulo="Extrato" emBreve>
                  <div className="flex items-center gap-2">
                    <Switch checked={form.extrato_mensal} onCheckedChange={v => upd("extrato_mensal", v)} id="bh-extrato" />
                    <Label htmlFor="bh-extrato" className="text-sm">Enviar extrato mensal do banco ao colaborador, para ciência</Label>
                  </div>
                  <p className="text-[11px] text-muted-foreground">
                    Recomendado: sem extrato, o colaborador pode alegar que não sabia do saldo e o banco pode ser anulado.
                  </p>
                </Grupo>
              </>
            )}

            {bloqueios.map((b) => (
              <Alert key={b} className="border-destructive/50 bg-destructive/5">
                <AlertDescription className="text-sm">{b}</AlertDescription>
              </Alert>
            ))}
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setOpen(false)}>Cancelar</Button>
            <Button onClick={onSalvar} disabled={saving || bloqueios.length > 0}>{saving ? "Salvando..." : "Salvar"}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
