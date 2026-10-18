import { useState } from "react";
import { format } from "date-fns";
import { toast } from "sonner";
import { proximaExecucaoRitual } from "@/lib/celebracoes";
import { PartyPopper, CheckCheck, Wand2, Plus, Trash2, ToggleLeft, ToggleRight, Settings2, CalendarDays } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import type { CulturaRitual, CulturaData, CulturaConfig, CulturaMarco } from "@/types/cultura";
import { FREQUENCIA_LABELS, TIPO_DATA_LABELS, CELEBRACAO_LABELS } from "@/types/cultura";

interface Props {
  rituais: CulturaRitual[];
  datas: CulturaData[];
  config: CulturaConfig | null;
  marcos: CulturaMarco[];
  isLoadingRituais: boolean;
  isLoadingDatas: boolean;
  onCreateRitual: (data: Partial<CulturaRitual>) => Promise<void>;
  onToggleRitual: (id: string, ativo: boolean) => Promise<void>;
  onDeleteRitual: (id: string) => Promise<void>;
  onRegistrarRitual: (r: CulturaRitual) => Promise<void>;
  onGerarAcoes: () => Promise<number>;
  onCreateData: (data: Partial<CulturaData>) => Promise<void>;
  onDeleteData: (id: string) => Promise<void>;
  onSaveConfig: (data: Partial<CulturaConfig>) => Promise<void>;
  onCreateMarco: (data: Partial<CulturaMarco>) => Promise<void>;
}

