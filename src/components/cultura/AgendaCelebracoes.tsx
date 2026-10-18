import { useState } from "react";
import { format, parseISO, startOfMonth, endOfMonth, addMonths, startOfYear, endOfYear, isWithinInterval } from "date-fns";
import { ptBR } from "date-fns/locale";
import { CalendarHeart, Plus, Trash2, Filter } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { useColaboradores } from "@/hooks/useColaboradores";
import type { CulturaAcao } from "@/types/cultura";
import { TIPO_ACAO_LABELS, STATUS_ACAO_LABELS, STATUS_ACAO_COLORS } from "@/types/cultura";

interface Props {
  acoes: CulturaAcao[];
  isLoading: boolean;
  onCreateAcao: (data: Partial<CulturaAcao>) => Promise<void>;
  onUpdateStatus: (id: string, status: string) => Promise<void>;
  onDelete: (id: string) => Promise<void>;
}

export const AgendaCelebracoes = ({ acoes, isLoading, onCreateAcao, onUpdateStatus, onDelete }: Props) => {
  const { colaboradores } = useColaboradores();
  const [showForm, setShowForm] = useState(false);
  const [filtroTipo, setFiltroTipo] = useState("todos");
  const [filtroStatus, setFiltroStatus] = useState("todos");
  const [filtroColaborador, setFiltroColaborador] = useState("");
  const [filtroPeriodo, setFiltroPeriodo] = useState("todos");

  const [form, setForm] = useState({
    tipo: "aniversario",
    titulo: "",
    descricao: "",
    colaborador_nome: "",
    data_referencia: "",
    data_execucao: "",
    responsavel_nome: "",
  });

  const filtered = acoes.filter(a => {
    if (filtroTipo !== "todos" && a.tipo !== filtroTipo) return false;
    if (filtroStatus !== "todos" && a.status !== filtroStatus) return false;
    if (filtroColaborador && a.colaborador_nome && !a.colaborador_nome.toLowerCase().includes(filtroColaborador.toLowerCase())) return false;
    if (filtroPeriodo !== "todos") {
      const dataRef = parseISO(a.data_referencia);
      const hoje = new Date();
      if (filtroPeriodo === "mes") {
        if (!isWithinInterval(dataRef, { start: startOfMonth(hoje), end: endOfMonth(hoje) })) return false;
      } else if (filtroPeriodo === "trimestre") {
        if (!isWithinInterval(dataRef, { start: startOfMonth(hoje), end: endOfMonth(addMonths(hoje, 2)) })) return false;
      } else if (filtroPeriodo === "ano") {
        if (!isWithinInterval(dataRef, { start: startOfYear(hoje), end: endOfYear(hoje) })) return false;
      }
    }
    return true;
  });

  const handleSubmit = async () => {
    if (!form.titulo || !form.data_referencia) return;
    await onCreateAcao({
      tipo: form.tipo,
      titulo: form.titulo,
      descricao: form.descricao || null,
      colaborador_nome: form.colaborador_nome || null,
      data_referencia: form.data_referencia,
      data_execucao: form.data_execucao || null,
      responsavel_nome: form.responsavel_nome || null,
    });
    setShowForm(false);
    setForm({ tipo: "aniversario", titulo: "", descricao: "", colaborador_nome: "", data_referencia: "", data_execucao: "", responsavel_nome: "" });
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between flex-wrap gap-2">
        <div className="flex items-center gap-2 flex-wrap w-full sm:w-auto">
          <Filter className="w-4 h-4 text-muted-foreground" />
          <Select value={filtroTipo} onValueChange={setFiltroTipo}>
            <SelectTrigger className="w-full sm:w-[160px] h-8 text-xs"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="todos">Todos os tipos</SelectItem>
              {Object.entries(TIPO_ACAO_LABELS).map(([k, v]) => (
                <SelectItem key={k} value={k}>{v}</SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Select value={filtroStatus} onValueChange={setFiltroStatus}>
            <SelectTrigger className="w-full sm:w-[150px] h-8 text-xs"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="todos">Todos os status</SelectItem>
              {Object.entries(STATUS_ACAO_LABELS).map(([k, v]) => (
                <SelectItem key={k} value={k}>{v}</SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Select value={filtroPeriodo} onValueChange={setFiltroPeriodo}>
            <SelectTrigger className="w-full sm:w-[130px] h-8 text-xs"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="todos">Todo período</SelectItem>
              <SelectItem value="mes">Este mês</SelectItem>
              <SelectItem value="trimestre">Trimestre</SelectItem>
              <SelectItem value="ano">Este ano</SelectItem>
            </SelectContent>
          </Select>
          <Input
            placeholder="Buscar colaborador..."
            value={filtroColaborador}
            onChange={e => setFiltroColaborador(e.target.value)}
            className="w-full sm:w-[180px] h-8 text-xs"
          />
        </div>
        <Button size="sm" onClick={() => setShowForm(true)} className="gap-1">
          <Plus className="w-4 h-4" /> Nova Ação
        </Button>
      </div>

      {isLoading ? (
        <p className="text-sm text-muted-foreground text-center py-10">Carregando...</p>
      ) : filtered.length === 0 ? (
        <Card className="p-10 text-center">
          <CalendarHeart className="w-10 h-10 mx-auto text-muted-foreground/40 mb-2" />
          <p className="text-sm text-muted-foreground">Nenhuma ação cultural encontrada</p>
          <p className="text-xs text-muted-foreground mt-1">Crie ações para celebrar datas e pessoas</p>
        </Card>
      ) : (
        <div className="grid gap-3">
          {filtered.map((acao) => (
            <Card key={acao.id} className="p-4">
              <div className="flex items-start justify-between gap-3">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <h4 className="font-medium text-sm truncate">{acao.titulo}</h4>
                    <Badge variant="outline" className="text-[10px] shrink-0">
                      {TIPO_ACAO_LABELS[acao.tipo] || acao.tipo}
                    </Badge>
                    <Badge className={`text-[10px] shrink-0 ${STATUS_ACAO_COLORS[acao.status]}`}>
                      {STATUS_ACAO_LABELS[acao.status]}
                    </Badge>
                  </div>
                  {acao.colaborador_nome && (
                    <p className="text-xs text-muted-foreground">Colaborador: {acao.colaborador_nome}</p>
                  )}
                  <p className="text-xs text-muted-foreground">
                    Data: {format(parseISO(acao.data_referencia), "dd/MM/yyyy")}
                    {acao.data_execucao && ` · Execução: ${format(parseISO(acao.data_execucao), "dd/MM/yyyy")}`}
                  </p>
                  {acao.responsavel_nome && (
                    <p className="text-xs text-muted-foreground">Responsável: {acao.responsavel_nome}</p>
                  )}
                  {acao.descricao && <p className="text-xs text-muted-foreground mt-1">{acao.descricao}</p>}
                </div>
                <div className="flex items-center gap-1 shrink-0">
                  {acao.status === "pendente" && (
                    <Button size="sm" variant="outline" className="text-xs h-7" onClick={() => onUpdateStatus(acao.id, "concluida")}>
                      Concluir
                    </Button>
                  )}
                  <Button size="icon" variant="ghost" className="h-7 w-7 text-destructive" onClick={() => onDelete(acao.id)}>
                    <Trash2 className="w-3.5 h-3.5" />
                  </Button>
                </div>
              </div>
            </Card>
          ))}
        </div>
      )}

      <Dialog open={showForm} onOpenChange={setShowForm}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Nova Ação Cultural</DialogTitle>
            <DialogDescription>Planeje uma celebração ou ação cultural</DialogDescription>
          </DialogHeader>
          <div className="space-y-3">
            <div>
              <Label>Tipo</Label>
              <Select value={form.tipo} onValueChange={v => setForm(f => ({ ...f, tipo: v }))}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {Object.entries(TIPO_ACAO_LABELS).map(([k, v]) => (
                    <SelectItem key={k} value={k}>{v}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label>Título *</Label>
              <Input value={form.titulo} onChange={e => setForm(f => ({ ...f, titulo: e.target.value }))} />
            </div>
            <div>
              <Label>Colaborador</Label>
              <Select
                value={form.colaborador_nome}
                onValueChange={v => setForm(f => ({ ...f, colaborador_nome: v === "_none" ? "" : v }))}
              >
                <SelectTrigger><SelectValue placeholder="Selecione um colaborador (opcional)" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="_none">Nenhum (geral)</SelectItem>
                  {colaboradores.map(c => (
                    <SelectItem key={c.id} value={c.nome_completo}>
                      {c.nome_completo}{c.cargo ? ` · ${c.cargo}` : ""}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <Label>Data de Referência *</Label>
                <Input type="date" value={form.data_referencia} onChange={e => setForm(f => ({ ...f, data_referencia: e.target.value }))} />
              </div>
              <div>
                <Label>Data de Execução</Label>
                <Input type="date" value={form.data_execucao} onChange={e => setForm(f => ({ ...f, data_execucao: e.target.value }))} />
              </div>
            </div>
            <div>
              <Label>Responsável</Label>
              <Input value={form.responsavel_nome} onChange={e => setForm(f => ({ ...f, responsavel_nome: e.target.value }))} />
            </div>
            <div>
              <Label>Descrição</Label>
              <Textarea value={form.descricao} onChange={e => setForm(f => ({ ...f, descricao: e.target.value }))} rows={2} />
            </div>
            <Button onClick={handleSubmit} className="w-full">Criar Ação</Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
};
