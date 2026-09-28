import { useState, useCallback } from "react";
import { Plus, Trash2, ChevronDown, ChevronRight, Link2, Wrench, Users, ExternalLink, HelpCircle, Pencil, Check, X, AlertTriangle, Sparkles, Zap } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Label } from "@/components/ui/label";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import { useAprendizado } from "@/hooks/useAprendizado";
import { usePopAtividade } from "@/hooks/usePopAtividade";
import { PopSection } from "./PopSection";
import { GerarPopsEmLoteModal } from "./GerarPopsEmLoteModal";
import { ExportarTodosPopsPdf } from "./ExportarTodosPopsPdf";
import { AudioAtividadesImport } from "./AudioAtividadesImport";
import { TextoAtividadesImport } from "./TextoAtividadesImport";
import type { FuncaoAtividade } from "@/types/aprendizado";

interface AtividadesSectionProps {
  cargoId: string;
  funcaoNome?: string;
  nivel?: string;
}

const FREQ_LABELS: Record<string, string> = { diaria: "Diária", semanal: "Semanal", mensal: "Mensal", eventual: "Eventual" };
const COMPL_LABELS: Record<string, string> = { baixa: "Baixa", media: "Média", alta: "Alta" };
const CLASS_LABELS: Record<string, string> = { rotineira: "Rotineira", critica: "Crítica", excepcional: "Excepcional" };
const TIPO_CONTEUDO_LABELS: Record<string, string> = { manual: "Manual", pop: "POP", instrucao: "Instrução", video: "Vídeo", apresentacao: "Apresentação", documento: "Documento", link: "Link" };
const TIPO_FERRAMENTA_LABELS: Record<string, string> = { sistema: "Sistema", software: "Software", planilha: "Planilha", equipamento: "Equipamento" };