export const RituaisReconhecimento = ({
  rituais, datas, config, marcos,
  isLoadingRituais, isLoadingDatas,
  onCreateRitual, onToggleRitual, onDeleteRitual, onRegistrarRitual, onGerarAcoes,
  onCreateData, onDeleteData,
  onSaveConfig, onCreateMarco,
}: Props) => {
  const [gerando, setGerando] = useState(false);
  const [showRitualForm, setShowRitualForm] = useState(false);
  const [showDataForm, setShowDataForm] = useState(false);
  const [showMarcoForm, setShowMarcoForm] = useState(false);

  const [ritualForm, setRitualForm] = useState({ nome: "", descricao: "", frequencia: "mensal", responsavel_nome: "" });
  const [dataForm, setDataForm] = useState({ titulo: "", descricao: "", tipo: "comemorativa", recorrencia: "anual", mes: "", dia: "" });
  const [marcoForm, setMarcoForm] = useState({ anos: "", tipo_celebracao: "reconhecimento", descricao: "" });

  const handleCreateRitual = async () => {
    if (!ritualForm.nome) return;
    await onCreateRitual({ nome: ritualForm.nome, descricao: ritualForm.descricao || null, frequencia: ritualForm.frequencia, responsavel_nome: ritualForm.responsavel_nome || null });
    setShowRitualForm(false);
    setRitualForm({ nome: "", descricao: "", frequencia: "mensal", responsavel_nome: "" });
  };

  const handleCreateData = async () => {
    if (!dataForm.titulo) return;
    await onCreateData({
      titulo: dataForm.titulo,
      descricao: dataForm.descricao || null,
      tipo: dataForm.tipo,
      recorrencia: dataForm.recorrencia,
      mes: dataForm.mes ? parseInt(dataForm.mes) : null,
      dia: dataForm.dia ? parseInt(dataForm.dia) : null,
    });
    setShowDataForm(false);
    setDataForm({ titulo: "", descricao: "", tipo: "comemorativa", recorrencia: "anual", mes: "", dia: "" });
  };

  const handleCreateMarco = async () => {
    if (!marcoForm.anos) return;
    await onCreateMarco({ anos: parseInt(marcoForm.anos), tipo_celebracao: marcoForm.tipo_celebracao, descricao: marcoForm.descricao || null });
    setShowMarcoForm(false);
    setMarcoForm({ anos: "", tipo_celebracao: "reconhecimento", descricao: "" });
  };

  return (
    <Tabs defaultValue="rituais" className="space-y-4">
      <TabsList>
        <TabsTrigger value="rituais">Rituais Culturais</TabsTrigger>
        <TabsTrigger value="datas">Datas Configuráveis</TabsTrigger>
        <TabsTrigger value="marcos">Marcos de Tempo</TabsTrigger>
        <TabsTrigger value="config">Configuração</TabsTrigger>
      </TabsList>

      {/* Rituais */}
      <TabsContent value="rituais" className="space-y-4">
        <div className="flex justify-end">
          <Button size="sm" onClick={() => setShowRitualForm(true)} className="gap-1">
            <Plus className="w-4 h-4" /> Novo Ritual
          </Button>
        </div>
        {rituais.length === 0 ? (
          <Card className="p-10 text-center">
            <PartyPopper className="w-10 h-10 mx-auto text-muted-foreground/40 mb-2" />
            <p className="text-sm text-muted-foreground">Nenhum ritual configurado</p>
            <p className="text-xs text-muted-foreground mt-1">Defina rituais recorrentes para engajar a equipe</p>
          </Card>
        ) : (
          <div className="grid gap-3">
            {rituais.map((r) => (
              <Card key={r.id} className="p-4 flex items-center justify-between gap-3">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-0.5">
                    <h4 className="font-medium text-sm">{r.nome}</h4>
                    <Badge variant="outline" className="text-[10px]">{FREQUENCIA_LABELS[r.frequencia]}</Badge>
                    <Badge variant={r.ativo ? "default" : "secondary"} className="text-[10px]">
                      {r.ativo ? "Ativo" : "Inativo"}
                    </Badge>
                  </div>
                  {r.descricao && <p className="text-xs text-muted-foreground">{r.descricao}</p>}
                  {r.responsavel_nome && <p className="text-xs text-muted-foreground">Responsável: {r.responsavel_nome}</p>}
                  {r.ativo && (
                    <p className="text-xs text-muted-foreground">
                      {(() => {
                        const prox = proximaExecucaoRitual(r);
                        return prox ? `Próximo: ${format(prox, "dd/MM/yyyy")}` : "Ainda não realizado: registre a primeira realização";
                      })()}
                    </p>
                  )}
                </div>
                <div className="flex items-center gap-1 shrink-0">
                  {r.ativo && (
                    <Button size="sm" variant="outline" className="h-7 px-2 text-xs gap-1" onClick={() => onRegistrarRitual(r)}>
                      <CheckCheck className="w-3.5 h-3.5" /> Registrar realização
                    </Button>
                  )}
                  <Button size="icon" variant="ghost" className="h-7 w-7" onClick={() => onToggleRitual(r.id, !r.ativo)}>
                    {r.ativo ? <ToggleRight className="w-4 h-4 text-emerald-600" /> : <ToggleLeft className="w-4 h-4 text-muted-foreground" />}
                  </Button>
                  <Button size="icon" variant="ghost" className="h-7 w-7 text-destructive" onClick={() => onDeleteRitual(r.id)}>
                    <Trash2 className="w-3.5 h-3.5" />
                  </Button>
                </div>
              </Card>
            ))}
          </div>
        )}
      </TabsContent>

      {/* Datas configuráveis */}
      <TabsContent value="datas" className="space-y-4">
        <div className="flex justify-end">
          <Button size="sm" onClick={() => setShowDataForm(true)} className="gap-1">
            <Plus className="w-4 h-4" /> Nova Data
          </Button>
        </div>
        {datas.length === 0 ? (
          <Card className="p-10 text-center">
            <CalendarDays className="w-10 h-10 mx-auto text-muted-foreground/40 mb-2" />
            <p className="text-sm text-muted-foreground">Nenhuma data configurada</p>
          </Card>
        ) : (
          <div className="grid gap-3">
            {datas.map((d) => (
              <Card key={d.id} className="p-4 flex items-center justify-between gap-3">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-0.5">
                    <h4 className="font-medium text-sm">{d.titulo}</h4>
                    <Badge variant="outline" className="text-[10px]">{TIPO_DATA_LABELS[d.tipo]}</Badge>
                  </div>
                  {d.descricao && <p className="text-xs text-muted-foreground">{d.descricao}</p>}
                  <p className="text-xs text-muted-foreground">
                    {d.dia && d.mes ? `Dia ${d.dia}/${String(d.mes).padStart(2, "0")}` : d.recorrencia}
                  </p>
                </div>
                <Button size="icon" variant="ghost" className="h-7 w-7 text-destructive" onClick={() => onDeleteData(d.id)}>
                  <Trash2 className="w-3.5 h-3.5" />
                </Button>
              </Card>
            ))}
          </div>
        )}
      </TabsContent>

      {/* Marcos */}
      <TabsContent value="marcos" className="space-y-4">
        <div className="flex justify-end">
          <Button size="sm" onClick={() => setShowMarcoForm(true)} className="gap-1">
            <Plus className="w-4 h-4" /> Novo Marco
          </Button>
        </div>
        {marcos.length === 0 ? (
          <Card className="p-10 text-center">
            <p className="text-sm text-muted-foreground">Nenhum marco configurado</p>
            <p className="text-xs text-muted-foreground mt-1">Defina marcos de tempo de casa (1, 5, 10 anos…)</p>
          </Card>
        ) : (
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {marcos.map((m) => (
              <Card key={m.id} className="p-4">
                <div className="flex items-center gap-2 mb-1">
                  <span className="text-lg font-bold">{m.anos}</span>
                  <span className="text-sm text-muted-foreground">{m.anos === 1 ? "ano" : "anos"}</span>
                </div>
                <Badge variant="outline" className="text-[10px]">{CELEBRACAO_LABELS[m.tipo_celebracao] || m.tipo_celebracao}</Badge>
                {m.descricao && <p className="text-xs text-muted-foreground mt-1">{m.descricao}</p>}
              </Card>
            ))}
          </div>
        )}
      </TabsContent>

      {/* Config */}
      <TabsContent value="config" className="space-y-4">
        <Card className="p-6 space-y-5">
          <h3 className="font-medium flex items-center gap-2">
            <Settings2 className="w-4 h-4" /> Configurações do Módulo
          </h3>
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium">Aniversário do Colaborador</p>
                <p className="text-xs text-muted-foreground">Gerar ações automáticas para aniversários</p>
              </div>
              <Switch checked={config?.aniversario_ativo ?? true} onCheckedChange={v => onSaveConfig({ aniversario_ativo: v })} />
            </div>
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium">Tempo de Casa</p>
                <p className="text-xs text-muted-foreground">Celebrar marcos de tempo na empresa</p>
              </div>
              <Switch checked={config?.tempo_casa_ativo ?? true} onCheckedChange={v => onSaveConfig({ tempo_casa_ativo: v })} />
            </div>
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium">Dia da Profissão</p>
                <p className="text-xs text-muted-foreground">Identificar automaticamente dias de profissões</p>
              </div>
              <Switch checked={config?.dia_profissao_ativo ?? true} onCheckedChange={v => onSaveConfig({ dia_profissao_ativo: v })} />
            </div>
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium">Presente Padrão</p>
                <p className="text-xs text-muted-foreground">Empresa oferece presente em aniversários</p>
              </div>
              <Switch checked={config?.presente_padrao ?? false} onCheckedChange={v => onSaveConfig({ presente_padrao: v })} />
            </div>
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium">Folga Permitida</p>
                <p className="text-xs text-muted-foreground">Colaborador pode ganhar folga no aniversário</p>
              </div>
              <Switch checked={config?.folga_permitida ?? false} onCheckedChange={v => onSaveConfig({ folga_permitida: v })} />
            </div>
            <div>
              <Label>Limite de valor do presente (R$)</Label>
              <Input
                type="number"
                className="w-32 mt-1"
                placeholder="Sem limite"
                value={config?.limite_valor_presente ?? ""}
                onChange={e => onSaveConfig({ limite_valor_presente: e.target.value ? parseFloat(e.target.value) : null })}
              />
              <p className="text-xs text-muted-foreground mt-1">Deixe vazio para sem limite</p>
            </div>
            <div>
              <Label>Dias de antecedência para criar ação</Label>
              <Input
                type="number"
                className="w-24 mt-1"
                value={config?.dias_antecedencia_acao ?? 7}
                onChange={e => onSaveConfig({ dias_antecedencia_acao: parseInt(e.target.value) || 7 })}
              />
            </div>
            <div>
              <Label>Meta de cobertura de celebração (%)</Label>
              <Input
                type="number"
                min={1}
                max={100}
                className="w-24 mt-1"
                value={config?.meta_cobertura ?? 95}
                onChange={e => {
                  const v = parseInt(e.target.value);
                  if (v >= 1 && v <= 100) onSaveConfig({ meta_cobertura: v });
                }}
              />
              <p className="text-xs text-muted-foreground mt-1">Abaixo da meta, a tela alerta e sugere uma ação no Plano de Ação</p>
            </div>
            <div>
              <Label>Responsável padrão</Label>
              <Select value={config?.responsavel_padrao ?? "rh"} onValueChange={v => onSaveConfig({ responsavel_padrao: v })}>
                <SelectTrigger className="w-48 mt-1"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="rh">RH</SelectItem>
                  <SelectItem value="lider">Líder Direto</SelectItem>
                  <SelectItem value="cultura">Cultura</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
        </Card>

        <Card className="p-6 space-y-4" data-testid="config-automacao">
          <h3 className="font-medium flex items-center gap-2">
            <Wand2 className="w-4 h-4" /> Automação
          </h3>
          <p className="text-xs text-muted-foreground">
            Todo dia a rotina cria, sozinha, a ação <strong>pendente</strong> de cada celebração que cai dentro dos dias de
            antecedência acima. Ela nunca conclui, nunca publica no Mural e nunca concede presente ou folga: parabenizar e
            publicar continuam sendo um clique seu, e quem pediu reconhecimento reservado nunca é publicado.
          </p>
          {([
            ["automacao_aniversario", "Aniversário"],
            ["automacao_tempo_casa", "Tempo de casa"],
          ] as const).map(([campo, rotulo]) => (
            <div key={campo} className="flex items-center justify-between gap-3 flex-wrap">
              <p className="text-sm font-medium">{rotulo}</p>
              <Select value={config?.[campo] ?? "desligado"} onValueChange={v => onSaveConfig({ [campo]: v } as Partial<CulturaConfig>)}>
                <SelectTrigger className="w-full sm:w-64"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="desligado">Desligada: eu crio as ações</SelectItem>
                  <SelectItem value="aprovar">Criar ação pendente sozinha</SelectItem>
                </SelectContent>
              </Select>
            </div>
          ))}
          <div className="flex items-center justify-between gap-3 flex-wrap">
            <div>
              <p className="text-sm font-medium">Tom das mensagens sugeridas</p>
              <p className="text-xs text-muted-foreground">Usado pela Íris ao sugerir o texto de parabéns</p>
            </div>
            <Select value={config?.tom_mensagem ?? "leve"} onValueChange={v => onSaveConfig({ tom_mensagem: v } as Partial<CulturaConfig>)}>
              <SelectTrigger className="w-full sm:w-64"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="leve">Leve e acolhedor</SelectItem>
                <SelectItem value="formal">Formal</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="flex items-center justify-between gap-3">
            <div>
              <p className="text-sm font-medium">Lembrar os gestores</p>
              <p className="text-xs text-muted-foreground">
                No Mural, cada gestor vê as celebrações do próprio time, com mensagem sugerida. O time vem do cadastro:
                o gestor imediato do colaborador (nome igual ao do gestor) ou o departamento em que a pessoa é gestora.
              </p>
            </div>
            <Switch checked={config?.lembrar_gestor ?? false} onCheckedChange={v => onSaveConfig({ lembrar_gestor: v })} />
          </div>
          <div className="flex items-center justify-between gap-3 flex-wrap pt-2 border-t">
            <p className="text-xs text-muted-foreground">A rotina roda todo dia às 6h. Para ver o efeito agora:</p>
            <Button
              size="sm"
              variant="outline"
              disabled={gerando}
              onClick={async () => {
                setGerando(true);
                try {
                  const n = await onGerarAcoes();
                  toast.success(n > 0 ? `${n} ação${n > 1 ? "ões criadas" : " criada"}` : "Nada novo para criar agora");
                } catch {
                  /* o hook já avisou o erro */
                } finally {
                  setGerando(false);
                }
              }}
            >
              Gerar ações agora
            </Button>
          </div>
        </Card>
      </TabsContent>

      {/* Modals */}
      <Dialog open={showRitualForm} onOpenChange={setShowRitualForm}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Novo Ritual Cultural</DialogTitle>
            <DialogDescription>Crie um ritual recorrente para a equipe</DialogDescription>
          </DialogHeader>
          <div className="space-y-3">
            <div><Label>Nome *</Label><Input value={ritualForm.nome} onChange={e => setRitualForm(f => ({ ...f, nome: e.target.value }))} /></div>
            <div>
              <Label>Frequência</Label>
              <Select value={ritualForm.frequencia} onValueChange={v => setRitualForm(f => ({ ...f, frequencia: v }))}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {Object.entries(FREQUENCIA_LABELS).map(([k, v]) => <SelectItem key={k} value={k}>{v}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div><Label>Responsável</Label><Input value={ritualForm.responsavel_nome} onChange={e => setRitualForm(f => ({ ...f, responsavel_nome: e.target.value }))} /></div>
            <div><Label>Descrição</Label><Textarea value={ritualForm.descricao} onChange={e => setRitualForm(f => ({ ...f, descricao: e.target.value }))} rows={2} /></div>
            <Button onClick={handleCreateRitual} className="w-full">Criar Ritual</Button>
          </div>
        </DialogContent>
      </Dialog>

      <Dialog open={showDataForm} onOpenChange={setShowDataForm}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Nova Data Comemorativa</DialogTitle>
            <DialogDescription>Configure uma data especial para a empresa</DialogDescription>
          </DialogHeader>
          <div className="space-y-3">
            <div><Label>Título *</Label><Input value={dataForm.titulo} onChange={e => setDataForm(f => ({ ...f, titulo: e.target.value }))} /></div>
            <div>
              <Label>Tipo</Label>
              <Select value={dataForm.tipo} onValueChange={v => setDataForm(f => ({ ...f, tipo: v }))}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {Object.entries(TIPO_DATA_LABELS).map(([k, v]) => <SelectItem key={k} value={k}>{v}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div><Label>Dia</Label><Input type="number" min={1} max={31} value={dataForm.dia} onChange={e => setDataForm(f => ({ ...f, dia: e.target.value }))} /></div>
              <div><Label>Mês</Label><Input type="number" min={1} max={12} value={dataForm.mes} onChange={e => setDataForm(f => ({ ...f, mes: e.target.value }))} /></div>
            </div>
            <div><Label>Descrição</Label><Textarea value={dataForm.descricao} onChange={e => setDataForm(f => ({ ...f, descricao: e.target.value }))} rows={2} /></div>
            <Button onClick={handleCreateData} className="w-full">Criar Data</Button>
          </div>
        </DialogContent>
      </Dialog>

      <Dialog open={showMarcoForm} onOpenChange={setShowMarcoForm}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>Novo Marco de Tempo</DialogTitle>
            <DialogDescription>Defina um marco de celebração por tempo de casa</DialogDescription>
          </DialogHeader>
          <div className="space-y-3">
            <div><Label>Anos *</Label><Input type="number" min={1} value={marcoForm.anos} onChange={e => setMarcoForm(f => ({ ...f, anos: e.target.value }))} /></div>
            <div>
              <Label>Tipo de Celebração</Label>
              <Select value={marcoForm.tipo_celebracao} onValueChange={v => setMarcoForm(f => ({ ...f, tipo_celebracao: v }))}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {Object.entries(CELEBRACAO_LABELS).map(([k, v]) => <SelectItem key={k} value={k}>{v}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div><Label>Descrição</Label><Textarea value={marcoForm.descricao} onChange={e => setMarcoForm(f => ({ ...f, descricao: e.target.value }))} rows={2} /></div>
            <Button onClick={handleCreateMarco} className="w-full">Criar Marco</Button>
          </div>
        </DialogContent>
      </Dialog>
    </Tabs>
  );
};
