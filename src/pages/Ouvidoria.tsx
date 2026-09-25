import { useState } from "react";
import { motion } from "framer-motion";
import { MessageSquareHeart, Plus, List, Settings } from "lucide-react";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useOuvidoria } from "@/hooks/useOuvidoria";
import { useAuth } from "@/hooks/useAuth";
import { OuvidoriaForm } from "@/components/ouvidoria/OuvidoriaForm";
import { OuvidoriaList } from "@/components/ouvidoria/OuvidoriaList";
import { OuvidoriaStats } from "@/components/ouvidoria/OuvidoriaStats";
import { OuvidoriaRoteamentoConfig } from "@/components/ouvidoria/OuvidoriaRoteamentoConfig";
import { OuvidoriaLinkTab } from "@/components/ouvidoria/OuvidoriaLinkTab";
import type { StatusManifestacao, PrioridadeManifestacao } from "@/types/ouvidoria";

const Ouvidoria = () => {
  const [activeTab, setActiveTab] = useState("enviar");
  const { hasMinimumRole, hasRole } = useAuth();
  const {
    manifestacoes,
    manifestacoesLoading,
    criarManifestacao,
    criandoManifestacao,
    responderManifestacao,
    respondendoManifestacao,
    atualizarStatus,
    deletarManifestacao,
    stats,
  } = useOuvidoria();

  const isManager = hasMinimumRole("manager");
  const isAdmin = hasMinimumRole("admin");

  const handleSubmit = async (data: Parameters<typeof criarManifestacao>[0]) => {
    await criarManifestacao(data);
    if (isManager) {
      setActiveTab("manifestacoes");
    }
  };

  const handleResponder = async (id: string, resposta: string) => {
    await responderManifestacao({ id, resposta });
  };

  const handleAtualizarStatus = async (id: string, status: StatusManifestacao, prioridade?: PrioridadeManifestacao) => {
    await atualizarStatus({ id, status, prioridade });
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4"
      >
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <MessageSquareHeart className="w-7 h-7 text-primary" />
            Ouvidoria
          </h1>
          <p className="text-muted-foreground">
            Canal de comunicação para sugestões, reclamações, denúncias e elogios
          </p>
        </div>
      </motion.div>

      {/* Stats (apenas para managers) */}
      {isManager && <OuvidoriaStats stats={stats} />}

      {/* Tabs */}
      <Tabs value={activeTab} onValueChange={setActiveTab}>
        <TabsList className={`grid w-full max-w-lg ${isAdmin ? "grid-cols-3" : "grid-cols-2"}`}>
          <TabsTrigger value="enviar" className="flex items-center gap-2">
            <Plus className="w-4 h-4" />
            Nova Manifestação
          </TabsTrigger>
          <TabsTrigger value="manifestacoes" className="flex items-center gap-2">
            <List className="w-4 h-4" />
            {isManager ? "Todas Manifestações" : "Minhas Manifestações"}
          </TabsTrigger>
          {isAdmin && (
            <TabsTrigger value="configuracoes" className="flex items-center gap-2">
              <Settings className="w-4 h-4" />
              Configurações
            </TabsTrigger>
          )}
        </TabsList>

        <TabsContent value="enviar" className="mt-6">
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="max-w-2xl mx-auto"
          >
            <OuvidoriaForm
              onSubmit={handleSubmit}
              isLoading={criandoManifestacao}
            />
          </motion.div>
        </TabsContent>

        <TabsContent value="manifestacoes" className="mt-6">
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="bg-card rounded-xl border p-6"
          >
            <h2 className="text-lg font-semibold mb-4">
              {isManager ? "Todas as Manifestações" : "Minhas Manifestações"}
            </h2>
            <OuvidoriaList
              manifestacoes={manifestacoes}
              isLoading={manifestacoesLoading}
              isManager={isManager}
              onResponder={isManager ? handleResponder : undefined}
              onAtualizarStatus={isManager ? handleAtualizarStatus : undefined}
              onDeletar={isAdmin ? deletarManifestacao : undefined}
            />
          </motion.div>
        </TabsContent>

        {isAdmin && (
          <TabsContent value="configuracoes" className="mt-6">
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              className="max-w-3xl mx-auto space-y-8"
            >
              <OuvidoriaLinkTab />
              <OuvidoriaRoteamentoConfig />
            </motion.div>
          </TabsContent>
        )}
      </Tabs>
    </div>
  );
};

export default Ouvidoria;