export function AtividadesSection({ cargoId, funcaoNome, nivel }: AtividadesSectionProps) {
  const {
    atividades, criarAtividade, criarAtividadesLote, atualizarAtividade, atualizandoAtividade, excluirAtividade, criandoAtividade,
    responsabilidades, salvarResponsabilidade,
    conteudos, criarConteudo, excluirConteudo,
    ferramentas, criarFerramenta, excluirFerramenta,
  } = useAprendizado(cargoId);

  const { pops, getPopByAtividade, criarPop, gerarPopIA } = usePopAtividade(cargoId, funcaoNome);

  const [showForm, setShowForm] = useState(false);
  const [showLoteModal, setShowLoteModal] = useState(false);
  const [nome, setNome] = useState("");
  const [descricao, setDescricao] = useState("");
  const [frequencia, setFrequencia] = useState("diaria");
  const [complexidade, setComplexidade] = useState("media");
  const [classificacao, setClassificacao] = useState("rotineira");

  const [expandedId, setExpandedId] = useState<string | null>(null);

  // Sub-forms state
  const [conteudoForm, setConteudoForm] = useState<{ atividadeId: string; tipo: string; titulo: string; url: string } | null>(null);
  const [ferramentaForm, setFerramentaForm] = useState<{ atividadeId: string; nome: string; tipo: string; url_manual: string } | null>(null);
  const [respForm, setRespForm] = useState<{ atividadeId: string; responsavel: string; interfaces: string; consequencia: string } | null>(null);
  const [editingDescId, setEditingDescId] = useState<string | null>(null);
  const [editingDescValue, setEditingDescValue] = useState("");
  const [popDesatualizadoId, setPopDesatualizadoId] = useState<string | null>(null);

  // Editing header fields state
  const [editingHeaderId, setEditingHeaderId] = useState<string | null>(null);
  const [editingHeaderValues, setEditingHeaderValues] = useState<{ nome: string; frequencia: string; complexidade: string; classificacao: string }>({ nome: "", frequencia: "diaria", complexidade: "media", classificacao: "rotineira" });

  const handleSaveHeader = useCallback(async (atividadeId: string) => {
    await atualizarAtividade({
      id: atividadeId,
      nome: editingHeaderValues.nome,
      frequencia: editingHeaderValues.frequencia as any,
      complexidade: editingHeaderValues.complexidade as any,
      classificacao: editingHeaderValues.classificacao as any,
    });
    setEditingHeaderId(null);
  }, [editingHeaderValues, atualizarAtividade]);

  const handleSaveDesc = useCallback(async (atividadeId: string) => {
    const original = atividades.find(a => a.id === atividadeId);
    if (original && original.descricao !== editingDescValue) {
      await atualizarAtividade({ id: atividadeId, descricao: editingDescValue });
      // Show desatualizado notice if POP exists
      setPopDesatualizadoId(atividadeId);
    }
    setEditingDescId(null);
  }, [atividades, editingDescValue, atualizarAtividade]);

  const handleCreate = async () => {
    if (!nome.trim()) return;
    await criarAtividade({ nome, descricao: descricao || undefined, frequencia: frequencia as any, complexidade: complexidade as any, classificacao: classificacao as any });
    setNome(""); setDescricao(""); setShowForm(false);
  };

  const complColor: Record<string, string> = { baixa: "bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300", media: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-300", alta: "bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-300" };
  const classColor: Record<string, string> = { rotineira: "bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-300", critica: "bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-300", excepcional: "bg-purple-100 text-purple-800 dark:bg-purple-900/30 dark:text-purple-300" };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="font-semibold text-foreground">Atividades ({atividades.length})</h3>
        <div className="flex gap-2">
          <AudioAtividadesImport
            funcaoNome={funcaoNome}
            onImportar={async (atividades) => {
              await criarAtividadesLote(
                atividades.map((at) => ({
                  nome: at.nome,
                  descricao: at.descricao,
                  frequencia: at.frequencia as any,
                  complexidade: at.complexidade as any,
                  classificacao: at.classificacao as any,
                }))
              );
            }}
          />
          <TextoAtividadesImport
            funcaoNome={funcaoNome}
            onImportar={async (atividades) => {
              await criarAtividadesLote(
                atividades.map((at) => ({
                  nome: at.nome,
                  descricao: at.descricao,
                  frequencia: at.frequencia as any,
                  complexidade: at.complexidade as any,
                  classificacao: at.classificacao as any,
                }))
              );
            }}
          />
          {(() => {
            const semPop = atividades.filter(a => !getPopByAtividade(a.id));
            if (semPop.length > 0) {
              return (
                <Button size="sm" variant="outline" className="gap-1" onClick={() => setShowLoteModal(true)}>
                  <Zap className="w-4 h-4" /> Gerar POPs ({semPop.length})
                </Button>
              );
            }
            return null;
          })()}
          <ExportarTodosPopsPdf pops={pops} funcaoNome={funcaoNome} />
          <Button size="sm" onClick={() => setShowForm(!showForm)}>
            <Plus className="w-4 h-4 mr-1" /> Atividade
          </Button>
        </div>
      </div>

      {showForm && (
        <Card>
          <CardContent className="p-4 space-y-3">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              <div className="space-y-1">
                <Label>Nome *</Label>
                <Input value={nome} onChange={(e) => setNome(e.target.value)} placeholder="Nome da atividade" />
              </div>
              <div className="grid grid-cols-3 gap-2">
                <div className="space-y-1">
                  <Label>Frequência</Label>
                  <Select value={frequencia} onValueChange={setFrequencia}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      {Object.entries(FREQ_LABELS).map(([k, v]) => <SelectItem key={k} value={k}>{v}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-1">
                  <Label>Complexidade</Label>
                  <Select value={complexidade} onValueChange={setComplexidade}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      {Object.entries(COMPL_LABELS).map(([k, v]) => <SelectItem key={k} value={k}>{v}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-1">
                  <Label>Classificação</Label>
                  <Select value={classificacao} onValueChange={setClassificacao}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      {Object.entries(CLASS_LABELS).map(([k, v]) => <SelectItem key={k} value={k}>{v}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
              </div>
            </div>
            <div className="space-y-1">
              <Label>Descrição</Label>
              <Textarea value={descricao} onChange={(e) => setDescricao(e.target.value)} placeholder="O que é feito no dia a dia" rows={2} />
            </div>
            <div className="flex gap-2 justify-end">
              <Button variant="ghost" size="sm" onClick={() => setShowForm(false)}>Cancelar</Button>
              <Button size="sm" onClick={handleCreate} disabled={criandoAtividade || !nome.trim()}>Salvar</Button>
            </div>
          </CardContent>
        </Card>
      )}

      {atividades.length === 0 && !showForm && (
        <div className="text-center py-8 text-muted-foreground text-sm">
          Nenhuma atividade cadastrada. Clique em "+ Atividade" para começar.
        </div>
      )}

      {/* Group activities by process */}
      {(() => {
        const processos = new Map<string, typeof atividades>();
        atividades.forEach((at) => {
          const proc = (at as any).processo || "Geral";
          if (!processos.has(proc)) processos.set(proc, []);
          processos.get(proc)!.push(at);
        });

        return Array.from(processos.entries()).map(([processo, procAtividades]) => (
          <div key={processo} className="space-y-2">
            {processos.size > 1 && (
              <div className="flex items-center gap-2 mt-2">
                <span className="text-xs font-semibold text-primary uppercase tracking-wide">🔹 {processo}</span>
                <span className="text-xs text-muted-foreground">({procAtividades.length})</span>
              </div>
            )}
            {procAtividades.map((at) => {
        const atConteudos = conteudos.filter((c) => c.atividade_id === at.id);
        const atFerramentas = ferramentas.filter((f) => f.atividade_id === at.id);
        const atResp = responsabilidades.find((r) => r.atividade_id === at.id);
        const isExpanded = expandedId === at.id;

        return (
          <Collapsible key={at.id} open={isExpanded} onOpenChange={() => setExpandedId(isExpanded ? null : at.id)}>
            <Card>
              {editingHeaderId === at.id ? (
                <CardHeader className="p-4">
                  <div className="space-y-3">
                    <div className="flex items-center gap-2">
                      <Input
                        value={editingHeaderValues.nome}
                        onChange={(e) => setEditingHeaderValues(v => ({ ...v, nome: e.target.value }))}
                        className="text-sm font-medium flex-1"
                        placeholder="Nome da atividade"
                        autoFocus
                        onClick={(e) => e.stopPropagation()}
                      />
                      <Button variant="ghost" size="icon" className="h-7 w-7 shrink-0" onClick={(e) => { e.stopPropagation(); handleSaveHeader(at.id); }} disabled={atualizandoAtividade || !editingHeaderValues.nome.trim()}>
                        <Check className="w-4 h-4 text-green-600" />
                      </Button>
                      <Button variant="ghost" size="icon" className="h-7 w-7 shrink-0" onClick={(e) => { e.stopPropagation(); setEditingHeaderId(null); }}>
                        <X className="w-4 h-4 text-destructive" />
                      </Button>
                    </div>
                    <div className="grid grid-cols-3 gap-2">
                      <div className="space-y-1">
                        <Label className="text-xs">Frequência</Label>
                        <Select value={editingHeaderValues.frequencia} onValueChange={(v) => setEditingHeaderValues(prev => ({ ...prev, frequencia: v }))}>
                          <SelectTrigger className="h-8 text-xs"><SelectValue /></SelectTrigger>
                          <SelectContent>{Object.entries(FREQ_LABELS).map(([k, lbl]) => <SelectItem key={k} value={k}>{lbl}</SelectItem>)}</SelectContent>
                        </Select>
                      </div>
                      <div className="space-y-1">
                        <Label className="text-xs">Complexidade</Label>
                        <Select value={editingHeaderValues.complexidade} onValueChange={(v) => setEditingHeaderValues(prev => ({ ...prev, complexidade: v }))}>
                          <SelectTrigger className="h-8 text-xs"><SelectValue /></SelectTrigger>
                          <SelectContent>{Object.entries(COMPL_LABELS).map(([k, lbl]) => <SelectItem key={k} value={k}>{lbl}</SelectItem>)}</SelectContent>
                        </Select>
                      </div>
                      <div className="space-y-1">
                        <Label className="text-xs">Classificação</Label>
                        <Select value={editingHeaderValues.classificacao} onValueChange={(v) => setEditingHeaderValues(prev => ({ ...prev, classificacao: v }))}>
                          <SelectTrigger className="h-8 text-xs"><SelectValue /></SelectTrigger>
                          <SelectContent>{Object.entries(CLASS_LABELS).map(([k, lbl]) => <SelectItem key={k} value={k}>{lbl}</SelectItem>)}</SelectContent>
                        </Select>
                      </div>
                    </div>
                  </div>
                </CardHeader>
              ) : (
              <CollapsibleTrigger asChild>
                <CardHeader className="p-4 cursor-pointer hover:bg-muted/30 transition-colors">
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      {isExpanded ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}
                      <CardTitle className="text-sm">{at.nome}</CardTitle>
                    </div>
                    <div className="flex items-center gap-2">
                      <Badge variant="outline" className="text-xs">{FREQ_LABELS[at.frequencia]}</Badge>
                      <Badge className={`text-xs ${complColor[at.complexidade]}`}>{COMPL_LABELS[at.complexidade]}</Badge>
                      <Badge className={`text-xs ${classColor[at.classificacao]}`}>{CLASS_LABELS[at.classificacao]}</Badge>
                      <Button variant="ghost" size="icon" className="h-7 w-7" onClick={(e) => { e.stopPropagation(); setEditingHeaderId(at.id); setEditingHeaderValues({ nome: at.nome, frequencia: at.frequencia, complexidade: at.complexidade, classificacao: at.classificacao }); }}>
                        <Pencil className="w-3.5 h-3.5 text-muted-foreground" />
                      </Button>
                      <Button variant="ghost" size="icon" className="h-7 w-7" onClick={(e) => { e.stopPropagation(); excluirAtividade(at.id); }}>
                        <Trash2 className="w-3.5 h-3.5 text-destructive" />
                      </Button>
                    </div>
                  </div>
                </CardHeader>
              </CollapsibleTrigger>
              )}
              <CollapsibleContent>
                <CardContent className="p-4 pt-0 space-y-4 border-t">
                  {/* Descrição editável */}
                  <div className="space-y-1">
                    {editingDescId === at.id ? (
                      <div className="flex gap-2 items-start">
                        <Textarea
                          value={editingDescValue}
                          onChange={(e) => setEditingDescValue(e.target.value)}
                          rows={2}
                          className="text-sm flex-1"
                        />
                        <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => handleSaveDesc(at.id)} disabled={atualizandoAtividade}>
                          <Check className="w-4 h-4 text-green-600" />
                        </Button>
                        <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => setEditingDescId(null)}>
                          <X className="w-4 h-4 text-destructive" />
                        </Button>
                      </div>
                    ) : (
                      <p
                        className="text-sm text-muted-foreground cursor-pointer hover:bg-muted/30 rounded px-2 py-1 -mx-2 group flex items-center gap-1"
                        onClick={() => { setEditingDescId(at.id); setEditingDescValue(at.descricao || ""); }}
                      >
                        {at.descricao || <span className="italic">Sem descrição — clique para adicionar</span>}
                        <Pencil className="w-3 h-3 opacity-0 group-hover:opacity-50 transition-opacity" />
                      </p>
                    )}

                    {/* Alerta POP desatualizado */}
                    {popDesatualizadoId === at.id && (
                      <div className="flex items-center gap-2 bg-warning/10 border border-warning/30 rounded-lg px-3 py-2 text-sm">
                        <AlertTriangle className="w-4 h-4 text-warning shrink-0" />
                        <span className="flex-1 text-foreground">A descrição foi alterada. O POP vinculado foi marcado como <strong>Desatualizado</strong>.</span>
                        <Button
                          variant="outline"
                          size="sm"
                          className="gap-1 text-xs"
                          onClick={() => { setPopDesatualizadoId(null); setExpandedId(at.id); }}
                        >
                          <Sparkles className="w-3 h-3" /> Atualizar POP com IA
                        </Button>
                        <Button variant="ghost" size="sm" className="text-xs" onClick={() => setPopDesatualizadoId(null)}>
                          Manter como está
                        </Button>
                      </div>
                    )}
                  </div>

                  {/* Responsabilidades */}
                  <div className="space-y-2">
                    <div className="flex items-center gap-2 text-sm font-medium">
                      <Users className="w-4 h-4" /> Matriz de Responsabilidade
                    </div>
                    {respForm?.atividadeId === at.id ? (
                      <TooltipProvider>
                        <div className="grid grid-cols-3 gap-2">
                          <div className="space-y-1">
                            <div className="flex items-center gap-1">
                              <Label className="text-xs">Quem executa</Label>
                              <Tooltip>
                                <TooltipTrigger asChild><HelpCircle className="w-3 h-3 text-muted-foreground cursor-help" /></TooltipTrigger>
                                <TooltipContent side="right" className="max-w-52"><p>Cargo ou pessoa diretamente responsável por realizar esta atividade no dia a dia.</p></TooltipContent>
                              </Tooltip>
                            </div>
                            <Input placeholder="Ex: Técnico de Segurança" value={respForm.responsavel} onChange={(e) => setRespForm({ ...respForm, responsavel: e.target.value })} />
                          </div>
                          <div className="space-y-1">
                            <div className="flex items-center gap-1">
                              <Label className="text-xs">Áreas envolvidas</Label>
                              <Tooltip>
                                <TooltipTrigger asChild><HelpCircle className="w-3 h-3 text-muted-foreground cursor-help" /></TooltipTrigger>
                                <TooltipContent side="right" className="max-w-52"><p>Setores ou pessoas que participam ou precisam ser consultados para esta atividade.</p></TooltipContent>
                              </Tooltip>
                            </div>
                            <Input placeholder="Ex: RH, SESMT, Gestor" value={respForm.interfaces} onChange={(e) => setRespForm({ ...respForm, interfaces: e.target.value })} />
                          </div>
                          <div className="space-y-1">
                            <div className="flex items-center gap-1">
                              <Label className="text-xs">Risco se falhar</Label>
                              <Tooltip>
                                <TooltipTrigger asChild><HelpCircle className="w-3 h-3 text-muted-foreground cursor-help" /></TooltipTrigger>
                                <TooltipContent side="right" className="max-w-52"><p>O que pode acontecer se esta atividade for executada incorretamente ou não for feita.</p></TooltipContent>
                              </Tooltip>
                            </div>
                            <div className="flex gap-1">
                              <Input placeholder="Ex: Multa, acidente" value={respForm.consequencia} onChange={(e) => setRespForm({ ...respForm, consequencia: e.target.value })} />
                              <Button size="sm" onClick={async () => {
                                await salvarResponsabilidade({ atividade_id: at.id, responsavel_direto: respForm.responsavel, interfaces: respForm.interfaces, consequencia_erro: respForm.consequencia });
                                setRespForm(null);
                              }}>OK</Button>
                            </div>
                          </div>
                        </div>
                      </TooltipProvider>
                    ) : atResp ? (
                      <div className="text-xs bg-muted/50 rounded-lg p-2 grid grid-cols-3 gap-2 cursor-pointer" onClick={() => setRespForm({ atividadeId: at.id, responsavel: atResp.responsavel_direto || "", interfaces: atResp.interfaces || "", consequencia: atResp.consequencia_erro || "" })}>
                        <span><strong>Quem executa:</strong> {atResp.responsavel_direto || "—"}</span>
                        <span><strong>Áreas envolvidas:</strong> {atResp.interfaces || "—"}</span>
                        <span><strong>Risco se falhar:</strong> {atResp.consequencia_erro || "—"}</span>
                      </div>
                    ) : (
                      <Button variant="ghost" size="sm" onClick={() => setRespForm({ atividadeId: at.id, responsavel: funcaoNome || "", interfaces: "", consequencia: "" })}>
                        <Plus className="w-3 h-3 mr-1" /> Definir
                      </Button>
                    )}
                  </div>

                  {/* Conteúdos */}
                  <div className="space-y-2">
                    <div className="flex items-center justify-between">
                      <span className="flex items-center gap-2 text-sm font-medium"><Link2 className="w-4 h-4" /> Conteúdos ({atConteudos.length})</span>
                      <Button variant="ghost" size="sm" onClick={() => setConteudoForm({ atividadeId: at.id, tipo: "link", titulo: "", url: "" })}>
                        <Plus className="w-3 h-3 mr-1" /> Adicionar
                      </Button>
                    </div>
                    {conteudoForm?.atividadeId === at.id && (
                      <div className="flex gap-2">
                        <Select value={conteudoForm.tipo} onValueChange={(v) => setConteudoForm({ ...conteudoForm, tipo: v })}>
                          <SelectTrigger className="w-32"><SelectValue /></SelectTrigger>
                          <SelectContent>
                            {Object.entries(TIPO_CONTEUDO_LABELS).map(([k, v]) => <SelectItem key={k} value={k}>{v}</SelectItem>)}
                          </SelectContent>
                        </Select>
                        <Input placeholder="Título" value={conteudoForm.titulo} onChange={(e) => setConteudoForm({ ...conteudoForm, titulo: e.target.value })} />
                        <Input placeholder="URL" value={conteudoForm.url} onChange={(e) => setConteudoForm({ ...conteudoForm, url: e.target.value })} />
                        <Button size="sm" onClick={async () => {
                          await criarConteudo({ atividade_id: at.id, tipo: conteudoForm.tipo, titulo: conteudoForm.titulo, url: conteudoForm.url });
                          setConteudoForm(null);
                        }} disabled={!conteudoForm.titulo || !conteudoForm.url}>OK</Button>
                        <Button variant="ghost" size="sm" onClick={() => setConteudoForm(null)}>✕</Button>
                      </div>
                    )}
                    {atConteudos.map((c) => (
                      <div key={c.id} className="flex items-center justify-between text-xs bg-muted/30 rounded-lg px-3 py-2">
                        <div className="flex items-center gap-2">
                          <Badge variant="outline" className="text-xs">{TIPO_CONTEUDO_LABELS[c.tipo]}</Badge>
                          <a href={c.url} target="_blank" rel="noopener noreferrer" className="text-primary hover:underline flex items-center gap-1">
                            {c.titulo} <ExternalLink className="w-3 h-3" />
                          </a>
                        </div>
                        <Button variant="ghost" size="icon" className="h-6 w-6" onClick={() => excluirConteudo(c.id)}>
                          <Trash2 className="w-3 h-3 text-destructive" />
                        </Button>
                      </div>
                    ))}
                  </div>

                  {/* Ferramentas */}
                  <div className="space-y-2">
                    <div className="flex items-center justify-between">
                      <span className="flex items-center gap-2 text-sm font-medium"><Wrench className="w-4 h-4" /> Ferramentas ({atFerramentas.length})</span>
                      <Button variant="ghost" size="sm" onClick={() => setFerramentaForm({ atividadeId: at.id, nome: "", tipo: "sistema", url_manual: "" })}>
                        <Plus className="w-3 h-3 mr-1" /> Adicionar
                      </Button>
                    </div>
                    {ferramentaForm?.atividadeId === at.id && (
                      <div className="flex gap-2">
                        <Select value={ferramentaForm.tipo} onValueChange={(v) => setFerramentaForm({ ...ferramentaForm, tipo: v })}>
                          <SelectTrigger className="w-32"><SelectValue /></SelectTrigger>
                          <SelectContent>
                            {Object.entries(TIPO_FERRAMENTA_LABELS).map(([k, v]) => <SelectItem key={k} value={k}>{v}</SelectItem>)}
                          </SelectContent>
                        </Select>
                        <Input placeholder="Nome" value={ferramentaForm.nome} onChange={(e) => setFerramentaForm({ ...ferramentaForm, nome: e.target.value })} />
                        <Input placeholder="URL do manual" value={ferramentaForm.url_manual} onChange={(e) => setFerramentaForm({ ...ferramentaForm, url_manual: e.target.value })} />
                        <Button size="sm" onClick={async () => {
                          await criarFerramenta({ atividade_id: at.id, nome: ferramentaForm.nome, tipo: ferramentaForm.tipo, url_manual: ferramentaForm.url_manual || undefined });
                          setFerramentaForm(null);
                        }} disabled={!ferramentaForm.nome}>OK</Button>
                        <Button variant="ghost" size="sm" onClick={() => setFerramentaForm(null)}>✕</Button>
                      </div>
                    )}
                    {atFerramentas.map((f) => (
                      <div key={f.id} className="flex items-center justify-between text-xs bg-muted/30 rounded-lg px-3 py-2">
                        <div className="flex items-center gap-2">
                          <Badge variant="outline" className="text-xs">{TIPO_FERRAMENTA_LABELS[f.tipo]}</Badge>
                          <span>{f.nome}</span>
                          {f.url_manual && (
                            <a href={f.url_manual} target="_blank" rel="noopener noreferrer" className="text-primary">
                              <ExternalLink className="w-3 h-3" />
                            </a>
                          )}
                        </div>
                        <Button variant="ghost" size="icon" className="h-6 w-6" onClick={() => excluirFerramenta(f.id)}>
                          <Trash2 className="w-3 h-3 text-destructive" />
                        </Button>
                      </div>
                    ))}
                  </div>

                  {/* POP da Atividade */}
                  <PopSection
                    atividade={at}
                    cargoId={cargoId}
                    funcaoNome={funcaoNome}
                    nivel={nivel}
                    ferramentas={atFerramentas.map(f => `${f.nome} (${TIPO_FERRAMENTA_LABELS[f.tipo]})`).join(", ") || undefined}
                    interfaces={atResp?.interfaces || undefined}
                    responsavelDireto={atResp?.responsavel_direto || undefined}
                    consequenciaErro={atResp?.consequencia_erro || undefined}
                    conteudos={atConteudos.map(c => `${c.titulo} (${TIPO_CONTEUDO_LABELS[c.tipo]})`).join(", ") || undefined}
                  />
                </CardContent>
              </CollapsibleContent>
            </Card>
          </Collapsible>
        );
      })}
          </div>
        ));
      })()}

      <GerarPopsEmLoteModal
        open={showLoteModal}
        onClose={() => setShowLoteModal(false)}
        atividadesSemPop={atividades
          .filter(a => !getPopByAtividade(a.id))
          .map(a => {
            const atResp = responsabilidades.find(r => r.atividade_id === a.id);
            const atFerr = ferramentas.filter(f => f.atividade_id === a.id);
            const atCont = conteudos.filter(c => c.atividade_id === a.id);
            return {
              atividade: a,
              responsabilidade: atResp,
              ferramentas: atFerr.map(f => `${f.nome} (${TIPO_FERRAMENTA_LABELS[f.tipo]})`).join(", ") || undefined,
              conteudos: atCont.map(c => `${c.titulo} (${TIPO_CONTEUDO_LABELS[c.tipo]})`).join(", ") || undefined,
            };
          })}
        funcaoNome={funcaoNome}
        nivel={nivel}
        gerarPopIA={gerarPopIA}
        criarPop={criarPop}
      />
    </div>
  );
}
