import { useState, useEffect } from "react";
import { motion } from "framer-motion";
import { useSearchParams } from "react-router-dom";
import { Fingerprint, LayoutDashboard, UserCircle2 } from "lucide-react";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useMapaComportamentalPermissoes } from "@/hooks/useMapaComportamentalPermissoes";
import { MeuMapaTab } from "@/components/mapa-comportamental/MeuMapaTab";
import { PainelMapaTab } from "@/components/mapa-comportamental/PainelMapaTab";

export default function MapaComportamental() {
  const { podeVerPainel } = useMapaComportamentalPermissoes();
  const [searchParams, setSearchParams] = useSearchParams();
  const tabFromUrl = searchParams.get("tab") || "meu-mapa";
  const [activeTab, setActiveTab] = useState(tabFromUrl);

  useEffect(() => {
    if (tabFromUrl !== activeTab) setActiveTab(tabFromUrl);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tabFromUrl]);

  const handleTabChange = (value: string) => {
    setActiveTab(value);
    const next = new URLSearchParams(searchParams);
    if (value === "meu-mapa") next.delete("tab");
    else next.set("tab", value);
    setSearchParams(next, { replace: true });
  };

  return (
    <div className="space-y-6">
      <motion.div
        initial={{ opacity: 0, y: -10 }}
        animate={{ opacity: 1, y: 0 }}
        className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-indigo-500 via-violet-500 to-fuchsia-600 p-6 sm:p-8 shadow-[0_20px_50px_-20px_hsl(var(--primary)/0.5)]"
      >
        <div className="absolute -top-16 -right-16 w-64 h-64 bg-white/15 rounded-full blur-3xl pointer-events-none" />
        <div className="absolute -bottom-20 -left-20 w-72 h-72 bg-white/10 rounded-full blur-3xl pointer-events-none" />
        <div className="relative flex items-start gap-4 text-white">
          <div className="p-3 rounded-2xl bg-white/20 backdrop-blur-sm border border-white/30 shadow-lg shrink-0">
            <Fingerprint className="w-7 h-7 drop-shadow" />
          </div>
          <div className="flex-1 min-w-0">
            <h1 className="text-2xl sm:text-3xl font-bold">Mapa Comportamental</h1>
            <p className="mt-1 text-white/90 max-w-2xl">
              Um mapa de autopercepção que traduz o seu jeito de trabalhar numa linguagem comum — e
              orienta o desenvolvimento. Não é teste, não mede capacidade e não decide sobre a sua
              carreira. Você vê o seu resultado primeiro.
            </p>
          </div>
        </div>
      </motion.div>

      <Tabs value={activeTab} onValueChange={handleTabChange} className="space-y-4">
        <TabsList>
          <TabsTrigger value="meu-mapa" className="gap-2">
            <UserCircle2 className="w-4 h-4" /> Meu Mapa
          </TabsTrigger>
          {podeVerPainel && (
            <TabsTrigger value="painel" className="gap-2">
              <LayoutDashboard className="w-4 h-4" /> Painel
            </TabsTrigger>
          )}
        </TabsList>

        <TabsContent value="meu-mapa">
          <MeuMapaTab />
        </TabsContent>
        {podeVerPainel && (
          <TabsContent value="painel">
            <PainelMapaTab />
          </TabsContent>
        )}
      </Tabs>
    </div>
  );
}
