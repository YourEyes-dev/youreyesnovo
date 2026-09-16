import { useState, useEffect, useMemo } from "react";
import { useSearchParams } from "react-router-dom";
import { motion } from "framer-motion";
import { Plus, HardHat, Package, Users, History, Shield, AlertTriangle, Wrench, ArrowDownCircle, Warehouse, ShieldCheck, HelpCircle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { ScrollArea, ScrollBar } from "@/components/ui/scroll-area";
import { useEpis } from "@/hooks/useEpis";
import { useEpiPermissions } from "@/hooks/useEpiPermissions";
import { EpiList } from "@/components/epi/EpiList";
import { EpiForm } from "@/components/epi/EpiForm";
import { EpiTipoForm } from "@/components/epi/EpiTipoForm";
import { EpiEntregaWizard } from "@/components/epi/entrega/EpiEntregaWizard";
import { EpiEntregaList } from "@/components/epi/EpiEntregaList";
import { EpiMovimentacoes } from "@/components/epi/EpiMovimentacoes";
import { AjustarEstoqueModal } from "@/components/epi/AjustarEstoqueModal";
import { MatrizProtecaoTab } from "@/components/epi/MatrizProtecaoTab";
import { EpiAlertasTab } from "@/components/epi/EpiAlertasTab";
import { EpiFiscalIATab } from "@/components/epi/EpiFiscalIATab";
import { EpiConfiguracaoTab } from "@/components/epi/EpiConfiguracaoTab";
import { EntradasEstoqueTab } from "@/components/epi/EntradasEstoqueTab";
import { SaldoLocalDashboard } from "@/components/epi/SaldoLocalDashboard";
import { EpiStatsCards } from "@/components/epi/EpiStatsCards";
import { GuiaRapidoEpi } from "@/components/epi/GuiaRapidoEpi";
import type { EpiCompleto } from "@/types/epi";

const Epis = () => {
  const {
    tipos, tiposLoading, customCategorias, categorias, epis, episLoading,
    entregas, entregasLoading, movimentacoes, movimentacoesLoading,
    stats, criarCategoria, criandoCategoria, criarTipo, criandoTipo,
    criarEpi, criandoEpi, atualizarEpi, atualizandoEpi, excluirEpi,
    ajustarEstoque, registrarEntrega, registrandoEntrega, registrarDevolucao,
  } = useEpis();

  // Quais categorias exigem CA, por nome (o formulário lê por nome porque é
  // assim que epi_tipos.categoria guarda a categoria).
  const categoriasExigemCa = useMemo(
    () => Object.fromEntries((categorias || []).map((c) => [c.nome, c.exige_ca])),
    [categorias]
  );

  const perm = useEpiPermissions();
  const [searchParams] = useSearchParams();
  const [activeTab, setActiveTab] = useState("entregas");

  // Sync tab from URL query param (used by QA Agent)
  useEffect(() => {
    const tab = searchParams.get("tab");
    if (tab) setActiveTab(tab);
  }, [searchParams]);
  const [showTipoForm, setShowTipoForm] = useState(false);
  const [showEpiForm, setShowEpiForm] = useState(false);
  const [showEntregaForm, setShowEntregaForm] = useState(false);
  const [showGuia, setShowGuia] = useState(false);
  const [editingEpi, setEditingEpi] = useState<EpiCompleto | null>(null);
  const [ajustarEstoqueEpi, setAjustarEstoqueEpi] = useState<EpiCompleto | null>(null);

  const handleCreateEpi = async (data: any) => { await criarEpi(data); };
  const handleUpdateEpi = async (data: any) => {
    if (editingEpi) { await atualizarEpi({ id: editingEpi.id, ...data }); setEditingEpi(null); }
  };
  const handleEditEpi = (epi: EpiCompleto) => { setEditingEpi(epi); setShowEpiForm(true); };

  const handleCardClick = (tab: string) => setActiveTab(tab);

  return (
    <div className="space-y-6">
      {/* Header */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className="flex flex-col gap-3"
      >
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-lg sm:text-2xl font-bold flex items-center gap-2">
              <HardHat className="w-5 h-5 sm:w-7 sm:h-7 text-primary" />
              Gestão de EPIs
            </h1>
            <p className="text-muted-foreground text-xs sm:text-sm">
              Controle de equipamentos de proteção individual
            </p>
          </div>
          <Button id="btn-epi-guia-mobile" variant="ghost" size="icon" onClick={() => setShowGuia(true)} className="text-primary shrink-0 sm:hidden">
            <HelpCircle className="h-5 w-5" />
          </Button>
        </div>
        <div className="flex gap-2 flex-wrap">
          <Button id="btn-epi-guia-rapido" variant="outline" size="sm" onClick={() => setShowGuia(true)} className="gap-2 text-primary border-primary/30 hover:bg-primary/5 hidden sm:flex">
            <HelpCircle className="h-4 w-4" />
            Guia Rápido
          </Button>
          {perm.podeCriarTipo && (
            <Button id="btn-epi-nova-categoria" variant="outline" size="sm" onClick={() => setShowTipoForm(true)} className="text-xs sm:text-sm">
              <Plus className="w-3.5 h-3.5 sm:w-4 sm:h-4 mr-1" /> Categoria
            </Button>
          )}
          {perm.podeCriarEpi && (
            <Button id="btn-epi-novo" variant="outline" size="sm" onClick={() => setShowEpiForm(true)} className="text-xs sm:text-sm">
              <Plus className="w-3.5 h-3.5 sm:w-4 sm:h-4 mr-1" /> Novo EPI
            </Button>
          )}
          {perm.podeRegistrarEntrega && (
            <Button id="btn-epi-entrega" onClick={() => setShowEntregaForm(true)} size="sm" className="text-xs sm:text-sm">
              <Users className="w-3.5 h-3.5 sm:w-4 sm:h-4 mr-1" /> Entrega
            </Button>
          )}
        </div>
      </motion.div>

      {/* Stats Cards - Clickable */}
      <EpiStatsCards stats={stats} onCardClick={handleCardClick} />

      {/* Tabs - Reordered for daily use */}
      <Tabs value={activeTab} onValueChange={setActiveTab}>
        <ScrollArea className="w-full">
          <TabsList className="inline-flex w-max min-w-full sm:flex sm:w-full sm:max-w-6xl sm:flex-wrap gap-0.5">
            <TabsTrigger id="tab-epi-entregas" value="entregas" className="flex items-center gap-1 text-xs sm:text-sm sm:gap-1.5">
              <Users className="w-3.5 h-3.5 sm:w-4 sm:h-4" /> Entregas
            </TabsTrigger>
            <TabsTrigger id="tab-epi-estoque" value="estoque" className="flex items-center gap-1 text-xs sm:text-sm sm:gap-1.5">
              <Package className="w-3.5 h-3.5 sm:w-4 sm:h-4" /> Estoque
            </TabsTrigger>
            <TabsTrigger id="tab-epi-saldo-local" value="saldo-local" className="flex items-center gap-1 text-xs sm:text-sm sm:gap-1.5">
              <Warehouse className="w-3.5 h-3.5 sm:w-4 sm:h-4" /> Local
            </TabsTrigger>
            {perm.podeMovimentarEstoque && (
              <TabsTrigger id="tab-epi-entradas" value="entradas" className="flex items-center gap-1 text-xs sm:text-sm sm:gap-1.5">
                <ArrowDownCircle className="w-3.5 h-3.5 sm:w-4 sm:h-4" /> Mov.
              </TabsTrigger>
            )}
            <TabsTrigger id="tab-epi-alertas" value="alertas" className="flex items-center gap-1 text-xs sm:text-sm sm:gap-1.5">
              <AlertTriangle className="w-3.5 h-3.5 sm:w-4 sm:h-4" /> Alertas
            </TabsTrigger>
            {perm.podeGerenciarMatriz && (
              <TabsTrigger id="tab-epi-matriz" value="matriz" className="flex items-center gap-1 text-xs sm:text-sm sm:gap-1.5">
                <Shield className="w-3.5 h-3.5 sm:w-4 sm:h-4" /> Matriz
              </TabsTrigger>
            )}
            {perm.podeUsarIAFiscal && (
              <TabsTrigger id="tab-epi-fiscal" value="fiscal" className="flex items-center gap-1 text-xs sm:text-sm sm:gap-1.5">
                <ShieldCheck className="w-3.5 h-3.5 sm:w-4 sm:h-4" /> Auditoria
              </TabsTrigger>
            )}
            <TabsTrigger id="tab-epi-historico" value="historico" className="flex items-center gap-1 text-xs sm:text-sm sm:gap-1.5">
              <History className="w-3.5 h-3.5 sm:w-4 sm:h-4" /> Histórico
            </TabsTrigger>
            {perm.podeConfigurar && (
              <TabsTrigger id="tab-epi-config" value="config" className="flex items-center gap-1 text-xs sm:text-sm sm:gap-1.5">
                <Wrench className="w-3.5 h-3.5 sm:w-4 sm:h-4" /> Config
              </TabsTrigger>
            )}
          </TabsList>
          <ScrollBar orientation="horizontal" />
        </ScrollArea>

        <TabsContent value="entregas" className="mt-6">
          <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="bg-card rounded-xl border p-6">
            <h2 className="text-lg font-semibold mb-4">Controle de Entregas</h2>
            <EpiEntregaList
              entregas={entregas} isLoading={entregasLoading}
              onDevolucao={perm.podeRegistrarDevolucao ? async (id: string, obs?: string, destino?: "manutencao" | "descarte" | "estoque") => {
                await registrarDevolucao({ entregaId: id, observacoes: obs, destino });
              } : undefined}
            />
          </motion.div>
        </TabsContent>

        <TabsContent value="estoque" className="mt-6">
          <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="bg-card rounded-xl border p-6">
            <h2 className="text-lg font-semibold mb-4">EPIs em Estoque</h2>
            <EpiList epis={epis} isLoading={episLoading}
              onEdit={perm.podeEditarEpi ? handleEditEpi : undefined}
              onDelete={perm.podeExcluirEpi ? excluirEpi : undefined}
              onAjustarEstoque={perm.podeAjustarEstoque ? setAjustarEstoqueEpi : undefined}
            />
          </motion.div>
        </TabsContent>

        <TabsContent value="saldo-local" className="mt-6">
          <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }}><SaldoLocalDashboard /></motion.div>
        </TabsContent>

        <TabsContent value="entradas" className="mt-6">
          <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }}><EntradasEstoqueTab /></motion.div>
        </TabsContent>

        <TabsContent value="alertas" className="mt-6">
          <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }}>
            <EpiAlertasTab epis={epis} entregas={entregas} tipos={tipos} />
          </motion.div>
        </TabsContent>

        <TabsContent value="matriz" className="mt-6">
          <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }}><MatrizProtecaoTab /></motion.div>
        </TabsContent>

        <TabsContent value="fiscal" className="mt-6">
          <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }}><EpiFiscalIATab /></motion.div>
        </TabsContent>

        <TabsContent value="historico" className="mt-6">
          <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="bg-card rounded-xl border p-6">
            <h2 className="text-lg font-semibold mb-4">Histórico de Movimentações</h2>
            <EpiMovimentacoes movimentacoes={movimentacoes} isLoading={movimentacoesLoading} />
          </motion.div>
        </TabsContent>

        <TabsContent value="config" className="mt-6">
          <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }}><EpiConfiguracaoTab /></motion.div>
        </TabsContent>
      </Tabs>

      {/* Modals */}
      <EpiTipoForm open={showTipoForm} onOpenChange={setShowTipoForm}
        onSubmit={async (data) => { await criarCategoria(data.nome); }}
        customCategorias={customCategorias} isLoading={criandoCategoria}
      />
      <EpiForm
        open={showEpiForm || !!editingEpi}
        onOpenChange={(open) => { setShowEpiForm(open); if (!open) setEditingEpi(null); }}
        onSubmit={editingEpi ? handleUpdateEpi : handleCreateEpi}
        onCreateTipo={async (data) => { await criarTipo(data); }}
        onCreateCategoria={async (nome) => { await criarCategoria(nome); }}
        tipos={tipos} customCategorias={customCategorias}
        categoriasExigemCa={categoriasExigemCa} epi={editingEpi}
        isLoading={criandoEpi || atualizandoEpi}
      />
      <EpiEntregaWizard open={showEntregaForm} onOpenChange={setShowEntregaForm}
        epiTipos={tipos} onSuccess={() => {}}
      />
      <AjustarEstoqueModal epi={ajustarEstoqueEpi} open={!!ajustarEstoqueEpi}
        onOpenChange={(open) => { if (!open) setAjustarEstoqueEpi(null); }}
        onConfirm={async (epiId, novaQuantidade, motivo) => { await ajustarEstoque({ epiId, novaQuantidade, motivo }); }}
      />
      <GuiaRapidoEpi open={showGuia} onOpenChange={setShowGuia} />
    </div>
  );
};

export default Epis;
