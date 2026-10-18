import { motion } from "framer-motion";
import { Sparkles } from "lucide-react";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useCultura } from "@/hooks/useCultura";
import { CulturaStats } from "@/components/cultura/CulturaStats";
import { AgendaCelebracoes } from "@/components/cultura/AgendaCelebracoes";
import { RituaisReconhecimento } from "@/components/cultura/RituaisReconhecimento";
import { ProximasCelebracoes } from "@/components/cultura/ProximasCelebracoes";
import { PreferenciasColaborador } from "@/components/cultura/PreferenciasColaborador";
import { HojeCelebracoes } from "@/components/cultura/HojeCelebracoes";
import { CalendarioCelebracoes } from "@/components/cultura/CalendarioCelebracoes";
import { CulturaIndicadores } from "@/components/cultura/CulturaIndicadores";

const CulturaCelebracoes = () => {
  const cultura = useCultura();

  return (
    <div className="space-y-6">
      <motion.div initial={{ opacity: 0, y: -10 }} animate={{ opacity: 1, y: 0 }} className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-foreground flex items-center gap-2">
            <Sparkles className="w-7 h-7 text-primary" />
            Cultura &amp; Celebrações
          </h1>
          <p className="text-muted-foreground mt-1">
            Cultura não se improvisa. Se planeja, se executa e se acompanha.
          </p>
        </div>
      </motion.div>

      <HojeCelebracoes
        acoes={cultura.acoes}
        rituais={cultura.rituais}
        preferencias={cultura.preferencias}
        onParabenizar={cultura.parabenizar}
        onRegistrarRitual={cultura.registrarRealizacaoRitual}
      />

      <CulturaStats
        datasAtivas={cultura.datasAtivas}
        acoesPendentes={cultura.acoesPendentes}
        acoesConcluidas={cultura.acoesConcluidas}
        rituaisAtivos={cultura.rituaisAtivos}
      />

      <CalendarioCelebracoes
        acoes={cultura.acoes}
        rituais={cultura.rituais}
        datas={cultura.datas}
        preferencias={cultura.preferencias}
      />

      <ProximasCelebracoes
        acoes={cultura.acoes}
        preferencias={cultura.preferencias}
        onCreateAcao={cultura.createAcao}
        onUpdateStatus={cultura.updateAcaoStatus}
      />

      <CulturaIndicadores
        acoes={cultura.acoes}
        rituais={cultura.rituais}
      />

      <Tabs defaultValue="experiencia" className="space-y-4">
        <TabsList>
          <TabsTrigger value="experiencia">Experiência do Colaborador</TabsTrigger>
          <TabsTrigger value="preferencias">Preferências</TabsTrigger>
          <TabsTrigger value="rituais">Rituais e Reconhecimento</TabsTrigger>
        </TabsList>

        <TabsContent value="experiencia">
          <AgendaCelebracoes
            acoes={cultura.acoes}
            isLoading={cultura.isLoadingAcoes}
            onCreateAcao={cultura.createAcao}
            onUpdateStatus={cultura.updateAcaoStatus}
            onDelete={cultura.deleteAcao}
          />
        </TabsContent>

        <TabsContent value="preferencias">
          <PreferenciasColaborador
            preferencias={cultura.preferencias}
            onCreatePreferencia={cultura.createPreferencia}
            onDeletePreferencia={cultura.deletePreferencia}
          />
        </TabsContent>

        <TabsContent value="rituais">
          <RituaisReconhecimento
            rituais={cultura.rituais}
            datas={cultura.datas}
            config={cultura.config ?? null}
            marcos={cultura.marcos}
            isLoadingRituais={cultura.isLoadingRituais}
            isLoadingDatas={cultura.isLoadingDatas}
            onCreateRitual={cultura.createRitual}
            onToggleRitual={cultura.toggleRitual}
            onDeleteRitual={cultura.deleteRitual}
            onRegistrarRitual={cultura.registrarRealizacaoRitual}
            onCreateData={cultura.createData}
            onDeleteData={cultura.deleteData}
            onSaveConfig={cultura.saveConfig}
            onCreateMarco={cultura.createMarco}
          />
        </TabsContent>
      </Tabs>
    </div>
  );
};

export default CulturaCelebracoes;
