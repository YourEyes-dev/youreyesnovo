import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { format } from "date-fns";
import { ptBR } from "date-fns/locale";
import { motion } from "framer-motion";
import { 
  User, 
  EyeOff, 
  Clock, 
  MessageSquare, 
  ChevronDown, 
  ChevronUp,
  Send,
  Trash2,
  Paperclip,
  ClipboardList,
  CheckCircle2,
  ExternalLink
} from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Textarea } from "@/components/ui/textarea";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { cn } from "@/lib/utils";
import type { Manifestacao, StatusManifestacao, PrioridadeManifestacao } from "@/types/ouvidoria";
import {
  TIPO_MANIFESTACAO_LABELS,
  TIPO_MANIFESTACAO_ICONS,
  TIPO_MANIFESTACAO_COLORS,
  STATUS_MANIFESTACAO_LABELS,
  STATUS_MANIFESTACAO_COLORS,
  PRIORIDADE_LABELS,
  PRIORIDADE_COLORS,
} from "@/types/ouvidoria";
import { AnexosList } from "./AnexosList";
import { OuvidoriaAcoesModal } from "./OuvidoriaAcoesModal";
import type { AnexoManifestacao } from "@/types/ouvidoria";

interface OuvidoriaCardProps {
  manifestacao: Manifestacao;
  isManager?: boolean;
  onResponder?: (id: string, resposta: string) => Promise<void>;
  onAtualizarStatus?: (id: string, status: StatusManifestacao, prioridade?: PrioridadeManifestacao) => Promise<void>;
  onDeletar?: (id: string) => Promise<void>;
  isLoading?: boolean;
}

