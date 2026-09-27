import { useState } from "react";
import { motion } from "framer-motion";
import { BookOpen, Briefcase, Settings, ChevronLeft, LayoutDashboard, FileSignature } from "lucide-react";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useCargos } from "@/hooks/useCadastros";
import { FuncaoList } from "@/components/aprendizado/FuncaoList";
import { FuncaoDetail } from "@/components/aprendizado/FuncaoDetail";
import { AprendizadoStats } from "@/components/aprendizado/AprendizadoStats";
import { AprendizadoConfig } from "@/components/aprendizado/AprendizadoConfig";
import { AssinaturasManualTab } from "@/components/aprendizado/AssinaturasManualTab";
import { Button } from "@/components/ui/button";

export default function AprendizadoPapeis() {
  const { cargos, isLoading } = useCargos();
  const [selectedCargoId, setSelectedCargoId] = useState<string | null>(null);
  const [tab, setTab] = useState("funcoes");

  const selectedCargo = cargos.find((c) => c.id === selectedCargoId);

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      className="space-y-6"
    >
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-foreground flex items-center gap-2">
            <BookOpen className="w-7 h-7 text-primary" />
            Aprendizado & Papéis
          </h1>
          <p className="text-muted-foreground mt-1">
            Organização do trabalho, conhecimento e ergonomia cognitiva
          </p>
        </div>
      </div>

      <Tabs value={tab} onValueChange={setTab}>
        <TabsList>
          <TabsTrigger value="funcoes" className="gap-1">
            <Briefcase className="w-4 h-4" /> Funções
          </TabsTrigger>
          <TabsTrigger value="assinaturas" className="gap-1">
            <FileSignature className="w-4 h-4" /> Assinaturas
          </TabsTrigger>
          <TabsTrigger value="indicadores" className="gap-1">
            <LayoutDashboard className="w-4 h-4" /> Visão geral
          </TabsTrigger>
          <TabsTrigger value="config" className="gap-1">
            <Settings className="w-4 h-4" /> Configurações
          </TabsTrigger>
        </TabsList>

        <TabsContent value="funcoes" className="mt-4">
          {selectedCargo ? (
            <div className="space-y-4">
              <Button variant="ghost" size="sm" onClick={() => setSelectedCargoId(null)}>
                <ChevronLeft className="w-4 h-4 mr-1" /> Voltar à lista
              </Button>
              <FuncaoDetail cargo={selectedCargo} />
            </div>
          ) : (
            <FuncaoList
              cargos={cargos}
              isLoading={isLoading}
              onSelect={(id) => setSelectedCargoId(id)}
            />
          )}
        </TabsContent>

        <TabsContent value="assinaturas" className="mt-4">
          <AssinaturasManualTab />
        </TabsContent>

        <TabsContent value="indicadores" className="mt-4">
          <AprendizadoStats cargos={cargos} />
        </TabsContent>

        <TabsContent value="config" className="mt-4">
          <AprendizadoConfig />
        </TabsContent>
      </Tabs>
    </motion.div>
  );
}
