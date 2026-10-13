import { useMemo, useState } from "react";
import { 
  BarChart3, 
  TrendingUp, 
  Target, 
  Brain, 
  Info,
  LayoutDashboard,
  ShieldCheck,
  Zap,
  Filter,
  Calendar as CalendarIcon,
  Search,
  CheckCircle2,
  AlertTriangle,
  FileText,
  Activity,
  Flame,
  Battery,
  Building2
} from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from "@/components/ui/dialog";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { Calendar } from "@/components/ui/calendar";
import { format } from "date-fns";
import { ptBR } from "date-fns/locale";
import { cn } from "@/lib/utils";
import { IPSHistoricoChart } from "./IPSHistoricoChart";
import { IndicesDerivadosDashboard } from "./IndicesDerivadosDashboard";
import { RadarPsicossocial } from "./RadarPsicossocial";
import { RadaresPsicossocialSection } from "./RadaresPsicossocialSection";
import { AnaliseSegmentadaSection } from "./AnaliseSegmentadaSection";
import type { CampanhaPsicossocial } from "@/types/psicossocial";
import { calcularIPSClassificacao, getIPSLabel, getIPSColor, isEntrevistaInstrumento } from "@/types/psicossocial";
import { radarParaIPS } from "@/lib/psicossocial-direcao";
import { 
  BarChart, 
  Bar, 
  XAxis, 
  YAxis, 
  CartesianGrid, 
  Tooltip as RechartsTooltip, 
  ResponsiveContainer, 
  Cell,
  PieChart,
  Pie
} from "recharts";

interface DashboardAvancadoIPSProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  campanhas: CampanhaPsicossocial[];
}

