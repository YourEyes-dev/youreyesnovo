import { useState, useMemo } from "react";
import { motion } from "framer-motion";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Skeleton } from "@/components/ui/skeleton";
import { ShieldCheck, Plus, Search, LayoutGrid, RefreshCw, History } from "lucide-react";
import { usePerfisAcesso, type PerfilAcesso, type PerfilPermissao } from "@/hooks/usePerfisAcesso";
import { PerfilCard } from "@/components/perfis/PerfilCard";
import { TemplateCard } from "@/components/perfis/TemplateCard";
import { PerfilFormDialog } from "@/components/perfis/PerfilFormDialog";
import { VinculosPerfilDialog } from "@/components/perfis/VinculosPerfilDialog";
import { SimularAcessoDialog } from "@/components/perfis/SimularAcessoDialog";
import { AuditLogPerfil } from "@/components/perfis/AuditLogPerfil";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "@/hooks/useAuth";

export default function PerfisContent() {
  const {
    templates, loadingTemplates,
    perfis, loadingPerfis,
    vinculos, loadingVinculos,
    auditLogs, loadingAuditLogs,
    createPerfil, updatePerfil, togglePerfilStatus,
    clonarTemplate, vincularPerfil, desvincularPerfil,
  } = usePerfisAcesso();

  const { tenantId } = useAuth();
  const [search, setSearch] = useState("");
  const [activeTab, setActiveTab] = useState("perfis");
  const [perfilFormOpen, setPerfilFormOpen] = useState(false);
  const [perfilEditando, setPerfilEditando] = useState<PerfilAcesso | undefined>();
  const [perfilVinculos, setPerfilVinculos] = useState<PerfilAcesso | undefined>();
  const [perfilSimulacao, setPerfilSimulacao] = useState<PerfilAcesso | undefined>();
  const [submitting, setSubmitting] = useState(false);

  const { data: usuarios = [] } = useQuery({
    queryKey: ["usuarios_base_lista", tenantId],
    queryFn: async () => {
      if (!tenantId) return [];
      const { data } = await fromTable("usuarios_base")
        .select("id, nome_completo, email_principal")
        .eq("tenant_id", tenantId)
        .order("nome_completo");
      return data || [];
    },
    enabled: !!tenantId,
  });

  // Contagem de usuários por perfil calculada AO VIVO a partir dos vínculos
  // ativos (fonte da verdade), por usuário distinto. Substitui o campo
  // armazenado perfis_acesso.total_usuarios, que derivava do real por causa de
  // gatilho duplicado + incremental no banco.
  const usuariosPorPerfil = useMemo(() => {
    const map = new Map<string, Set<string>>();
    for (const v of vinculos) {
      if (v.ativo === false) continue;
      if (!map.has(v.perfil_id)) map.set(v.perfil_id, new Set());
      map.get(v.perfil_id)!.add(v.usuario_id);
    }
    return map;
  }, [vinculos]);

  const perfisFiltered = perfis.filter((p) =>
    p.nome.toLowerCase().includes(search.toLowerCase()) ||
    p.descricao?.toLowerCase().includes(search.toLowerCase())
  );

  const perfisSistema = perfisFiltered.filter((p) => p.tipo !== "personalizado");
  const perfisPersonalizados = perfisFiltered.filter((p) => p.tipo === "personalizado");
  const templateIds = new Set(perfis.map((p) => p.template_origem_id).filter(Boolean));

  const handleCreateOrEdit = async (data: Partial<PerfilAcesso> & { permissoes: Partial<PerfilPermissao>[] }) => {
    setSubmitting(true);
    try {
      if (perfilEditando) {
        await updatePerfil.mutateAsync({ id: perfilEditando.id, ...data });
      } else {
        await createPerfil.mutateAsync(data);
      }
      setPerfilFormOpen(false);
      setPerfilEditando(undefined);
    } finally {
      setSubmitting(false);
    }
  };

  const handleEditar = (perfil: PerfilAcesso) => {
    setPerfilEditando(perfil);
    setPerfilFormOpen(true);
  };

  const handleClonar = async (perfil: PerfilAcesso) => {
    await createPerfil.mutateAsync({
      nome: `${perfil.nome} (cópia)`,
      descricao: perfil.descricao,
      cor: perfil.cor,
      icone: perfil.icone,
      tipo: "personalizado",
      permissoes: perfil.permissoes || [],
    });
  };

  const loading = loadingTemplates || loadingPerfis;
  const perfisRiscoCritico = perfis.filter((p) => p.nivel_risco === "critico").length;
  const perfisRiscoElevado = perfis.filter((p) => p.nivel_risco === "elevado").length;

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-start justify-between gap-4">
        <div className="flex items-center gap-3">
          <div className="w-9 h-9 rounded-xl bg-primary/10 flex items-center justify-center">
            <ShieldCheck className="w-5 h-5 text-primary" />
          </div>
          <div>
            <h2 className="text-lg font-semibold text-foreground">Perfis & Níveis de Acesso</h2>
            <p className="text-sm text-muted-foreground">Configure quem pode acessar o quê no YourEyes</p>
          </div>
        </div>
        <Button onClick={() => { setPerfilEditando(undefined); setPerfilFormOpen(true); }} className="shrink-0">
          <Plus className="w-4 h-4 mr-2" /> Novo Perfil
        </Button>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        {[
          { label: "Perfis ativos", value: perfis.filter((p) => p.ativo).length, color: "text-primary" },
          { label: "Templates disponíveis", value: templates.length, color: "text-violet-500" },
          { label: "Usuários com perfil", value: vinculos.length, color: "text-emerald-500" },
          { label: "Perfis personalizados", value: perfisPersonalizados.length, color: "text-amber-500" },
        ].map((stat) => (
          <div key={stat.label} className="border rounded-xl p-3 bg-card">
            <p className={`text-2xl font-bold ${stat.color}`}>{stat.value}</p>
            <p className="text-[11px] text-muted-foreground mt-0.5">{stat.label}</p>
          </div>
        ))}
      </div>

      {/* Alertas de risco */}
      {(perfisRiscoCritico > 0 || perfisRiscoElevado > 0) && (
        <div className="flex flex-wrap gap-2">
          {perfisRiscoCritico > 0 && (
            <div className="flex items-center gap-2 text-[12px] text-red-700 dark:text-red-400 bg-red-50 dark:bg-red-950/30 border border-red-200 dark:border-red-800 rounded-lg px-3 py-2">
              <ShieldCheck className="w-4 h-4" />
              <span><strong>{perfisRiscoCritico}</strong> perfil{perfisRiscoCritico > 1 ? "is" : ""} com risco crítico — revise as permissões</span>
            </div>
          )}
          {perfisRiscoElevado > 0 && (
            <div className="flex items-center gap-2 text-[12px] text-amber-700 dark:text-amber-400 bg-amber-50 dark:bg-amber-950/30 border border-amber-200 dark:border-amber-800 rounded-lg px-3 py-2">
              <ShieldCheck className="w-4 h-4" />
              <span><strong>{perfisRiscoElevado}</strong> perfil{perfisRiscoElevado > 1 ? "is" : ""} com risco elevado</span>
            </div>
          )}
        </div>
      )}

      <Tabs value={activeTab} onValueChange={setActiveTab}>
        <div className="flex items-center justify-between gap-3">
          <TabsList>
            <TabsTrigger value="perfis">
              Meus Perfis
              {perfis.length > 0 && <Badge variant="secondary" className="ml-1.5 h-4 text-[10px]">{perfis.length}</Badge>}
            </TabsTrigger>
            <TabsTrigger value="templates">
              Templates
              {templates.length > 0 && <Badge variant="secondary" className="ml-1.5 h-4 text-[10px]">{templates.length}</Badge>}
            </TabsTrigger>
            <TabsTrigger value="auditoria">
              <History className="w-3.5 h-3.5 mr-1.5" /> Auditoria
            </TabsTrigger>
          </TabsList>
          <div className="relative">
            <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
            <Input
              placeholder="Buscar perfil..."
              className="pl-8 h-8 w-52 text-sm"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
          </div>
        </div>

        <TabsContent value="perfis" className="mt-4">
          {loading ? (
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
              {Array.from({ length: 6 }).map((_, i) => <Skeleton key={i} className="h-36 rounded-xl" />)}
            </div>
          ) : perfisFiltered.length === 0 ? (
            <div className="text-center py-16 space-y-3">
              <LayoutGrid className="w-10 h-10 text-muted-foreground/30 mx-auto" />
              <p className="text-muted-foreground font-medium">Nenhum perfil encontrado</p>
              <p className="text-sm text-muted-foreground/60">Crie um novo perfil ou use um template do sistema como base</p>
              <Button variant="outline" size="sm" onClick={() => setActiveTab("templates")}>
                <RefreshCw className="w-3.5 h-3.5 mr-2" /> Ver templates
              </Button>
            </div>
          ) : (
            <div className="space-y-6">
              {perfisSistema.length > 0 && (
                <div>
                  <p className="text-[11px] font-semibold uppercase tracking-wider text-muted-foreground mb-3">Baseados em template</p>
                  <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
                    {perfisSistema.map((perfil, i) => (
                      <motion.div key={perfil.id} initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: i * 0.04 }}>
                        <PerfilCard perfil={perfil} onEdit={handleEditar} onClone={handleClonar}
                          onToggleStatus={(id, ativo) => togglePerfilStatus.mutate({ id, ativo })}
                          onVerVinculos={setPerfilVinculos} onSimular={setPerfilSimulacao}
                          usuariosCount={usuariosPorPerfil.get(perfil.id)?.size ?? 0} />
                      </motion.div>
                    ))}
                  </div>
                </div>
              )}
              {perfisPersonalizados.length > 0 && (
                <div>
                  <p className="text-[11px] font-semibold uppercase tracking-wider text-muted-foreground mb-3">Personalizados</p>
                  <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
                    {perfisPersonalizados.map((perfil, i) => (
                      <motion.div key={perfil.id} initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: i * 0.04 }}>
                        <PerfilCard perfil={perfil} onEdit={handleEditar} onClone={handleClonar}
                          onToggleStatus={(id, ativo) => togglePerfilStatus.mutate({ id, ativo })}
                          onVerVinculos={setPerfilVinculos} onSimular={setPerfilSimulacao}
                          usuariosCount={usuariosPorPerfil.get(perfil.id)?.size ?? 0} />
                      </motion.div>
                    ))}
                  </div>
                </div>
              )}
            </div>
          )}
        </TabsContent>

        <TabsContent value="templates" className="mt-4">
          {loadingTemplates ? (
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              {Array.from({ length: 8 }).map((_, i) => <Skeleton key={i} className="h-32 rounded-xl" />)}
            </div>
          ) : (
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              {templates
                .filter((t) => t.nome.toLowerCase().includes(search.toLowerCase()) || t.descricao?.toLowerCase().includes(search.toLowerCase()))
                .map((template, i) => (
                  <motion.div key={template.id} initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: i * 0.04 }}>
                    <TemplateCard template={template} onUsar={() => clonarTemplate.mutate(template)} jaClonado={templateIds.has(template.id)} />
                  </motion.div>
                ))}
            </div>
          )}
        </TabsContent>

        <TabsContent value="auditoria" className="mt-4">
          <div className="rounded-xl border border-border bg-card p-4">
            <p className="text-[13px] font-semibold text-foreground mb-1">Trilha de Auditoria — Perfis & Acessos</p>
            <p className="text-[12px] text-muted-foreground mb-4">Registro imutável de todas as alterações críticas de perfis, permissões e vínculos</p>
            <AuditLogPerfil logs={auditLogs} loading={loadingAuditLogs} />
          </div>
        </TabsContent>
      </Tabs>

      <PerfilFormDialog
        open={perfilFormOpen}
        onClose={() => { setPerfilFormOpen(false); setPerfilEditando(undefined); }}
        perfilInicial={perfilEditando}
        onSubmit={handleCreateOrEdit}
        loading={submitting}
      />

      {perfilVinculos && (
        <VinculosPerfilDialog
          open={!!perfilVinculos}
          onClose={() => setPerfilVinculos(undefined)}
          perfil={perfilVinculos}
          vinculos={vinculos}
          usuarios={usuarios}
          onVincular={(payload) => vincularPerfil.mutate(payload)}
          onDesvincular={(vinculoId) => desvincularPerfil.mutate(vinculoId)}
        />
      )}

      {perfilSimulacao && (
        <SimularAcessoDialog
          open={!!perfilSimulacao}
          onClose={() => setPerfilSimulacao(undefined)}
          perfil={perfilSimulacao}
        />
      )}
    </div>
  );
}
