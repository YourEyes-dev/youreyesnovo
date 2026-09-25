import { useState } from "react";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Shield,
  FileText,
  AlertTriangle,
  CheckCircle2,
  Upload,
  Search,
  BarChart3,
  FileCheck,
  AlertCircle,
  ArrowRight,
  Target,
  Trash2,
  Loader2,
  Brain,
  Sparkles,
  BookOpen,
  ClipboardCheck,
  HeartPulse,
} from "lucide-react";
import { useSSTDocumentos, SSTDocumento } from "@/hooks/useSSTDocumentos";
import { PsicossocialVisaoBasica } from "@/components/avaliacoes/psicossocial/PsicossocialVisaoBasica";
import { SSTAnaliseIAModal } from "@/components/sst/SSTAnaliseIAModal";
import { SSTAlertasTab } from "@/components/sst/SSTAlertasTab";
import { SSTAcoesTab } from "@/components/sst/SSTAcoesTab";
import { SSTDocumentosTab } from "@/components/sst/SSTDocumentosTab";
import { ImportacaoInteligente } from "@/components/sst/importacao/ImportacaoInteligente";
import { SSTOrdemServicoTab } from "@/components/sst/SSTOrdemServicoTab";
import { GuiaRapidoComplianceSST } from "@/components/sst/GuiaRapidoComplianceSST";
import { useNavigate } from "react-router-dom";
import { format } from "date-fns";