export function OuvidoriaCard({
  manifestacao,
  isManager,
  onResponder,
  onAtualizarStatus,
  onDeletar,
  isLoading,
}: OuvidoriaCardProps) {
  const [expanded, setExpanded] = useState(false);
  const [resposta, setResposta] = useState("");
  const [showRespostaForm, setShowRespostaForm] = useState(false);
  const [showAcoesModal, setShowAcoesModal] = useState(false);

  const isValidUuid = /^[0-9a-f]{8}-/.test(manifestacao.id);
  const origemDescSearch = `${TIPO_MANIFESTACAO_LABELS[manifestacao.tipo]}: ${manifestacao.assunto}`;

  const { data: acoesVinculadas = [] } = useQuery({
    queryKey: ["ouvidoria-acoes-vinculadas", manifestacao.id, manifestacao.assunto],
    queryFn: async () => {
      let query = supabase
        .from("plano_acoes")
        .select("id, codigo, titulo, status")
        .eq("origem_modulo", "ouvidoria");

      if (isValidUuid) {
        query = query.or(`origem_id.eq.${manifestacao.id},origem_descricao.eq.${origemDescSearch}`);
      } else {
        query = query.eq("origem_descricao", origemDescSearch);
      }

      const { data, error } = await query;
      if (error) throw error;
      return data || [];
    },
  });

  const handleResponder = async () => {
    if (!resposta.trim() || !onResponder) return;
    await onResponder(manifestacao.id, resposta.trim());
    setResposta("");
    setShowRespostaForm(false);
  };

  const handleStatusChange = async (status: StatusManifestacao) => {
    if (onAtualizarStatus) {
      await onAtualizarStatus(manifestacao.id, status);
    }
  };

  const handlePrioridadeChange = async (prioridade: PrioridadeManifestacao) => {
    if (onAtualizarStatus) {
      await onAtualizarStatus(manifestacao.id, manifestacao.status, prioridade);
    }
  };

  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      layout
    >
      <Card className="overflow-hidden">
        <CardHeader className="pb-3">
          <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-3">
            <div className="space-y-2">
              <div className="flex items-center gap-2 flex-wrap">
                <span className="text-lg">
                  {TIPO_MANIFESTACAO_ICONS[manifestacao.tipo]}
                </span>
                <Badge className={cn("text-xs", TIPO_MANIFESTACAO_COLORS[manifestacao.tipo])}>
                  {TIPO_MANIFESTACAO_LABELS[manifestacao.tipo]}
                </Badge>
                <Badge className={cn("text-xs", STATUS_MANIFESTACAO_COLORS[manifestacao.status])}>
                  {STATUS_MANIFESTACAO_LABELS[manifestacao.status]}
                </Badge>
                {isManager && (
                  <Badge className={cn("text-xs", PRIORIDADE_COLORS[manifestacao.prioridade])}>
                    {PRIORIDADE_LABELS[manifestacao.prioridade]}
                  </Badge>
                )}
                {manifestacao.anexos && manifestacao.anexos.length > 0 && (
                  <Badge variant="outline" className="text-xs">
                    <Paperclip className="w-3 h-3 mr-1" />
                    {manifestacao.anexos.length} anexo(s)
                  </Badge>
                )}
              </div>
              <h3 className="font-semibold text-lg">{manifestacao.assunto}</h3>
            </div>

            <div className="flex items-center gap-2 text-sm text-muted-foreground">
              {manifestacao.anonimo ? (
                <div className="flex items-center gap-1">
                  <EyeOff className="w-4 h-4" />
                  <span>Anônimo</span>
                </div>
              ) : (
                <div className="flex items-center gap-1">
                  <User className="w-4 h-4" />
                  <span>{manifestacao.autor_nome}</span>
                </div>
              )}
              <span>•</span>
              <div className="flex items-center gap-1">
                <Clock className="w-4 h-4" />
                <span>
                  {format(new Date(manifestacao.created_at), "dd/MM/yyyy 'às' HH:mm", { locale: ptBR })}
                </span>
              </div>
              {isManager && (manifestacao as any).departamento_destino && (
                <>
                  <span>•</span>
                  <Badge variant="outline" className="text-xs">
                    📋 {(manifestacao as any).departamento_destino}
                  </Badge>
                </>
              )}
              {isManager && (manifestacao as any).responsavel_nome && (
                <>
                  <span>•</span>
                  <Badge variant="outline" className="text-xs">
                    👤 {(manifestacao as any).responsavel_nome}
                  </Badge>
                </>
              )}
            </div>
          </div>
        </CardHeader>

        <CardContent className="space-y-4">
          {/* Mensagem (com expand/collapse) */}
          <div className="space-y-2">
            <p className={cn(
              "text-muted-foreground whitespace-pre-wrap",
              !expanded && manifestacao.mensagem.length > 200 && "line-clamp-3"
            )}>
              {manifestacao.mensagem}
            </p>
            {manifestacao.mensagem.length > 200 && (
              <Button
                variant="ghost"
                size="sm"
                onClick={() => setExpanded(!expanded)}
                className="text-xs"
              >
                {expanded ? (
                  <>
                    <ChevronUp className="w-3 h-3 mr-1" />
                    Ver menos
                  </>
                ) : (
                  <>
                    <ChevronDown className="w-3 h-3 mr-1" />
                    Ver mais
                  </>
                )}
              </Button>
            )}
          </div>

          {/* Anexos */}
          {manifestacao.anexos && manifestacao.anexos.length > 0 && (
            <AnexosList anexos={manifestacao.anexos} />
          )}

          {/* Ações vinculadas ao Plano de Ação */}
          {acoesVinculadas.length > 0 && (
            <div className="p-3 rounded-lg bg-primary/5 border border-primary/20">
              <div className="flex items-center gap-2 mb-2">
                <CheckCircle2 className="w-4 h-4 text-primary" />
                <span className="font-medium text-sm">
                  {acoesVinculadas.length} ação(ões) no Plano de Ação
                </span>
              </div>
              <div className="flex flex-wrap gap-2">
                {acoesVinculadas.map((acao) => (
                  <Badge key={acao.id} variant="outline" className="text-xs gap-1">
                    <span className="font-mono">{acao.codigo}</span>
                    <span className="text-muted-foreground">—</span>
                    <span className="max-w-[200px] truncate">{acao.titulo}</span>
                  </Badge>
                ))}
              </div>
            </div>
          )}

          {/* Resposta existente */}
          {manifestacao.resposta && (
            <div className="p-4 bg-primary/5 rounded-lg border border-primary/20">
              <div className="flex items-center gap-2 mb-2">
                <MessageSquare className="w-4 h-4 text-primary" />
                <span className="font-medium text-sm">Resposta</span>
                {manifestacao.respondido_por_nome && (
                  <span className="text-xs text-muted-foreground">
                    por {manifestacao.respondido_por_nome} em{" "}
                    {format(new Date(manifestacao.respondido_em!), "dd/MM/yyyy 'às' HH:mm", { locale: ptBR })}
                  </span>
                )}
              </div>
              <p className="text-sm whitespace-pre-wrap">{manifestacao.resposta}</p>
            </div>
          )}

          {/* Ações de gestão: só aparecem para quem pode agir (a tela decide pelo perfil) */}
          {isManager && (onResponder || onAtualizarStatus || onDeletar) && (
            <div className="flex flex-col sm:flex-row gap-3 pt-3 border-t">
              <div className="flex gap-2 flex-1">
                <Select value={manifestacao.status} onValueChange={handleStatusChange} disabled={!onAtualizarStatus}>
                  <SelectTrigger className="w-[140px]">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="pendente">Pendente</SelectItem>
                    <SelectItem value="em_analise">Em Análise</SelectItem>
                    <SelectItem value="respondido">Respondido</SelectItem>
                    <SelectItem value="arquivado">Arquivado</SelectItem>
                  </SelectContent>
                </Select>

                <Select value={manifestacao.prioridade} onValueChange={handlePrioridadeChange} disabled={!onAtualizarStatus}>
                  <SelectTrigger className="w-[120px]">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="baixa">Baixa</SelectItem>
                    <SelectItem value="normal">Normal</SelectItem>
                    <SelectItem value="alta">Alta</SelectItem>
                    <SelectItem value="urgente">Urgente</SelectItem>
                  </SelectContent>
                </Select>
              </div>

              <div className="flex gap-2">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => setShowAcoesModal(true)}
                >
                  <ClipboardList className="w-4 h-4 mr-1" />
                  Criar Ações
                </Button>

                {!manifestacao.resposta && onResponder && (
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => setShowRespostaForm(!showRespostaForm)}
                  >
                    <MessageSquare className="w-4 h-4 mr-1" />
                    Responder
                  </Button>
                )}

                {onDeletar && (
                  <AlertDialog>
                    <AlertDialogTrigger asChild>
                      <Button variant="outline" size="sm" className="text-destructive">
                        <Trash2 className="w-4 h-4" />
                      </Button>
                    </AlertDialogTrigger>
                    <AlertDialogContent>
                      <AlertDialogHeader>
                        <AlertDialogTitle>Confirmar exclusão</AlertDialogTitle>
                        <AlertDialogDescription>
                          Tem certeza que deseja excluir esta manifestação? Esta ação não pode ser desfeita.
                        </AlertDialogDescription>
                      </AlertDialogHeader>
                      <AlertDialogFooter>
                        <AlertDialogCancel>Cancelar</AlertDialogCancel>
                        <AlertDialogAction
                          onClick={() => onDeletar(manifestacao.id)}
                          className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
                        >
                          Excluir
                        </AlertDialogAction>
                      </AlertDialogFooter>
                    </AlertDialogContent>
                  </AlertDialog>
                )}
              </div>
            </div>
          )}

          {/* Formulário de Resposta */}
          {showRespostaForm && isManager && (
            <motion.div
              initial={{ opacity: 0, height: 0 }}
              animate={{ opacity: 1, height: "auto" }}
              exit={{ opacity: 0, height: 0 }}
              className="space-y-3 pt-3 border-t"
            >
              <Textarea
                placeholder="Digite sua resposta..."
                value={resposta}
                onChange={(e) => setResposta(e.target.value)}
                rows={4}
              />
              <div className="flex gap-2 justify-end">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => {
                    setShowRespostaForm(false);
                    setResposta("");
                  }}
                >
                  Cancelar
                </Button>
                <Button
                  size="sm"
                  onClick={handleResponder}
                  disabled={!resposta.trim() || isLoading}
                >
                  <Send className="w-4 h-4 mr-1" />
                  Enviar Resposta
                </Button>
              </div>
            </motion.div>
          )}
        </CardContent>
      </Card>

      {/* Modal de Ações */}
      {isManager && (
        <OuvidoriaAcoesModal
          manifestacao={manifestacao}
          open={showAcoesModal}
          onOpenChange={setShowAcoesModal}
        />
      )}
    </motion.div>
  );
}
