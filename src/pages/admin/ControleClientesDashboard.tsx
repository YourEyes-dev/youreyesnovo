import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  ArrowLeft, Radar, AlertTriangle, Activity, HeartPulse, Bell, TrendingUp,
  Timer, Users, Construction,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs';
import { RadarClientes } from '@/components/admin/controle-clientes/RadarClientes';
import { PainelIncidentes } from '@/components/admin/controle-clientes/PainelIncidentes';
import {
  useClientesRadar, useResumoCentral,
} from '@/components/admin/controle-clientes/useClientesRadar';

// Central de Controle de Clientes — monitoramento em tempo real dos clientes
// em produção (documento de requisitos v1.0). Dois eixos:
//   • técnico  — erros e exceções com contexto, para corrigir antes da reclamação;
//   • negócio  — uso, inatividade, health score e gatilhos de cross-sell/upsell.
//
// O eixo técnico já está de pé (captura de erros ligada). O eixo de negócio
// — uso, inatividade, health score e oportunidade — é a próxima etapa, e
// enquanto não existir, cada número dele fica em "—": nada aqui é simulado.

type Kpi = { label: string; ajuda: string; icon: typeof Radar; valor: number | null | undefined };

function EmConstrucao({ titulo, itens }: { titulo: string; itens: string[] }) {
  return (
    <Card>
      <CardContent className="p-6 space-y-3">
        <div className="flex items-center gap-2 text-sm font-medium">
          <Construction className="w-4 h-4 text-muted-foreground" />
          {titulo}
        </div>
        <p className="text-sm text-muted-foreground">
          Ainda não há dado nenhum aqui: o sistema precisa primeiro passar a registrar o que
          acontece nos clientes. Quando essa etapa entrar, esta aba passará a mostrar:
        </p>
        <ul className="text-sm text-muted-foreground list-disc pl-5 space-y-1">
          {itens.map((i) => <li key={i}>{i}</li>)}
        </ul>
      </CardContent>
    </Card>
  );
}

