import { motion } from "framer-motion";
import { PilaresSummaryLive } from "@/components/dashboard/PilaresSummaryLive";
import { DashboardKPIs } from "@/components/dashboard/DashboardKPIs";
import { QuickActions } from "@/components/dashboard/QuickActions";
import { AlertasCriticos } from "@/components/dashboard/AlertasCriticos";
import { PendingTasks } from "@/components/dashboard/PendingTasks";
import { CalendarDays } from "lucide-react";
import { useMeuPerfilInicio } from "@/hooks/useMeuPerfilInicio";
import { useAuthContext } from "@/contexts/AuthContext";

const Dashboard = () => {
  const { profile } = useAuthContext();
  const { blocos, isLoading } = useMeuPerfilInicio();
  // blocos === null → painel completo (perfil legado / sem perfil / dono).
  // Enquanto carrega o perfil, nada sensível é montado (evita piscar números).
  const mostra = (b: string) => !isLoading && (blocos === null || blocos.includes(b as never));
  const semBlocos = !isLoading && blocos !== null && blocos.length === 0;
  const today = new Date().toLocaleDateString("pt-BR", {
    weekday: "long",
    day: "numeric",
    month: "long",
    year: "numeric",
  });

  return (
    <div className="space-y-8 pb-8">
      {/* Page Header */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
        className="flex flex-col md:flex-row md:items-end justify-between gap-4"
      >
        <div>
          <h1 className="text-3xl font-bold text-foreground tracking-tight">
            {blocos === null ? "Dashboard" : `Olá, ${profile?.nome_completo?.split(" ")[0] || "bem-vindo"}`}
          </h1>
          <p className="text-muted-foreground mt-1">
            Plataforma de Governança do Trabalho Humano
          </p>
        </div>
        <div className="flex items-center gap-2 text-sm text-muted-foreground bg-muted/60 px-4 py-2 rounded-lg">
          <CalendarDays className="w-4 h-4" />
          <span className="capitalize">{today}</span>
        </div>
      </motion.div>

      {/* Pilares Summary - Visão Geral */}
      {mostra("pilares") && <PilaresSummaryLive />}

      {/* KPIs Operacionais */}
      {mostra("indicadores") && <DashboardKPIs />}

      {/* Pendências */}
      {mostra("pendencias") && <PendingTasks />}

      {/* Alertas Críticos */}
      {mostra("alertas") && <AlertasCriticos />}

      {semBlocos && (
        <p className="text-sm text-muted-foreground">
          Use o menu ao lado para acessar os módulos liberados para o seu perfil.
        </p>
      )}
    </div>
  );
};

export default Dashboard;