export function DashboardAvancadoIPS({ open, onOpenChange, campanhas }: DashboardAvancadoIPSProps) {
  const [filtroCampanha, setFiltroCampanha] = useState<string>("todos");
  const [filtroInstrumento, setFiltroInstrumento] = useState<string>("todos");
  const [dataInicio, setDataInicio] = useState<Date | undefined>();
  const [dataFim, setDataFim] = useState<Date | undefined>();

  const campanhasFiltradas = useMemo(() => {
    return campanhas.filter(c => {
      let match = true;
      if (filtroCampanha !== "todos" && c.id !== filtroCampanha) match = false;
      if (filtroInstrumento !== "todos" && c.instrumento !== filtroInstrumento) match = false;
      if (dataInicio && new Date(c.data_inicio) < dataInicio) match = false;
      if (dataFim && new Date(c.data_fim || c.data_inicio) > dataFim) match = false;
      return match;
    });
  }, [campanhas, filtroCampanha, filtroInstrumento, dataInicio, dataFim]);

  const ultimaCampanha = useMemo(() => {
    if (campanhasFiltradas.length === 0) return null;
    return [...campanhasFiltradas].sort((a, b) => 
      new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
    )[0];
  }, [campanhasFiltradas]);

  const radarData = useMemo(() => {
    if (!ultimaCampanha?.radar_data) return [];
    // Régua única de saúde (alto=melhor): normaliza o radar bruto, pois SIPRO e
    // entrevistas vêm orientados a risco (alto=pior). Corrige barData, radar,
    // "pior dimensão" e os cards por dimensão de uma vez.
    return radarParaIPS(
      ultimaCampanha.radar_data as any[],
      ultimaCampanha.instrumento,
      (ultimaCampanha as any).tipo_instrumento,
    );
  }, [ultimaCampanha]);

  // Gráfico de Barras: Comparativo de Dimensões
  const barData = useMemo(() => {
    return radarData.map(d => ({
      name: d.subject,
      valor: d.value,
      color: d.value >= 80 ? "#10b981" : d.value >= 65 ? "#3b82f6" : d.value >= 50 ? "#f59e0b" : "#ef4444"
    })).sort((a, b) => b.valor - a.valor);
  }, [radarData]);

  // Gráfico de Pizza: Distribuição de Classificação (resumo campanhas filtradas)
  const pieData = useMemo(() => {
    const counts = { saudavel: 0, estavel: 0, atencao: 0, risco: 0, critico: 0 };
    campanhasFiltradas.forEach(c => {
      if (c.ips_score) {
        const score = c.instrumento === 'sipro' ? 100 - c.ips_score : c.ips_score;
        const cls = calcularIPSClassificacao(score);
        counts[cls]++;
      }
    });
    return [
      { name: 'Saudável', value: counts.saudavel, fill: '#10b981' },
      { name: 'Estável', value: counts.estavel, fill: '#3b82f6' },
      { name: 'Atenção', value: counts.atencao, fill: '#f59e0b' },
      { name: 'Risco/Crítico', value: counts.risco + counts.critico, fill: '#ef4444' },
    ].filter(d => d.value > 0);
  }, [campanhasFiltradas]);

  const totalRespostas = useMemo(() => {
    return campanhasFiltradas.reduce((acc, curr) => acc + (curr.total_respostas || 0), 0);
  }, [campanhasFiltradas]);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-[98vw] h-[98vh] overflow-hidden flex flex-col p-0 gap-0">
        <DialogHeader className="p-6 pb-2 border-b bg-background sticky top-0 z-10">
          <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-4">
            <div className="flex items-center gap-3">
              <div className="p-2 bg-purple-100 rounded-lg shrink-0">
                <LayoutDashboard className="h-6 w-6 text-purple-600" />
              </div>
              <div>
                <DialogTitle className="text-2xl font-bold">Análise Psicossocial Avançada</DialogTitle>
                <DialogDescription>
                  Dashboard inteligente com filtros multidimensionais e análise aprofundada.
                </DialogDescription>
              </div>
            </div>

            <div className="flex flex-wrap items-center gap-2">
              <div className="flex items-center gap-1.5 bg-muted/50 p-1 rounded-md border">
                <Filter className="h-3.5 w-3.5 text-muted-foreground ml-1" />
                <Select value={filtroCampanha} onValueChange={setFiltroCampanha}>
                  <SelectTrigger className="w-[180px] h-8 text-xs border-none bg-transparent focus:ring-0">
                    <SelectValue placeholder="Campanha" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="todos">Todas as Campanhas</SelectItem>
                    {campanhas
                      .filter(c => (c.total_respostas || 0) >= (isEntrevistaInstrumento(c.tipo_instrumento) ? 1 : 5))
                      .map(c => (
                        <SelectItem key={c.id} value={c.id}>{c.nome}</SelectItem>
                      ))}
                  </SelectContent>
                </Select>
                
                <Select value={filtroInstrumento} onValueChange={setFiltroInstrumento}>
                  <SelectTrigger className="w-[140px] h-8 text-xs border-none bg-transparent focus:ring-0">
                    <SelectValue placeholder="Instrumento" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="todos">Todos Instrumentos</SelectItem>
                    <SelectItem value="sipro">SIPRO</SelectItem>
                    <SelectItem value="copsoq">COPSOQ modificado</SelectItem>
                    <SelectItem value="hse">HSE</SelectItem>
                    <SelectItem value="proart">PROART</SelectItem>
                  </SelectContent>
                </Select>

                <Popover>
                  <PopoverTrigger asChild>
                    <Button variant="ghost" size="sm" className="h-8 text-xs gap-2 px-2 hover:bg-background">
                      <CalendarIcon className="h-3.5 w-3.5" />
                      {dataInicio ? format(dataInicio, "dd/MM/yy") : "Início"} - {dataFim ? format(dataFim, "dd/MM/yy") : "Fim"}
                    </Button>
                  </PopoverTrigger>
                  <PopoverContent className="w-auto p-0" align="end">
                    <div className="p-3 border-b bg-muted/20 flex items-center justify-between">
                      <span className="text-xs font-medium">Período de Análise</span>
                      <Button variant="ghost" size="sm" onClick={() => {setDataInicio(undefined); setDataFim(undefined)}} className="text-[10px] h-6 px-2">Limpar</Button>
                    </div>
                    <div className="flex flex-col sm:flex-row divide-x">
                      <Calendar mode="single" selected={dataInicio} onSelect={setDataInicio} locale={ptBR} initialFocus />
                      <Calendar mode="single" selected={dataFim} onSelect={setDataFim} locale={ptBR} />
                    </div>
                  </PopoverContent>
                </Popover>
              </div>
            </div>
          </div>
        </DialogHeader>

        <div className="flex-1 overflow-y-auto p-6 bg-muted/10 space-y-6">
          {/* Métricas Rápidas */}
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            <Card className="bg-white/50 backdrop-blur-sm border-purple-100 shadow-sm">
              <CardContent className="p-4 flex items-center gap-4">
                <div className="p-3 bg-purple-100 rounded-full"><FileText className="h-5 w-5 text-purple-600" /></div>
                <div>
                  <p className="text-xs text-muted-foreground font-medium uppercase tracking-wider">Amostragem</p>
                  <h4 className="text-2xl font-bold">{totalRespostas} <span className="text-xs font-normal text-muted-foreground">respostas</span></h4>
                </div>
              </CardContent>
            </Card>
            <Card className="bg-white/50 backdrop-blur-sm border-blue-100 shadow-sm">
              <CardContent className="p-4 flex items-center gap-4">
                <div className="p-3 bg-blue-100 rounded-full"><CheckCircle2 className="h-5 w-5 text-blue-600" /></div>
                <div>
                  <p className="text-xs text-muted-foreground font-medium uppercase tracking-wider">Campanhas</p>
                  <h4 className="text-2xl font-bold">{campanhasFiltradas.length} <span className="text-xs font-normal text-muted-foreground">analisadas</span></h4>
                </div>
              </CardContent>
            </Card>
            <Card className="bg-white/50 backdrop-blur-sm border-amber-100 shadow-sm">
              <CardContent className="p-4 flex items-center gap-4">
                <div className="p-3 bg-amber-100 rounded-full"><Zap className="h-5 w-5 text-amber-600" /></div>
                <div>
                  <p className="text-xs text-muted-foreground font-medium uppercase tracking-wider">IPS Atual</p>
                  <h4 className="text-2xl font-bold">{ultimaCampanha?.ips_score != null ? (ultimaCampanha.instrumento === 'sipro' ? 100 - ultimaCampanha.ips_score : ultimaCampanha.ips_score) : '--'}</h4>
                </div>
              </CardContent>
            </Card>
            <Card className="bg-white/50 backdrop-blur-sm border-red-100 shadow-sm">
              <CardContent className="p-4 flex items-center gap-4">
                <div className="p-3 bg-red-100 rounded-full"><AlertTriangle className="h-5 w-5 text-red-600" /></div>
                <div>
                  <p className="text-xs text-muted-foreground font-medium uppercase tracking-wider">Foco Alerta</p>
                  <h4 className="text-lg font-bold truncate max-w-[150px]">{barData.find(d => d.valor < 50)?.name || 'Nenhum'}</h4>
                </div>
              </CardContent>
            </Card>
          </div>

          <Tabs defaultValue="visao-geral" className="space-y-6">
            <TabsList className="grid w-full max-w-3xl grid-cols-6 bg-muted/50 p-1 border">
              <TabsTrigger value="visao-geral" className="gap-2 text-xs py-2"><BarChart3 className="h-3.5 w-3.5" /> Visão Geral</TabsTrigger>
              <TabsTrigger value="dimensoes" className="gap-2 text-xs py-2"><Target className="h-3.5 w-3.5" /> Dimensões</TabsTrigger>
              <TabsTrigger value="segmentos" className="gap-2 text-xs py-2"><Building2 className="h-3.5 w-3.5" /> Segmentos</TabsTrigger>
              <TabsTrigger value="burnout" className="gap-2 text-xs py-2"><Flame className="h-3.5 w-3.5" /> Burnout & Boreout</TabsTrigger>
              <TabsTrigger value="indices" className="gap-2 text-xs py-2"><Zap className="h-3.5 w-3.5" /> SIPRO</TabsTrigger>
              <TabsTrigger value="evolucao" className="gap-2 text-xs py-2"><TrendingUp className="h-3.5 w-3.5" /> Evolução</TabsTrigger>
            </TabsList>

            <TabsContent value="visao-geral" className="space-y-6 animate-in fade-in-50 duration-500">
              <div className="grid gap-6 lg:grid-cols-2">
                <Card>
                  <CardHeader className="pb-2">
                    <CardTitle className="text-lg flex items-center gap-2">
                      <Target className="h-5 w-5 text-purple-600" />
                      Radar Psicossocial
                    </CardTitle>
                    <CardDescription>Perfil psicológico organizacional consolidado</CardDescription>
                  </CardHeader>
                  <CardContent className="flex justify-center h-[350px]">
                    {radarData.length > 0 ? (
                      <RadarPsicossocial dados={radarData} />
                    ) : (
                      <div className="flex flex-col items-center justify-center text-muted-foreground italic w-full">
                        <Search className="h-8 w-8 mb-2 opacity-20" />
                        <p>Nenhum dado disponível para os filtros atuais.</p>
                      </div>
                    )}
                  </CardContent>
                </Card>

                <Card>
                  <CardHeader className="pb-2">
                    <CardTitle className="text-lg flex items-center gap-2">
                      <Activity className="h-5 w-5 text-blue-600" />
                      Distribuição de Saúde Mental
                    </CardTitle>
                    <CardDescription>Classificação do IPS nas campanhas selecionadas</CardDescription>
                  </CardHeader>
                  <CardContent className="h-[350px]">
                    <ResponsiveContainer width="100%" height="100%">
                      <PieChart>
                        <Pie
                          data={pieData}
                          cx="50%"
                          cy="50%"
                          innerRadius={60}
                          outerRadius={100}
                          paddingAngle={5}
                          dataKey="value"
                          label={({ name, percent }) => `${name} ${(percent * 100).toFixed(0)}%`}
                        />
                        <RechartsTooltip />
                      </PieChart>
                    </ResponsiveContainer>
                  </CardContent>
                </Card>
              </div>

              <div className="grid gap-6">
                <Card>
                  <CardHeader>
                    <CardTitle className="text-lg">Análise Comparativa por Dimensão</CardTitle>
                    <CardDescription>Pontuação detalhada de 0 a 100 por eixo temático</CardDescription>
                  </CardHeader>
                  <CardContent className="h-[400px]">
                    <ResponsiveContainer width="100%" height="100%">
                      <BarChart data={barData} layout="vertical" margin={{ left: 50, right: 30 }}>
                        <CartesianGrid strokeDasharray="3 3" horizontal={false} />
                        <XAxis type="number" domain={[0, 100]} hide />
                        <YAxis dataKey="name" type="category" width={180} tick={{ fontSize: 11 }} />
                        <RechartsTooltip 
                          cursor={{ fill: 'transparent' }}
                          content={({ active, payload }) => {
                            if (active && payload && payload.length) {
                              return (
                                <div className="bg-popover border p-2 rounded shadow-sm text-xs">
                                  <p className="font-bold">{payload[0].payload.name}</p>
                                  <p className="text-muted-foreground">Score: <span className="font-bold text-foreground">{payload[0].value}</span></p>
                                </div>
                              );
                            }
                            return null;
                          }}
                        />
                        <Bar dataKey="valor" radius={[0, 4, 4, 0]} barSize={20}>
                          {barData.map((entry, index) => (
                            <Cell key={`cell-${index}`} fill={entry.color} />
                          ))}
                        </Bar>
                      </BarChart>
                    </ResponsiveContainer>
                  </CardContent>
                </Card>
              </div>
            </TabsContent>

            <TabsContent value="dimensoes" className="space-y-6">
               <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
                {radarData.map((d, i) => {
                  const score = d.value;
                  const isHighRisk = score < 50; 
                  return (
                    <Card key={i} className={cn("transition-all hover:shadow-md", isHighRisk ? "border-red-100 bg-red-50/10" : "border-muted")}>
                      <CardHeader className="p-4 pb-2">
                        <div className="flex items-center justify-between gap-2">
                          <CardDescription className="text-[10px] uppercase font-bold tracking-wider truncate">{d.subject}</CardDescription>
                          {isHighRisk && <AlertTriangle className="h-3 w-3 text-red-500 shrink-0" />}
                        </div>
                      </CardHeader>
                      <CardContent className="p-4 pt-0">
                        <div className="flex items-end justify-between">
                          <span className={cn("text-2xl font-bold", score >= 80 ? "text-emerald-600" : score >= 65 ? "text-blue-600" : score >= 50 ? "text-amber-600" : "text-red-600")}>
                            {score}
                          </span>
                          <span className="text-[10px] text-muted-foreground font-medium">{score >= 80 ? 'SAUDÁVEL' : score >= 65 ? 'ESTÁVEL' : score >= 50 ? 'ATENÇÃO' : 'CRÍTICO'}</span>
                        </div>
                        <div className="mt-2 h-1.5 w-full rounded-full bg-muted overflow-hidden">
                          <div className={cn("h-full", score >= 80 ? "bg-emerald-500" : score >= 65 ? "bg-blue-500" : score >= 50 ? "bg-amber-500" : "bg-red-500")} style={{ width: `${score}%` }} />
                        </div>
                      </CardContent>
                    </Card>
                  );
                })}
              </div>
            </TabsContent>

            <TabsContent value="segmentos" className="space-y-6">
              <AnaliseSegmentadaSection campanhas={campanhasFiltradas} />
            </TabsContent>

            <TabsContent value="burnout" className="space-y-6">
              <RadaresPsicossocialSection campanhas={campanhasFiltradas} />
            </TabsContent>

            <TabsContent value="indices" className="space-y-6">
              <IndicesDerivadosDashboard campanhas={campanhasFiltradas} />
            </TabsContent>

            <TabsContent value="evolucao" className="space-y-6">
              <IPSHistoricoChart campanhas={campanhasFiltradas} />
            </TabsContent>
          </Tabs>
        </div>

        <div className="p-4 border-t bg-background flex items-center justify-between sticky bottom-0 z-10">
          <p className="text-xs text-muted-foreground hidden sm:block">
            Dashboard consolidado — Exibindo {campanhasFiltradas.length} de {campanhas.length} campanhas
          </p>
          <Button onClick={() => onOpenChange(false)}>Fechar Análise</Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}