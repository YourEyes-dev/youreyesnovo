import { useState } from "react";
import { ShieldCheck, ShieldAlert, Gavel, Megaphone, SlidersHorizontal, BarChart3, Store } from "lucide-react";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Button } from "@/components/ui/button";
import { ModeracaoPanel } from "@/components/marketplace/ModeracaoPanel";
import { DenunciasList } from "@/components/marketplace/DenunciasList";
import { ContestacoesPanel, ParametrosPanel, LiquidezPanel, DestaquesPanel } from "@/components/marketplace/GovernancaPanel";

// Administração do MarketYE: só a equipe da casa (Super Admin) vê isto.
// A empresa cliente vê a vitrine (/marketplace); o prestador vê o portal
// dele (/marketye/portal). Nada de administração misturada nessas telas.
export function MarketYEAdminPanel() {
  const [aba, setAba] = useState("moderacao");
  return (
    <div className="space-y-4" data-testid="admin-marketye">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="text-lg font-semibold flex items-center gap-2"><Store className="w-5 h-5" />MarketYE</h2>
          <p className="text-sm text-muted-foreground">Quem entra na vitrine, denúncias, pedidos de revisão, destaques, ajustes e o retrato de oferta e procura.</p>
        </div>
        <Button asChild variant="outline" size="sm">
          <a href={`${import.meta.env.BASE_URL.replace(/\/$/, "")}/marketplace`} target="_blank" rel="noreferrer">Ver a vitrine como empresa</a>
        </Button>
      </div>
      <Tabs value={aba} onValueChange={setAba}>
        <TabsList className="flex-wrap h-auto">
          <TabsTrigger value="moderacao" className="gap-1.5" data-testid="admin-marketye-aprovar"><ShieldCheck className="h-4 w-4" /> Aprovar cadastros</TabsTrigger>
          <TabsTrigger value="denuncias" className="gap-1.5"><ShieldAlert className="h-4 w-4" /> Denúncias</TabsTrigger>
          <TabsTrigger value="contestacoes" className="gap-1.5"><Gavel className="h-4 w-4" /> Pedidos de revisão</TabsTrigger>
          <TabsTrigger value="destaques" className="gap-1.5"><Megaphone className="h-4 w-4" /> Destaques</TabsTrigger>
          <TabsTrigger value="parametros" className="gap-1.5" data-testid="admin-marketye-ajustes"><SlidersHorizontal className="h-4 w-4" /> Ajustes</TabsTrigger>
          <TabsTrigger value="liquidez" className="gap-1.5"><BarChart3 className="h-4 w-4" /> Oferta e procura</TabsTrigger>
        </TabsList>
        <TabsContent value="moderacao" className="mt-4"><ModeracaoPanel ativo={aba === "moderacao"} /></TabsContent>
        <TabsContent value="denuncias" className="mt-4"><DenunciasList /></TabsContent>
        <TabsContent value="contestacoes" className="mt-4"><ContestacoesPanel ativo={aba === "contestacoes"} /></TabsContent>
        <TabsContent value="destaques" className="mt-4"><DestaquesPanel ativo={aba === "destaques"} /></TabsContent>
        <TabsContent value="parametros" className="mt-4"><ParametrosPanel ativo={aba === "parametros"} /></TabsContent>
        <TabsContent value="liquidez" className="mt-4"><LiquidezPanel ativo={aba === "liquidez"} /></TabsContent>
      </Tabs>
    </div>
  );
}