export default function ControleClientesDashboard() {
  const navigate = useNavigate();
  const [radarAberto, setRadarAberto] = useState(false);
  // A contagem de clientes ativos já é dado real (contrato ativo), então o
  // cartão mostra o número de verdade. "Ativos AGORA" (atividade no minuto)
  // depende da captura de eventos e entra junto com ela.
  const { data: clientes } = useClientesRadar(true);
  const { data: resumo } = useResumoCentral();

  const KPIS: Kpi[] = [
    { label: 'Erros nas últimas 24h', ajuda: 'Ocorrências capturadas nas telas dos clientes',
      icon: AlertTriangle, valor: resumo?.erros24h },
    { label: 'Incidentes abertos', ajuda: 'Erros agrupados ainda sem solução',
      icon: Bell, valor: resumo?.incidentesAbertos },
    { label: 'Clientes com erro (24h)', ajuda: 'Quantos clientes sentiram algum erro',
      icon: HeartPulse, valor: resumo?.clientesComErro },
    { label: 'Tempo médio de solução', ajuda: 'Entra com o motor de alertas',
      icon: Timer, valor: null },
    { label: 'Oportunidades abertas', ajuda: 'Entra com o eixo de uso e plano',
      icon: TrendingUp, valor: null },
  ];

  return (
    <div className="min-h-screen bg-background p-4 md:p-6">
      <div className="max-w-[1400px] mx-auto space-y-6">
        {/* Cabeçalho */}
        <div className="flex items-center gap-4">
          <Button variant="ghost" size="icon" onClick={() => navigate('/admin')}>
            <ArrowLeft className="w-5 h-5" />
          </Button>
          <div>
            <h1 className="text-2xl md:text-3xl font-bold flex items-center gap-2">
              <Radar className="w-7 h-7 text-primary" />
              Central de Controle de Clientes
            </h1>
            <p className="text-sm text-muted-foreground mt-1">
              Erros, uso e saúde dos clientes em tempo real · Exclusivo superadmin
            </p>
          </div>
        </div>

        <Alert>
          <Construction className="h-4 w-4" />
          <AlertTitle>Eixo técnico no ar; eixo de negócio em construção</AlertTitle>
          <AlertDescription>
            A captura de erros está ligada: o que quebra na tela de um cliente chega aqui em
            segundos, já sem dado pessoal (CPF, e-mail, telefone e segredos são mascarados antes
            de a informação ser gravada). Ainda faltam o acompanhamento de uso e inatividade, o
            health score e o disparo de alertas por WhatsApp e e-mail — os números dessas frentes
            continuam em “—”.
          </AlertDescription>
        </Alert>

        {/* KPIs ao vivo */}
        <div className="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-6 gap-4">
          {/* Clientes ativos: o único com número real hoje, e a porta do radar. */}
          <Card
            role="button"
            tabIndex={0}
            onClick={() => setRadarAberto(true)}
            onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); setRadarAberto(true); } }}
            className="cursor-pointer transition-colors hover:border-primary/50 hover:bg-accent/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          >
            <CardContent className="p-4 space-y-2">
              <div className="flex items-center gap-2">
                <div className="w-9 h-9 rounded-lg bg-primary/10 flex items-center justify-center shrink-0">
                  <Users className="w-4 h-4 text-primary" />
                </div>
                <p className="text-xl font-bold leading-none">{clientes ? clientes.length : '—'}</p>
              </div>
              <div>
                <p className="text-xs font-medium">Clientes ativos</p>
                <p className="text-[11px] text-muted-foreground mt-0.5">Clique para ver o radar</p>
              </div>
            </CardContent>
          </Card>

          {KPIS.map((k) => (
            <Card key={k.label}>
              <CardContent className="p-4 space-y-2">
                <div className="flex items-center gap-2">
                  <div className="w-9 h-9 rounded-lg bg-primary/10 flex items-center justify-center shrink-0">
                    <k.icon className="w-4 h-4 text-primary" />
                  </div>
                  <p className="text-xl font-bold leading-none">
                    {k.valor === null || k.valor === undefined ? '—' : k.valor}
                  </p>
                </div>
                <div>
                  <p className="text-xs font-medium">{k.label}</p>
                  <p className="text-[11px] text-muted-foreground mt-0.5">{k.ajuda}</p>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>

        {/* Eixos */}
        <Tabs defaultValue="incidentes" className="space-y-6">
          <TabsList>
            <TabsTrigger value="incidentes"><AlertTriangle className="w-4 h-4 mr-2" />Incidentes</TabsTrigger>
            <TabsTrigger value="saude"><Activity className="w-4 h-4 mr-2" />Saúde dos clientes</TabsTrigger>
            <TabsTrigger value="alertas"><Bell className="w-4 h-4 mr-2" />Fila de alertas</TabsTrigger>
          </TabsList>

          <TabsContent value="incidentes">
            <PainelIncidentes />
          </TabsContent>

          <TabsContent value="saude">
            <EmConstrucao
              titulo="Eixo de negócio — uso, inatividade e oportunidade"
              itens={[
                'Lista de clientes por health score (verde, amarelo, vermelho) com a tendência',
                'Uso por módulo e tempo sem uso (ex.: “sem usar o Ponto há 7 dias”)',
                'Gatilhos de cross-sell e upsell a partir do uso real contra o plano contratado',
              ]}
            />
          </TabsContent>

          <TabsContent value="alertas">
            <EmConstrucao
              titulo="Fila de alertas"
              itens={[
                'Alertas com situação (novo, reconhecido, em análise, resolvido) e responsável',
                'Prazo de atendimento por gravidade e escalonamento quando o prazo estoura',
                'Regras configuráveis aqui mesmo, sem depender de publicação nova',
              ]}
            />
          </TabsContent>
        </Tabs>
      </div>

      <RadarClientes aberto={radarAberto} aoFechar={() => setRadarAberto(false)} />
    </div>
  );
}
