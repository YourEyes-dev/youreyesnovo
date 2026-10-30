import { useMemo, useState } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Badge } from "@/components/ui/badge";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Plus, Trash2, Save, X, Pencil, Clock, Paperclip, ShieldAlert, Scale, AlertTriangle, Smartphone } from "lucide-react";
import { usePontoJustificativas, type PontoJustificativa, type TipoAbono, type NaturezaJustificativa } from "@/hooks/usePontoJustificativas";
import { divergenciaNomeRegra } from "@/lib/ponto/justificativaDivergencia";
import { confirm } from "@/components/ui/confirm-dialog";
import { toast } from "sonner";

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
}

type FormState = Partial<PontoJustificativa> & { nome: string; horas_abono: number };

const EMPTY: FormState = { nome: "", descricao: "", horas_abono: 0, requer_anexo: false, ativo: true, ordem: 0, tipo_abono: "nao", base_legal: null, natureza: null, aparece_no_app: false };

const ABONO_LABEL: Record<TipoAbono, string> = { sim: "Abona", nao: "Não abona", configuravel: "Configurável" };
const ABONO_BADGE: Record<TipoAbono, string> = {
  sim: "border-emerald-500 text-emerald-700 dark:text-emerald-400",
  nao: "border-rose-400 text-rose-700 dark:text-rose-400",
  configuravel: "border-amber-500 text-amber-700 dark:text-amber-400",
};

// Radix Select não aceita valor vazio: "rh" representa natureza nula.
const NATUREZA_RH = "rh";
const NATUREZA_LABEL: Record<string, string> = {
  correcao_batida: "Correção de batida",
  ausencia: "Ausência",
  [NATUREZA_RH]: "Lançamento do RH",
};

