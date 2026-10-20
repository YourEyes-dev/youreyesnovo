import { useState, useEffect } from "react";
import { motion } from "framer-motion";
import { Users, ClipboardList, ShieldCheck, Rocket, ArrowRight, Shield } from "lucide-react";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { AuditoriaTab } from "@/components/configuracoes/AuditoriaTab";
import { useAuthContext } from "@/contexts/AuthContext";
import { useNavigate } from "react-router-dom";
import { Button } from "@/components/ui/button";
import UsuariosContent from "@/components/configuracoes/UsuariosContent";
import PerfisContent from "@/components/configuracoes/PerfisContent";
import { EsocialConfig } from "@/components/esocial/EsocialConfig";
import { supabase } from "@/integrations/supabase/client";

export default function Configuracoes() {
  const { hasMinimumRole, profile, isSuperAdmin } = useAuthContext();
  const isAdmin = hasMinimumRole("admin");
  const navigate = useNavigate();

  const profileOnboardingIncomplete = !!profile && !(profile as any).onboarding_concluido && !isSuperAdmin;
  const tenantId = (profile as any)?.tenant_id;
  const [tenantHasData, setTenantHasData] = useState<boolean | null>(null);

  useEffect(() => {
    if (!profileOnboardingIncomplete || !tenantId) {
      setTenantHasData(false);
      return;
    }
    supabase
      .from("empresa_cadastro")
      .select("id", { count: "exact", head: true })
      .eq("tenant_id", tenantId)
      .then(({ count }) => {
        const hasData = (count ?? 0) > 0;
        setTenantHasData(hasData);
        if (hasData) {
          // Self-heal: mark this user's onboarding as concluded
          supabase
            .from("profiles")
            .update({ onboarding_concluido: true })
            .eq("user_id", (profile as any).user_id)
            .then(() => {});
        }
      });
  }, [profileOnboardingIncomplete, tenantId]);

  const needsOnboarding = profileOnboardingIncomplete && tenantHasData === false;

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-foreground">Usuários</h1>
        <p className="text-muted-foreground">Gerencie sua equipe, níveis de acesso e auditoria</p>
      </div>

      {needsOnboarding && (
        <motion.div
          initial={{ opacity: 0, y: -8 }}
          animate={{ opacity: 1, y: 0 }}
          className="flex items-center justify-between gap-4 p-4 bg-primary/5 border border-primary/15 rounded-xl"
        >
          <div className="flex items-center gap-3">
            <div className="p-2 bg-primary/10 rounded-lg">
              <Rocket className="w-5 h-5 text-primary" />
            </div>
            <div>
              <p className="text-sm font-semibold text-foreground">Configuração inicial pendente</p>
              <p className="text-xs text-muted-foreground">
                Finalize o onboarding para liberar todos os recursos do sistema.
              </p>
            </div>
          </div>
          <Button size="sm" onClick={() => {
            const token = (profile as any)?.onboarding_token;
            if (token) {
              navigate(`/onboarding-cliente/${token}`);
            } else {
              navigate("/onboarding");
            }
          }} className="gap-1.5 shrink-0">
            Finalizar Configuração
            <ArrowRight className="w-3.5 h-3.5" />
          </Button>
        </motion.div>
      )}

      <Tabs defaultValue="usuarios">
        <TabsList>
          {isAdmin && (
            <TabsTrigger value="usuarios" className="flex items-center gap-1.5">
              <Users className="h-4 w-4" />
              <span className="hidden sm:inline">Usuários</span>
            </TabsTrigger>
          )}
          {isAdmin && (
            <TabsTrigger value="perfis" className="flex items-center gap-1.5">
              <ShieldCheck className="h-4 w-4" />
              <span className="hidden sm:inline">Perfis & Acessos</span>
            </TabsTrigger>
          )}
          {isAdmin && (
            <TabsTrigger value="esocial" className="flex items-center gap-1.5">
              <Shield className="h-4 w-4" />
              <span className="hidden sm:inline">eSocial</span>
            </TabsTrigger>
          )}
          {isAdmin && (
            <TabsTrigger value="auditoria" className="flex items-center gap-1.5">
              <ClipboardList className="h-4 w-4" />
              <span className="hidden sm:inline">Auditoria</span>
            </TabsTrigger>
          )}
        </TabsList>

        {isAdmin && (
          <TabsContent value="usuarios" className="mt-6">
            <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }}>
              <UsuariosContent />
            </motion.div>
          </TabsContent>
        )}

        {isAdmin && (
          <TabsContent value="perfis" className="mt-6">
            <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }}>
              <PerfisContent />
            </motion.div>
          </TabsContent>
        )}

        {isAdmin && (
          <TabsContent value="esocial" className="mt-6">
            <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }}>
              <EsocialConfig />
            </motion.div>
          </TabsContent>
        )}

        {isAdmin && (
          <TabsContent value="auditoria" className="mt-6">
            <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }}>
              <AuditoriaTab />
            </motion.div>
          </TabsContent>
        )}
      </Tabs>
    </div>
  );
}
