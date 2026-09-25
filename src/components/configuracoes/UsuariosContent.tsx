import { useState, useMemo } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import {
  Users, Plus, Search, User, Building2, Link2,
  Clock, Sparkles, AlertTriangle, RefreshCw,
} from "lucide-react";
import { useUsuarios, TIPO_USUARIO_LABELS, STATUS_LABELS, calcularQualidade } from "@/hooks/useUsuarios";
import { UsuarioStatusBadge } from "@/components/usuarios/UsuarioStatusBadge";
import { QualidadeScoreIndicator } from "@/components/usuarios/QualidadeScoreIndicator";
import { NovoUsuarioDialog } from "@/components/usuarios/NovoUsuarioDialog";
import { UsuarioDetalheDialog } from "@/components/usuarios/UsuarioDetalheDialog";
import { format } from "date-fns";
import { ptBR } from "date-fns/locale";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "@/hooks/useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";

const STATUS_OPTIONS = [
  { value: "todos", label: "Todos os status" },
  ...Object.entries(STATUS_LABELS).map(([k, v]) => ({ value: k, label: v })),
];

const TIPO_OPTIONS = [
  { value: "todos", label: "Todos os tipos de usuário" },
  ...Object.entries(TIPO_USUARIO_LABELS).map(([k, v]) => ({ value: k, label: v })),
];


