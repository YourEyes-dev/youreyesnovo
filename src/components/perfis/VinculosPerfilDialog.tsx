import { useState } from "react";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import type { PerfilAcesso, UsuarioPerfilVinculo } from "@/hooks/usePerfisAcesso";
import { UserPlus, X, CalendarDays } from "lucide-react";
import { format } from "date-fns";
import { ptBR } from "date-fns/locale";

interface VinculosPerfilDialogProps {
  open: boolean;
  onClose: () => void;
  perfil: PerfilAcesso;
  vinculos: UsuarioPerfilVinculo[];
  usuarios: { id: string; nome_completo: string; email_principal: string }[];
  onVincular: (payload: {
    usuario_id: string;
    perfil_id: string;
    expira_em?: string;
    is_perfil_principal?: boolean;
    observacao?: string;
  }) => void;
  onDesvincular: (vinculoId: string) => void;
}

export function VinculosPerfilDialog({
  open, onClose, perfil, vinculos, usuarios, onVincular, onDesvincular,
}: VinculosPerfilDialogProps) {
  const [usuarioSelecionado, setUsuarioSelecionado] = useState("");
  const [expiracao, setExpiracao] = useState("");
  const [isPrincipal, setIsPrincipal] = useState(true);
  const [observacao, setObservacao] = useState("");

  const vinculosDoPerfil = vinculos.filter((v) => v.perfil_id === perfil.id);
  const idsVinculados = new Set(vinculosDoPerfil.map((v) => v.usuario_id));
  const usuariosDisponiveis = usuarios.filter((u) => !idsVinculados.has(u.id));

  const handleVincular = () => {
    if (!usuarioSelecionado) return;
    onVincular({
      usuario_id: usuarioSelecionado,
      perfil_id: perfil.id,
      expira_em: expiracao || undefined,
      is_perfil_principal: isPrincipal,
      observacao: observacao || undefined,
    });
    setUsuarioSelecionado("");
    setExpiracao("");
    setObservacao("");
    setIsPrincipal(true);
  };

  return (
    <Dialog open={open} onOpenChange={onClose}>
      <DialogContent className="max-w-lg max-h-[85vh] flex flex-col overflow-hidden">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <div
              className="w-6 h-6 rounded flex items-center justify-center text-xs font-bold text-white"
              style={{ backgroundColor: perfil.cor || "#6366f1" }}
            >
              {perfil.nome.charAt(0)}
            </div>
            Usuários — {perfil.nome}
          </DialogTitle>
        </DialogHeader>

        <div className="flex-1 overflow-y-auto space-y-4">
          {/* Formulário de vínculo */}
          <div className="space-y-3 rounded-lg border border-border p-3 bg-muted/20">
            <p className="text-[12px] font-semibold text-muted-foreground uppercase tracking-wide">Adicionar usuário</p>
            <Select value={usuarioSelecionado} onValueChange={setUsuarioSelecionado}>
              <SelectTrigger className="text-[13px]">
                <SelectValue placeholder="Selecionar usuário..." />
              </SelectTrigger>
              <SelectContent>
                {usuariosDisponiveis.length === 0 ? (
                  <p className="text-[12px] text-muted-foreground px-3 py-2">Todos os usuários já possuem este perfil</p>
                ) : usuariosDisponiveis.map((u) => (
                  <SelectItem key={u.id} value={u.id}>
                    <span className="text-[13px]">{u.nome_completo}</span>
                    <span className="text-[11px] text-muted-foreground ml-1">({u.email_principal})</span>
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>

            <div className="grid grid-cols-2 gap-2">
              <div className="space-y-1">
                <Label className="text-[11px]">Expiração (opcional)</Label>
                <Input
                  type="date"
                  value={expiracao}
                  onChange={(e) => setExpiracao(e.target.value)}
                  className="text-[12px] h-8"
                />
              </div>
              <div className="flex items-end gap-2 pb-0.5">
                <div className="flex items-center gap-2">
                  <Switch checked={isPrincipal} onCheckedChange={setIsPrincipal} id="principal-switch" />
                  <Label htmlFor="principal-switch" className="text-[12px] cursor-pointer">Perfil principal</Label>
                </div>
              </div>
            </div>

            <Input
              placeholder="Observação (opcional)"
              value={observacao}
              onChange={(e) => setObservacao(e.target.value)}
              className="text-[12px] h-8"
            />

            <Button size="sm" onClick={handleVincular} disabled={!usuarioSelecionado} className="w-full">
              <UserPlus className="w-4 h-4 mr-1.5" /> Vincular ao perfil
            </Button>
          </div>

          {/* Lista de usuários vinculados */}
          <div className="space-y-1.5">
            <p className="text-[12px] font-semibold text-muted-foreground uppercase tracking-wide">
              Usuários vinculados ({idsVinculados.size})
            </p>
            {vinculosDoPerfil.length === 0 ? (
              <p className="text-[12px] text-muted-foreground text-center py-6">
                Nenhum usuário vinculado a este perfil
              </p>
            ) : vinculosDoPerfil.map((v) => {
              const nome = (v.usuario as any)?.nome_completo || "Usuário";
              const email = (v.usuario as any)?.email_principal || "";
              const expirado = v.expira_em && new Date(v.expira_em) < new Date();
              return (
                <div key={v.id} className="flex items-center gap-3 p-2 rounded-lg border border-border/50 bg-muted/10">
                  <Avatar className="w-8 h-8 shrink-0">
                    <AvatarFallback className="text-[11px] font-medium">
                      {nome.charAt(0).toUpperCase()}
                    </AvatarFallback>
                  </Avatar>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-1.5">
                      <p className="text-[13px] font-medium truncate">{nome}</p>
                      {v.is_perfil_principal && (
                        <Badge variant="secondary" className="text-[9px] h-3.5 px-1">Principal</Badge>
                      )}
                    </div>
                    <div className="flex items-center gap-2">
                      <p className="text-[11px] text-muted-foreground truncate">{email}</p>
                      {v.expira_em && (
                        <span className={`text-[10px] flex items-center gap-0.5 ${expirado ? "text-red-500" : "text-muted-foreground"}`}>
                          <CalendarDays className="w-2.5 h-2.5" />
                          {format(new Date(v.expira_em), "dd/MM/yy", { locale: ptBR })}
                        </span>
                      )}
                    </div>
                  </div>
                  <Badge variant="outline" className="text-[10px] text-emerald-600 border-emerald-200 shrink-0">Ativo</Badge>
                  <Button
                    variant="ghost"
                    size="icon"
                    className="h-6 w-6 text-muted-foreground hover:text-destructive shrink-0"
                    onClick={() => onDesvincular(v.id)}
                  >
                    <X className="w-3.5 h-3.5" />
                  </Button>
                </div>
              );
            })}
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