export function ConfigJustificativasModal({ open, onOpenChange }: Props) {
  const { justificativas, loading, podeGerenciar, salvar, salvando, remover } = usePontoJustificativas();
  const [form, setForm] = useState<FormState>(EMPTY);
  const [editId, setEditId] = useState<string | null>(null);

  const reset = () => { setForm(EMPTY); setEditId(null); };

  const natureza: NaturezaJustificativa = form.natureza ?? null;
  const avisoDivergencia = divergenciaNomeRegra(form.nome, form.tipo_abono);
  // D2: criadas pela empresa sem natureza não aparecerão no app novo até o RH classificar.
  const semNaturezaDaEmpresa = useMemo(
    () => justificativas.filter((j) => !j.sistema && !j.natureza).length,
    [justificativas],
  );

  const mudarNatureza = (v: string) => {
    const nova: NaturezaJustificativa = v === NATUREZA_RH ? null : (v as NaturezaJustificativa);
    setForm((f) => ({
      ...f,
      natureza: nova,
      // as mesmas travas do banco (trg_justificativa_trava_natureza)
      tipo_abono: nova === "correcao_batida" ? "nao" : f.tipo_abono,
      requer_anexo: nova === "ausencia" ? true : f.requer_anexo,
      aparece_no_app: nova ? f.aparece_no_app : false,
    }));
  };

  const handleEdit = (j: PontoJustificativa) => {
    setEditId(j.id);
    setForm({
      id: j.id,
      nome: j.nome,
      descricao: j.descricao || "",
      horas_abono: Number(j.horas_abono),
      requer_anexo: j.requer_anexo,
      ativo: j.ativo,
      ordem: j.ordem,
      tipo_abono: j.tipo_abono || "nao",
      codigo: j.codigo,
      sistema: j.sistema,
      base_legal: j.base_legal,
      natureza: j.natureza ?? null,
      aparece_no_app: !!j.aparece_no_app,
    });
  };

  const handleSave = async () => {
    if (!form.nome.trim()) return;
    if (avisoDivergencia) {
      const ok = await confirm({
        title: "O nome contradiz a regra de abono",
        description: `${avisoDivergencia}. Quem escolher "${form.nome.trim()}" pode entender o contrário do que o sistema vai aplicar. Salvar mesmo assim?`,
        confirmLabel: "Salvar mesmo assim",
        cancelLabel: "Revisar",
      });
      if (!ok) return;
    }
    await salvar(form);
    reset();
  };

  const handleRemove = async (j: PontoJustificativa) => {
    if (j.sistema) {
      toast.warning("Esta é uma justificativa padrão do sistema e não pode ser excluída. Você pode inativá-la ou ajustar o abono.");
      return;
    }
    const ok = await confirm({
      title: "Remover justificativa",
      description: `Tem certeza que deseja remover "${j.nome}"? Esta ação não pode ser desfeita.`,
      confirmLabel: "Remover",
      cancelLabel: "Cancelar",
      variant: "destructive",
    });
    if (!ok) return;
    await remover(j.id);
    if (editId === j.id) reset();
  };

  return (
    <Dialog open={open} onOpenChange={(v) => { onOpenChange(v); if (!v) reset(); }}>
      <DialogContent className="max-w-4xl max-h-[90vh] flex flex-col">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Clock className="w-5 h-5" /> Justificativas de Ponto
          </DialogTitle>
          <DialogDescription>
            Cadastre os motivos que o gestor pode escolher ao ajustar o ponto. Cada justificativa tem uma regra de <strong>abono automático</strong> (Sim / Não / Configurável), aplicada na aprovação de um lançamento de <strong>dia inteiro</strong>. A <strong>natureza</strong> define o uso no app do colaborador e na tela de ajuste: <em>correção de batida</em> grava o horário como trabalho (nunca abona); <em>ausência</em> exige a declaração ou o atestado anexado e, na aprovação, vira lançamento em <strong>Atestados</strong> com o documento e a regra de abono (não grava marcação). Sem natureza = lançamento só do RH (folga, day off…), fora do app.
          </DialogDescription>
        </DialogHeader>

        {!podeGerenciar && (
          <div className="flex items-center gap-2 text-sm bg-amber-50 dark:bg-amber-950/30 border border-amber-200 dark:border-amber-900 text-amber-800 dark:text-amber-300 rounded-md p-3">
            <ShieldAlert className="w-4 h-4" />
            Apenas perfis Admin, RH ou Dono podem cadastrar/editar justificativas.
          </div>
        )}

        {podeGerenciar && semNaturezaDaEmpresa > 0 && (
          <div data-testid="just-banner-sem-natureza" className="flex items-start gap-2 text-sm bg-sky-50 dark:bg-sky-950/30 border border-sky-200 dark:border-sky-900 text-sky-800 dark:text-sky-300 rounded-md p-3">
            <Smartphone className="w-4 h-4 mt-0.5 shrink-0" />
            <span>
              {semNaturezaDaEmpresa === 1
                ? "1 justificativa criada pela empresa ainda não tem natureza"
                : `${semNaturezaDaEmpresa} justificativas criadas pela empresa ainda não têm natureza`}
              {" "}e não vão aparecer no novo app do colaborador. Edite e escolha <strong>Correção de batida</strong> ou <strong>Ausência</strong> para liberá-las.
            </span>
          </div>
        )}

        {podeGerenciar && (
          <div className="border rounded-md p-3 space-y-3 bg-muted/30">
            <div className="text-sm font-semibold">{editId ? "Editar justificativa" : "Nova justificativa"}</div>
            <div className="grid grid-cols-1 md:grid-cols-12 gap-2">
              <div className="md:col-span-5">
                <Label className="text-xs">Nome *</Label>
                <Input value={form.nome} onChange={(e) => setForm({ ...form, nome: e.target.value })} placeholder="Ex.: Atestado médico" />
              </div>
              <div className="md:col-span-7">
                <Label className="text-xs">Descrição (opcional)</Label>
                <Input value={form.descricao || ""} onChange={(e) => setForm({ ...form, descricao: e.target.value })} placeholder="Quando usar este motivo" />
              </div>
            </div>
            <div className="flex items-center gap-4 text-sm flex-wrap">
              <div className="flex items-center gap-2">
                <Label className="text-xs">Natureza</Label>
                <Select value={natureza ?? NATUREZA_RH} onValueChange={mudarNatureza}>
                  <SelectTrigger data-testid="just-natureza" className="h-8 w-[210px] text-xs"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="correcao_batida" disabled={!!form.base_legal}>Correção de batida</SelectItem>
                    <SelectItem value="ausencia">Ausência (declaração/atestado)</SelectItem>
                    <SelectItem value={NATUREZA_RH}>Só lançamento do RH</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <label className="flex items-center gap-2" title={natureza ? undefined : "Escolha a natureza para liberar no app"}>
                <Switch
                  checked={!!form.aparece_no_app && !!natureza}
                  disabled={!natureza}
                  onCheckedChange={(v) => setForm({ ...form, aparece_no_app: v })}
                />
                <span className={`flex items-center gap-1 ${natureza ? "" : "text-muted-foreground"}`}><Smartphone className="w-3 h-3" /> Aparece no app</span>
              </label>
            </div>
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div className="flex items-center gap-4 text-sm flex-wrap">
                <div className="flex items-center gap-2">
                  <Label className="text-xs">Abono automático</Label>
                  <Select value={(form.tipo_abono as TipoAbono) || "nao"} disabled={!!form.base_legal || natureza === "correcao_batida"} onValueChange={(v) => setForm({ ...form, tipo_abono: v as TipoAbono })}>
                    <SelectTrigger data-testid="just-abono" className="h-8 w-[150px] text-xs"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="sim">Sim (abona)</SelectItem>
                      <SelectItem value="nao">Não abona</SelectItem>
                      <SelectItem value="configuravel">Configurável</SelectItem>
                    </SelectContent>
                  </Select>
                  {form.base_legal ? (
                    <span className="text-[11px] text-muted-foreground inline-flex items-center gap-1">
                      <Scale className="w-3 h-3" /> Abono obrigatório por lei ({form.base_legal})
                    </span>
                  ) : natureza === "correcao_batida" ? (
                    <span className="text-[11px] text-muted-foreground">Não abona (é trabalho)</span>
                  ) : null}
                </div>
                <label className="flex items-center gap-2">
                  <Switch checked={!!form.requer_anexo || natureza === "ausencia"} disabled={natureza === "ausencia"} onCheckedChange={(v) => setForm({ ...form, requer_anexo: v })} />
                  <span className="flex items-center gap-1" title={natureza === "ausencia" ? "Ausência sempre exige a declaração ou o atestado" : undefined}><Paperclip className="w-3 h-3" /> Exigir anexo</span>
                </label>
                <label className="flex items-center gap-2">
                  <Switch checked={form.ativo !== false} onCheckedChange={(v) => setForm({ ...form, ativo: v })} />
                  <span>Ativa</span>
                </label>
              </div>
              <div className="flex gap-2">
                {editId && <Button variant="ghost" size="sm" onClick={reset}><X className="w-4 h-4 mr-1" /> Cancelar</Button>}
                <Button size="sm" onClick={handleSave} disabled={!form.nome.trim() || salvando}>
                  {editId ? <><Save className="w-4 h-4 mr-1" /> Salvar</> : <><Plus className="w-4 h-4 mr-1" /> Adicionar</>}
                </Button>
              </div>
            </div>
            {avisoDivergencia && (
              <div data-testid="just-aviso-divergencia" className="flex items-center gap-2 text-xs bg-amber-50 dark:bg-amber-950/30 border border-amber-200 dark:border-amber-900 text-amber-800 dark:text-amber-300 rounded-md px-3 py-2">
                <AlertTriangle className="w-3.5 h-3.5 shrink-0" />
                {avisoDivergencia}. Confira o nome ou a regra antes de salvar.
              </div>
            )}
          </div>
        )}

        {/* min-h-0 é obrigatório: sem ele o item flex não encolhe e a lista
            estoura o modal sem barra de rolagem (justificativas ficavam cortadas). */}
        <div className="flex-1 min-h-0 overflow-y-auto border rounded-md scrollbar-thin">
          {loading ? (
            <p className="text-center text-sm text-muted-foreground py-8">Carregando…</p>
          ) : justificativas.length === 0 ? (
            <p className="text-center text-sm text-muted-foreground py-8">
              Nenhuma justificativa cadastrada. {podeGerenciar ? "Adicione a primeira acima." : "Aguarde o RH/Dono configurar."}
            </p>
          ) : (
            <table className="w-full text-sm">
              <thead className="bg-muted/50 sticky top-0 z-10">
                <tr className="text-left">
                  <th className="px-3 py-2 font-medium">Nome</th>
                  <th className="px-3 py-2 font-medium w-32">Natureza</th>
                  <th className="px-3 py-2 font-medium w-28">Abono</th>
                  <th className="px-3 py-2 font-medium w-24">Anexo</th>
                  <th className="px-3 py-2 font-medium w-20">No app</th>
                  <th className="px-3 py-2 font-medium w-24">Status</th>
                  {podeGerenciar && <th className="px-3 py-2 w-24"></th>}
                </tr>
              </thead>
              <tbody>
                {justificativas.map((j) => {
                  const divergencia = divergenciaNomeRegra(j.nome, j.tipo_abono);
                  return (
                  <tr key={j.id} className={`border-t ${editId === j.id ? "bg-primary/5" : ""}`}>
                    <td className="px-3 py-2">
                      <div className="font-medium flex items-center gap-1.5">
                        {j.nome}
                        {divergencia && (
                          <span title={divergencia} className="inline-flex"><AlertTriangle className="w-3.5 h-3.5 text-amber-600" aria-label={divergencia} /></span>
                        )}
                        {j.base_legal ? (
                          <Badge variant="outline" className="text-[9px] px-1 py-0 border-indigo-500 text-indigo-700 dark:text-indigo-400">por lei</Badge>
                        ) : j.sistema ? (
                          <Badge variant="secondary" className="text-[9px] px-1 py-0">padrão</Badge>
                        ) : null}
                      </div>
                      {j.base_legal ? (
                        <div className="text-[11px] text-muted-foreground inline-flex items-center gap-1"><Scale className="w-3 h-3" /> {j.base_legal}</div>
                      ) : j.descricao ? (
                        <div className="text-xs text-muted-foreground">{j.descricao}</div>
                      ) : null}
                    </td>
                    <td className="px-3 py-2 text-xs">{NATUREZA_LABEL[j.natureza ?? NATUREZA_RH]}</td>
                    <td className="px-3 py-2">
                      <Badge variant="outline" className={`text-[10px] ${ABONO_BADGE[j.tipo_abono || "nao"]}`}>
                        {ABONO_LABEL[j.tipo_abono || "nao"]}
                      </Badge>
                    </td>
                    <td className="px-3 py-2 text-xs">{j.requer_anexo ? "Obrigatório" : "Opcional"}</td>
                    <td className="px-3 py-2 text-xs">{j.aparece_no_app && j.natureza ? "Sim" : "Não"}</td>
                    <td className="px-3 py-2">
                      <Badge variant={j.ativo ? "outline" : "secondary"} className={j.ativo ? "border-emerald-500 text-emerald-700 dark:text-emerald-400" : ""}>
                        {j.ativo ? "Ativa" : "Inativa"}
                      </Badge>
                    </td>
                    {podeGerenciar && (
                      <td className="px-3 py-2 text-right">
                        <Button size="icon" variant="ghost" className="h-7 w-7" onClick={() => handleEdit(j)}><Pencil className="w-3.5 h-3.5" /></Button>
                        {!j.sistema && (
                          <Button size="icon" variant="ghost" className="h-7 w-7 text-destructive" onClick={() => handleRemove(j)}><Trash2 className="w-3.5 h-3.5" /></Button>
                        )}
                      </td>
                    )}
                  </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>

        <div className="flex justify-end pt-2">
          <Button variant="outline" onClick={() => onOpenChange(false)}>Fechar</Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