export default function UsuariosContent() {
  const { tenantId } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  const { usuarios, isLoading } = useUsuarios();
  const [search, setSearch] = useState("");
  const [filterStatus, setFilterStatus] = useState("todos");
  const [filterTipo, setFilterTipo] = useState("todos");
  const [filterEmpresa, setFilterEmpresa] = useState(empresaAtivaId || "todos");
  const [showNovo, setShowNovo] = useState(false);
  const [selecionadoId, setSelecionadoId] = useState<string | null>(null);
  const selecionado = selecionadoId ? usuarios.find(u => u.id === selecionadoId) || null : null;

  const { data: empresas = [] } = useQuery({
    queryKey: ["empresas-lista", tenantId],
    queryFn: async () => {
      if (!tenantId) return [];
      const { data } = await fromTable("empresa_cadastro")
        .select("id, razao_social, nome_fantasia")
        .eq("tenant_id", tenantId)
        .order("razao_social");
      return data || [];
    },
    enabled: !!tenantId,
  });

  // Buscar vínculos de perfil de acesso para todos os usuários
  const { data: perfilVinculos = [] } = useQuery({
    queryKey: ["usuarios-perfil-vinculos-lista", tenantId],
    queryFn: async () => {
      if (!tenantId) return [];
      const { data } = await fromTable("usuario_perfil_vinculos")
        .select("usuario_id, perfil:perfil_id(id,nome,cor)")
        .eq("tenant_id", tenantId)
        .eq("ativo", true);
      return data || [];
    },
    enabled: !!tenantId,
  });

  const perfilPorUsuario = useMemo(() => {
    const map = new Map<string, { nome: string; cor: string }>();
    for (const v of perfilVinculos) {
      if (v.perfil) map.set(v.usuario_id, { nome: v.perfil.nome, cor: v.perfil.cor });
    }
    return map;
  }, [perfilVinculos]);

  const filtered = useMemo(() => {
    return usuarios.filter(u => {
      const q = search.toLowerCase();
      const matchQ = !q ||
        u.nome_completo.toLowerCase().includes(q) ||
        u.email_principal.toLowerCase().includes(q) ||
        (u.cpf || "").includes(q) ||
        (u.telefone_principal || "").includes(q);
      const matchStatus = filterStatus === "todos" || u.status === filterStatus;
      const matchTipo = filterTipo === "todos" || u.tipo_usuario === filterTipo;
      // Administradores e papéis de acesso global aparecem em qualquer empresa filtrada.
      // 'proprietario'/'owner' (dono da conta) têm acesso amplo ao tenant e não são
      // vinculados a uma empresa específica — sem eles nesta lista, o dono some da
      // tela sempre que há uma empresa selecionada no filtro (o padrão).
      const tiposGlobais = ["proprietario", "owner", "administrador", "rh_dp", "corporativo_multiempresa", "suporte_autorizado", "auditor"];
      const isGlobal = tiposGlobais.includes(u.tipo_usuario);
      const matchEmpresa = filterEmpresa === "todos" || isGlobal ||
        ((u as any).vinculos || []).some((v: any) => v.empresa_id === filterEmpresa && v.status === "ativo");
      return matchQ && matchStatus && matchTipo && matchEmpresa;
    });
  }, [usuarios, search, filterStatus, filterTipo, filterEmpresa]);

  const ativos = usuarios.filter(u => u.status === "ativo").length;
  const convites = usuarios.filter(u => ["convite_enviado", "aguardando_ativacao", "pendente_convite"].includes(u.status)).length;
  const duplicidades = usuarios.filter(u => u.alerta_duplicidade).length;
  const multiempresa = usuarios.filter(u => ((u as any).vinculos || []).filter((v: any) => v.status === "ativo").length > 1).length;

  const hasFilters = search || filterStatus !== "todos" || filterTipo !== "todos" || filterEmpresa !== "todos";

  function fmt(d?: string) {
    if (!d) return null;
    try { return format(new Date(d), "dd/MM/yy", { locale: ptBR }); }
    catch { return null; }
  }

  function getEmpresaPrincipal(u: any) {
    const vinculos: any[] = u.vinculos || [];
    const ativo = vinculos.find(v => v.status === "ativo");
    if (!ativo) return null;
    return ativo.empresa?.nome_fantasia || ativo.empresa?.razao_social || null;
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-semibold flex items-center gap-2 text-foreground">
            <Users className="w-5 h-5 text-primary" />
            Usuários do Sistema
          </h2>
          <p className="text-sm text-muted-foreground mt-0.5">
            Identidades digitais, vínculos e ciclo de vida no YourEyes
          </p>
        </div>
        <Button onClick={() => setShowNovo(true)}>
          <Plus className="w-4 h-4 mr-2" /> Novo Usuário
        </Button>
      </div>

      {/* Métricas */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        {[
          { label: "Ativos", value: ativos, icon: User, color: "text-success" },
          { label: "Com convite", value: convites, icon: Clock, color: "text-blue-600" },
          { label: "Multiempresa", value: multiempresa, icon: Building2, color: "text-purple-600" },
          { label: "Alertas IA", value: duplicidades, icon: AlertTriangle, color: "text-amber-600" },
        ].map(({ label, value, icon: Icon, color }) => (
          <Card key={label}>
            <CardContent className="p-4 flex items-center gap-3">
              <div className="p-2 rounded-lg bg-muted/50">
                <Icon className={`w-5 h-5 ${color}`} />
              </div>
              <div>
                <p className="text-2xl font-bold text-foreground">{value}</p>
                <p className="text-xs text-muted-foreground">{label}</p>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Filtros */}
      <div className="flex flex-wrap gap-3">
        <div className="relative flex-1 min-w-[220px]">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
          <Input
            className="pl-9"
            placeholder="Buscar por nome, e-mail, CPF, telefone…"
            value={search}
            onChange={e => setSearch(e.target.value)}
          />
        </div>
        <Select value={filterEmpresa} onValueChange={setFilterEmpresa}>
          <SelectTrigger className="w-52"><SelectValue /></SelectTrigger>
          <SelectContent>
            
            {empresas.map((e: any) => (
              <SelectItem key={e.id} value={e.id}>{e.nome_fantasia || e.razao_social}</SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Select value={filterStatus} onValueChange={setFilterStatus}>
          <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
          <SelectContent>
            {STATUS_OPTIONS.map(o => <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>)}
          </SelectContent>
        </Select>
        <Select value={filterTipo} onValueChange={setFilterTipo}>
          <SelectTrigger className="w-52"><SelectValue /></SelectTrigger>
          <SelectContent>
            {TIPO_OPTIONS.map(o => <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>)}
          </SelectContent>
        </Select>
        {hasFilters && (
          <Button variant="ghost" size="sm" onClick={() => {
            setSearch(""); setFilterStatus("todos"); setFilterTipo("todos"); setFilterEmpresa("todos");
          }}>
            <RefreshCw className="w-3.5 h-3.5 mr-1" /> Limpar
          </Button>
        )}
      </div>

      {/* Lista */}
      {isLoading ? (
        <div className="flex items-center justify-center py-20 text-muted-foreground">
          <RefreshCw className="w-5 h-5 mr-2 animate-spin" /> Carregando usuários…
        </div>
      ) : filtered.length === 0 ? (
        <div className="text-center py-20 text-muted-foreground">
          <Users className="w-12 h-12 mx-auto mb-3 opacity-30" />
          <p className="font-medium">{hasFilters ? "Nenhum usuário encontrado" : "Nenhum usuário cadastrado"}</p>
          {!hasFilters && (
            <Button className="mt-4" onClick={() => setShowNovo(true)}>
              <Plus className="w-4 h-4 mr-2" /> Cadastrar primeiro usuário
            </Button>
          )}
        </div>
      ) : (
        <div className="space-y-2">
          <div className="hidden md:grid grid-cols-[2fr_1.5fr_1fr_1fr_1fr_80px] gap-4 px-4 py-2 text-xs font-medium text-muted-foreground uppercase tracking-wide">
            <span>Usuário</span>
            <span>Empresa / E-mail</span>
            <span>Perfil de Acesso</span>
            <span>Vínculos</span>
            <span>Cadastro Completo</span>
            <span>Status</span>
          </div>
          {filtered.map(u => {
            const vinculos: any[] = (u as any).vinculos || [];
            const ativosV = vinculos.filter(v => v.status === "ativo");
            const { score, pct } = calcularQualidade(u, vinculos);
            const empresaPrincipal = getEmpresaPrincipal(u);
            return (
              <Card
                key={u.id}
                className="hover:border-primary/40 cursor-pointer transition-all"
                onClick={() => setSelecionadoId(u.id)}
              >
                <CardContent className="p-4">
                  <div className="md:hidden space-y-2">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <div className="w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center">
                          <User className="w-4 h-4 text-primary" />
                        </div>
                        <div>
                          <p className="font-medium text-sm">{u.nome_completo}</p>
                          <p className="text-xs text-muted-foreground">{u.email_principal}</p>
                        </div>
                      </div>
                      <UsuarioStatusBadge status={u.status} />
                    </div>
                    <div className="flex items-center gap-2 flex-wrap">
                      {(() => {
                        const perfil = perfilPorUsuario.get(u.id);
                        return perfil ? (
                          <Badge variant="outline" className="text-xs" style={{ borderColor: perfil.cor, color: perfil.cor }}>
                            <span className="w-2 h-2 rounded-full mr-1.5 shrink-0" style={{ backgroundColor: perfil.cor }} />
                            {perfil.nome}
                          </Badge>
                        ) : (
                          <Badge variant="secondary" className="text-xs text-muted-foreground">Sem perfil</Badge>
                        );
                      })()}
                      {empresaPrincipal && (
                        <span className="text-xs text-muted-foreground">
                          <Building2 className="w-3 h-3 inline mr-0.5" />{empresaPrincipal}
                        </span>
                      )}
                    </div>
                    <QualidadeScoreIndicator score={score} pct={pct} />
                  </div>
                  <div className="hidden md:grid grid-cols-[2fr_1.5fr_1fr_1fr_1fr_80px] gap-4 items-center">
                    <div className="flex items-center gap-3 min-w-0">
                      <div className="w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center shrink-0">
                        {u.foto_url
                          ? <img src={u.foto_url} className="w-8 h-8 rounded-full object-cover" alt="" />
                          : <User className="w-4 h-4 text-primary" />
                        }
                      </div>
                      <div className="min-w-0">
                        <div className="flex items-center gap-1.5">
                          <p className="font-medium text-sm truncate">{u.nome_completo}</p>
                          {u.alerta_duplicidade && <AlertTriangle className="w-3.5 h-3.5 text-amber-500 shrink-0" />}
                        </div>
                        <p className="text-xs text-muted-foreground">
                          {u.cpf || (u.ultimo_acesso_em ? `Acesso: ${fmt(u.ultimo_acesso_em)}` : "Nunca acessou")}
                        </p>
                      </div>
                    </div>
                    <div className="min-w-0">
                      {empresaPrincipal ? (
                        <>
                          <p className="text-sm font-medium truncate flex items-center gap-1">
                            <Building2 className="w-3 h-3 text-muted-foreground shrink-0" />{empresaPrincipal}
                          </p>
                          <p className="text-xs text-muted-foreground truncate">{u.email_principal}</p>
                        </>
                      ) : (
                        <p className="text-sm text-muted-foreground truncate">{u.email_principal}</p>
                      )}
                    </div>
                    {(() => {
                      const perfil = perfilPorUsuario.get(u.id);
                      // Perfil de acesso (permissão) e tipo de usuário (natureza)
                      // são coisas distintas. Quando não há perfil atribuído,
                      // dizer "Sem perfil" é mais honesto que "—", que parecia
                      // falha de gravação.
                      return perfil ? (
                        <Badge variant="outline" className="text-xs truncate" style={{ borderColor: perfil.cor, color: perfil.cor }}>
                          <span className="w-2 h-2 rounded-full mr-1.5 shrink-0" style={{ backgroundColor: perfil.cor }} />
                          {perfil.nome}
                        </Badge>
                      ) : (
                        <Badge variant="secondary" className="text-xs text-muted-foreground truncate">
                          Sem perfil
                        </Badge>
                      );
                    })()}
                    <div className="flex items-center gap-1 text-sm">
                      <Link2 className="w-3.5 h-3.5 text-muted-foreground" />
                      <span>{ativosV.length}</span>
                      {ativosV.length > 1 && <Sparkles className="w-3 h-3 text-purple-500" />}
                    </div>
                    <QualidadeScoreIndicator score={score} pct={pct} />
                    <UsuarioStatusBadge status={u.status} />
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}

      {!isLoading && filtered.length > 0 && (
        <p className="text-xs text-muted-foreground text-center">
          {filtered.length} de {usuarios.length} usuário(s)
        </p>
      )}

      <NovoUsuarioDialog open={showNovo} onOpenChange={setShowNovo} />
      {selecionado && (
        <UsuarioDetalheDialog
          usuario={selecionado}
          open={!!selecionado}
          onOpenChange={v => { if (!v) setSelecionadoId(null); }}
        />
      )}
    </div>
  );
}