const ComplianceSST = () => {
  const [activeTab, setActiveTab] = useState("importacao");
  const [analiseDoc, setAnaliseDoc] = useState<SSTDocumento | null>(null);
  const [showGuia, setShowGuia] = useState(false);
  const { documentos, isLoading, deleteDocumento } = useSSTDocumentos();
  const navigate = useNavigate();

  const docVigentes = documentos.filter(d => d.status === "vigente").length;
  const docVencidos = documentos.filter(d => d.status === "vencido").length;
  const docAnalisados = documentos.filter(d => d.analise_ia_status === "concluida").length;

  const indicadores = [
    { titulo: "Documentos Vigentes", valor: String(docVigentes), icone: Shield, color: "text-primary" },
    { titulo: "Documentos Vencidos", valor: String(docVencidos), icone: AlertTriangle, color: "text-destructive" },
    { titulo: "Análises IA Concluídas", valor: String(docAnalisados), icone: Brain, color: "text-primary" },
    { titulo: "Total Documentos", valor: String(documentos.length), icone: FileText, color: "text-muted-foreground" },
  ];

  const getStatusDisplay = (doc: SSTDocumento) => {
    if (doc.data_vigencia) {
      const vig = new Date(doc.data_vigencia);
      if (vig < new Date()) return { label: "Vencido", variant: "destructive" as const };
    }
    return { label: "Vigente", variant: "default" as const };
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-foreground flex items-center gap-2">
            <Shield className="w-7 h-7 text-primary" />
            Compliance SST
          </h1>
          <p className="text-muted-foreground mt-1">
            Governança, conformidade e inteligência legal em Saúde e Segurança do Trabalho
          </p>
        </div>
        <Button variant="outline" onClick={() => setShowGuia(true)}>
          <BookOpen className="w-4 h-4 mr-2" /> Guia Rapido
        </Button>
      </div>

      {/* Disclaimer */}
      <Card className="border-amber-200 bg-amber-50 dark:bg-amber-950/20 dark:border-amber-800">
        <CardContent className="py-3 px-4 flex items-start gap-3">
          <AlertCircle className="w-5 h-5 text-amber-600 mt-0.5 flex-shrink-0" />
          <p className="text-sm text-amber-800 dark:text-amber-200">
            <strong>Aviso legal:</strong> Este módulo não substitui profissionais legalmente habilitados nem elabora documentos obrigatórios (PGR, PCMSO, LTCAT).
            Atua como orquestrador da execução, auditor de coerência e gerador de inteligência preventiva.
          </p>
        </CardContent>
      </Card>

      <Tabs value={activeTab} onValueChange={setActiveTab}>
        <TabsList className="grid grid-cols-3 md:grid-cols-8 w-full">
          <TabsTrigger value="importacao" className="text-xs md:text-sm">
            <Sparkles className="w-4 h-4 mr-1.5" />
            Importação IA
          </TabsTrigger>
          <TabsTrigger value="documentos" className="text-xs md:text-sm">
            <FileText className="w-4 h-4 mr-1.5" />
            Documentos
            {documentos.length > 0 && (
              <Badge variant="secondary" className="ml-1.5 text-[10px] px-1.5 h-4">{documentos.length}</Badge>
            )}
          </TabsTrigger>
          <TabsTrigger value="ordem-servico" className="text-xs md:text-sm">
            <ClipboardCheck className="w-4 h-4 mr-1.5" />
            Ordem De Serviço
          </TabsTrigger>
          <TabsTrigger value="painel" className="text-xs md:text-sm">
            <BarChart3 className="w-4 h-4 mr-1.5" />
            Painel
          </TabsTrigger>
          <TabsTrigger value="alertas" className="text-xs md:text-sm">
            <AlertTriangle className="w-4 h-4 mr-1.5" />
            Alertas
          </TabsTrigger>
          <TabsTrigger value="acoes" className="text-xs md:text-sm">
            <Target className="w-4 h-4 mr-1.5" />
            Ações
          </TabsTrigger>
          <TabsTrigger value="esocial" className="text-xs md:text-sm">
            <FileCheck className="w-4 h-4 mr-1.5" />
            eSocial
          </TabsTrigger>
          <TabsTrigger value="psicossocial-visao" className="text-xs md:text-sm">
            <HeartPulse className="w-4 h-4 mr-1.5" />
            Visão Psicossocial
          </TabsTrigger>
        </TabsList>

        {/* IMPORTAÇÃO INTELIGENTE */}
        <TabsContent value="psicossocial-visao" className="space-y-4">
          <PsicossocialVisaoBasica />
        </TabsContent>

        <TabsContent value="importacao" className="space-y-4">
          <ImportacaoInteligente onImportado={() => setActiveTab("documentos")} />
        </TabsContent>

        {/* DOCUMENTOS IMPORTADOS */}
        <TabsContent value="documentos" className="space-y-4">
          <SSTDocumentosTab />
        </TabsContent>

        {/* ORDEM DE SERVIÇO (NR-1) */}
        <TabsContent value="ordem-servico" className="space-y-4">
          <SSTOrdemServicoTab />
        </TabsContent>

        {/* PAINEL */}
        <TabsContent value="painel" className="space-y-6">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            {indicadores.map((ind, i) => (
              <Card key={i}>
                <CardContent className="p-4 text-center">
                  <ind.icone className={`w-6 h-6 mx-auto mb-2 ${ind.color}`} />
                  <p className="text-2xl font-bold text-foreground">{ind.valor}</p>
                  <p className="text-xs text-muted-foreground mt-1">{ind.titulo}</p>
                </CardContent>
              </Card>
            ))}
          </div>

          <div className="grid md:grid-cols-2 gap-6">
            <Card>
              <CardHeader>
                <CardTitle className="text-lg">Documentos Importados</CardTitle>
                <CardDescription>Status de vigência dos documentos</CardDescription>
              </CardHeader>
              <CardContent className="space-y-3">
                {isLoading ? (
                  <div className="flex justify-center py-4"><Loader2 className="w-6 h-6 animate-spin text-muted-foreground" /></div>
                ) : documentos.length === 0 ? (
                  <div className="text-center py-6 text-muted-foreground text-sm">
                    <FileText className="w-8 h-8 mx-auto mb-2 opacity-50" />
                    <p>Nenhum documento ainda.</p>
                    <Button variant="link" size="sm" className="mt-1" onClick={() => setActiveTab("importacao")}>
                      Importar primeiro documento →
                    </Button>
                  </div>
                ) : (
                  <>
                    {documentos.slice(0, 5).map((doc) => {
                      const st = getStatusDisplay(doc);
                      return (
                        <div key={doc.id} className="flex items-center justify-between py-2 border-b last:border-0">
                          <div className="flex items-center gap-3">
                            <FileText className="w-4 h-4 text-muted-foreground" />
                            <div>
                              <p className="font-medium text-sm">{doc.tipo}</p>
                              <p className="text-xs text-muted-foreground">{doc.profissional_responsavel || doc.empresa_emissora || doc.arquivo_nome}</p>
                            </div>
                          </div>
                          <div className="flex items-center gap-2">
                            <Badge variant={st.variant} className="text-xs">{st.label}</Badge>
                            <Button variant="ghost" size="sm" className="h-7 px-2" onClick={() => setAnaliseDoc(doc)}>
                              <Search className="w-3.5 h-3.5" />
                            </Button>
                          </div>
                        </div>
                      );
                    })}
                    {documentos.length > 5 && (
                      <Button variant="ghost" size="sm" className="w-full mt-1 text-xs" onClick={() => setActiveTab("alertas")}>
                        Ver alertas <ArrowRight className="w-3.5 h-3.5 ml-1" />
                      </Button>
                    )}
                  </>
                )}
              </CardContent>
            </Card>

            {/* Calendário de Vencimentos */}
            <Card>
              <CardHeader>
                <CardTitle className="text-lg flex items-center gap-2">
                  <AlertTriangle className="w-5 h-5 text-amber-500" />
                  Calendário de Vencimentos
                </CardTitle>
                <CardDescription>Documentos ordenados por prazo de validade</CardDescription>
              </CardHeader>
              <CardContent className="space-y-2">
                {isLoading ? (
                  <div className="flex justify-center py-4"><Loader2 className="w-6 h-6 animate-spin text-muted-foreground" /></div>
                ) : documentos.filter(d => d.data_vigencia).length === 0 ? (
                  <div className="text-center py-6 text-muted-foreground text-sm">
                    <CheckCircle2 className="w-8 h-8 mx-auto mb-2 opacity-50 text-primary" />
                    <p>Nenhum vencimento registrado.</p>
                    <p className="text-xs mt-1">Importe documentos com data de vigência para monitorar aqui.</p>
                  </div>
                ) : (
                  [...documentos]
                    .filter(d => d.data_vigencia)
                    .sort((a, b) => new Date(a.data_vigencia!).getTime() - new Date(b.data_vigencia!).getTime())
                    .slice(0, 6)
                    .map((doc) => {
                      const vigDate = new Date(doc.data_vigencia!);
                      const hoje = new Date();
                      const diffDays = Math.ceil((vigDate.getTime() - hoje.getTime()) / (1000 * 60 * 60 * 24));
                      const isVencido = diffDays < 0;
                      const isProximo = diffDays >= 0 && diffDays <= 60;
                      return (
                        <div key={doc.id} className="flex items-center justify-between p-2.5 rounded-lg border bg-muted/20">
                          <div className="flex items-center gap-2 min-w-0">
                            <div className={`w-2 h-2 rounded-full flex-shrink-0 ${isVencido ? "bg-destructive" : isProximo ? "bg-amber-500" : "bg-primary"}`} />
                            <div className="min-w-0">
                              <p className="font-medium text-sm truncate">{doc.tipo}</p>
                              <p className="text-xs text-muted-foreground">
                                Vigência: {format(vigDate, "dd/MM/yyyy")}
                              </p>
                            </div>
                          </div>
                          <div className="flex-shrink-0 text-right">
                            {isVencido ? (
                              <Badge variant="destructive" className="text-xs">Vencido</Badge>
                            ) : (
                              <Badge variant={isProximo ? "outline" : "secondary"} className={`text-xs ${isProximo ? "border-amber-500 text-amber-600" : ""}`}>
                                {diffDays === 0 ? "Hoje" : `${diffDays}d`}
                              </Badge>
                            )}
                          </div>
                        </div>
                      );
                    })
                )}
                {documentos.filter(d => d.data_vigencia).length > 6 && (
                  <Button variant="ghost" size="sm" className="w-full mt-1 text-xs" onClick={() => setActiveTab("alertas")}>
                    Ver todos os alertas <ArrowRight className="w-3.5 h-3.5 ml-1" />
                  </Button>
                )}
              </CardContent>
            </Card>
          </div>
        </TabsContent>

        {/* ALERTAS */}
        <TabsContent value="alertas" className="space-y-6">
          <SSTAlertasTab documentos={documentos} />
        </TabsContent>

        {/* AÇÕES */}
        <TabsContent value="acoes" className="space-y-6">
          <div className="flex items-center justify-between">
            <h2 className="text-lg font-semibold">Ações de Compliance SST</h2>
            <Badge variant="secondary" className="text-xs">
              {docAnalisados} doc{docAnalisados !== 1 ? "s" : ""} analisado{docAnalisados !== 1 ? "s" : ""}
            </Badge>
          </div>
          <SSTAcoesTab documentos={documentos} />
        </TabsContent>

        {/* eSocial */}
        <TabsContent value="esocial" className="space-y-6">
          <Card>
            <CardHeader>
              <CardTitle>Auditoria eSocial — Eventos SST</CardTitle>
              <CardDescription>Confronto entre eventos enviados (S-2210, S-2220, S-2240) e dados dos documentos legais</CardDescription>
            </CardHeader>
            <CardContent className="flex flex-col items-center justify-center py-12 text-center">
              <FileCheck className="w-12 h-12 text-muted-foreground mb-4" />
              <p className="text-muted-foreground">
                Em breve: conecte o certificado digital da empresa para auditoria automática dos eventos SST no eSocial.
              </p>
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>

      {/* Modal análise IA individual */}
      <SSTAnaliseIAModal open={!!analiseDoc} onOpenChange={(open) => !open && setAnaliseDoc(null)} documento={analiseDoc} />
      <GuiaRapidoComplianceSST open={showGuia} onOpenChange={setShowGuia} />
    </div>
  );
};

export default ComplianceSST;
