import { useState } from "react";
import { motion } from "framer-motion";
import { 
  BookOpen, 
  Users, 
  Video, 
  FileText, 
  Presentation, 
  ExternalLink,
  Star,
  Clock,
  Search,
  MapPin,
  ShieldCheck,
  Loader2,
  UserX
} from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

// ── Tipos ──────────────────────────────────────────────────────────────────

interface ConteudoEducativo {
  id: string;
  titulo: string;
  tipo: 'texto' | 'video' | 'guia' | 'apresentacao' | 'trilha';
  categoria: string;
  duracao?: string;
  descricao: string;
  tags: string[];
}

// Segmentos relevantes para Ergonomia/SST
const SEGMENTOS_ERGONOMIA = [
  'Ergonomia', 'Fisioterapia', 'SST', 'Saúde Ocupacional', 'Saúde Mental',
  'AET', 'AEP', 'PCMSO', 'LER/DORT', 'Ginástica Laboral', 'Biomecânica',
  'NR-17', 'Medicina do Trabalho', 'Psicologia Organizacional', 'Psicossocial',
];

const CONSELHOS_RELEVANTES = ['CREFITO', 'CRM', 'CRP', 'CFP', 'CREA'];

// ── Conteúdo educativo (estático por ora) ─────────────────────────────────

const CONTEUDOS: ConteudoEducativo[] = [
  {
    id: '1',
    titulo: 'Introdução à NR-17: Ergonomia no Trabalho',
    tipo: 'video',
    categoria: 'NR-17',
    duracao: '15 min',
    descricao: 'Entenda os conceitos fundamentais da norma regulamentadora de ergonomia.',
    tags: ['ergonomia', 'nr-17', 'introdução'],
  },
  {
    id: '2',
    titulo: 'Guia Prático: Postura no Trabalho Remoto',
    tipo: 'guia',
    categoria: 'Mobiliário',
    descricao: 'Dicas práticas para configurar seu espaço de trabalho em casa.',
    tags: ['home office', 'postura', 'mobiliário'],
  },
  {
    id: '3',
    titulo: 'Prevenção de LER/DORT',
    tipo: 'trilha',
    categoria: 'Saúde',
    duracao: '2h',
    descricao: 'Trilha completa sobre prevenção de lesões por esforço repetitivo.',
    tags: ['ler', 'dort', 'prevenção'],
  },
  {
    id: '4',
    titulo: 'Análise Ergonômica: Como Fazer',
    tipo: 'apresentacao',
    categoria: 'AET',
    duracao: '45 min',
    descricao: 'Passo a passo para realizar uma análise ergonômica do trabalho.',
    tags: ['aet', 'análise', 'metodologia'],
  },
  {
    id: '5',
    titulo: 'Riscos Psicossociais no Ambiente de Trabalho',
    tipo: 'texto',
    categoria: 'Saúde Mental',
    descricao: 'Artigo sobre identificação e mitigação de riscos psicossociais.',
    tags: ['psicossocial', 'saúde mental', 'burnout'],
  },
];

const TIPO_ICONS = {
  texto: FileText,
  video: Video,
  guia: BookOpen,
  apresentacao: Presentation,
  trilha: BookOpen,
};

// ── Hook: busca profissionais reais do Marketplace ────────────────────────

function useProfissionaisSST(search: string) {
  return useQuery({
    queryKey: ['hub-profissionais-sst', search],
    queryFn: async () => {
      let query = supabase
        .from('marketplace_profissionais')
        .select('id, nome_completo, conselho, especialidades, areas_atuacao, status, nota_media, total_avaliacoes, foto_url, bio, cidade, estado, selo_verificado, modalidades_atendimento')
        .eq('status', 'ativo')
        .in('conselho', CONSELHOS_RELEVANTES)
        .order('nota_media', { ascending: false })
        .limit(20);

      if (search.trim()) {
        query = query.or(
          `nome_completo.ilike.%${search}%,bio.ilike.%${search}%`
        );
      }

      const { data, error } = await query;
      if (error) throw error;

      // Filtro adicional: ao menos uma especialidade/área alinhada com ergonomia/SST
      return (data || []).filter((p) => {
        const esp = (p.especialidades || []).join(' ').toLowerCase();
        const areas = (p.areas_atuacao || []).join(' ').toLowerCase();
        const keywords = SEGMENTOS_ERGONOMIA.map((s) => s.toLowerCase());
        return keywords.some((k) => esp.includes(k) || areas.includes(k));
      });
    },
  });
}

// ── Componente ─────────────────────────────────────────────────────────────

export function HubServicos() {
  const [searchConteudo, setSearchConteudo] = useState("");
  const [searchProfissional, setSearchProfissional] = useState("");

  const { data: profissionais = [], isLoading: loadingProf } = useProfissionaisSST(searchProfissional);

  const conteudosFiltrados = CONTEUDOS.filter((c) =>
    c.titulo.toLowerCase().includes(searchConteudo.toLowerCase()) ||
    c.categoria.toLowerCase().includes(searchConteudo.toLowerCase()) ||
    c.tags.some((t) => t.toLowerCase().includes(searchConteudo.toLowerCase()))
  );

  return (
    <Card className="border-border/50">
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <BookOpen className="h-5 w-5 text-primary" />
          Hub de Serviços
        </CardTitle>
      </CardHeader>
      <CardContent>
        <Tabs defaultValue="conhecimento" className="space-y-4">
          <TabsList className="grid w-full grid-cols-2">
            <TabsTrigger value="conhecimento" className="gap-2">
              <BookOpen className="h-4 w-4" />
              Conhecimento
            </TabsTrigger>
            <TabsTrigger value="profissionais" className="gap-2">
              <Users className="h-4 w-4" />
              Profissionais
            </TabsTrigger>
          </TabsList>

          {/* ── Conhecimento ── */}
          <TabsContent value="conhecimento" className="space-y-4">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <Input
                placeholder="Buscar conteúdos..."
                value={searchConteudo}
                onChange={(e) => setSearchConteudo(e.target.value)}
                className="pl-10"
              />
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              {conteudosFiltrados.map((conteudo, index) => {
                const Icon = TIPO_ICONS[conteudo.tipo];
                return (
                  <motion.div
                    key={conteudo.id}
                    initial={{ opacity: 0, y: 10 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ delay: index * 0.05 }}
                  >
                    <Card className="border-border/50 hover:shadow-md transition-all cursor-pointer group">
                      <CardContent className="p-4">
                        <div className="flex items-start gap-3">
                          <div className="p-2 rounded-lg bg-primary/10">
                            <Icon className="h-4 w-4 text-primary" />
                          </div>
                          <div className="flex-1 min-w-0">
                            <h4 className="font-medium text-sm text-foreground line-clamp-1 group-hover:text-primary transition-colors">
                              {conteudo.titulo}
                            </h4>
                            <p className="text-xs text-muted-foreground mt-1 line-clamp-2">
                              {conteudo.descricao}
                            </p>
                            <div className="flex items-center gap-2 mt-2">
                              <Badge variant="outline" className="text-xs">
                                {conteudo.categoria}
                              </Badge>
                              {conteudo.duracao && (
                                <span className="flex items-center gap-1 text-xs text-muted-foreground">
                                  <Clock className="h-3 w-3" />
                                  {conteudo.duracao}
                                </span>
                              )}
                            </div>
                          </div>
                          <ExternalLink className="h-4 w-4 text-muted-foreground opacity-0 group-hover:opacity-100 transition-opacity" />
                        </div>
                      </CardContent>
                    </Card>
                  </motion.div>
                );
              })}
            </div>

            {conteudosFiltrados.length === 0 && (
              <div className="text-center py-8 text-muted-foreground">
                <BookOpen className="h-12 w-12 mx-auto mb-2 opacity-50" />
                <p>Nenhum conteúdo encontrado</p>
              </div>
            )}
          </TabsContent>

          {/* ── Profissionais (MarketYE – dados reais) ── */}
          <TabsContent value="profissionais" className="space-y-4">
            <div className="flex items-center gap-2">
              <div className="relative flex-1">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <Input
                  placeholder="Buscar por nome ou especialidade..."
                  value={searchProfissional}
                  onChange={(e) => setSearchProfissional(e.target.value)}
                  className="pl-10"
                />
              </div>
            </div>

            <p className="text-xs text-muted-foreground">
              Especialistas ativos no MarketYE com atuação em Fisioterapia, Ergonomia, SST, Saúde Ocupacional e Saúde Mental.
            </p>

            {loadingProf ? (
              <div className="flex items-center justify-center py-12">
                <Loader2 className="h-6 w-6 animate-spin text-primary mr-2" />
                <span className="text-sm text-muted-foreground">Buscando profissionais...</span>
              </div>
            ) : profissionais.length === 0 ? (
              <div className="text-center py-12 text-muted-foreground">
                <UserX className="h-12 w-12 mx-auto mb-3 opacity-40" />
                <p className="font-medium">Nenhum profissional cadastrado</p>
                <p className="text-xs mt-1">Especialistas cadastrados no <strong>MarketYE</strong> aparecem aqui assim que verificados.</p>
              </div>
            ) : (
              <div className="space-y-3">
                {profissionais.map((prof, index) => (
                  <motion.div
                    key={prof.id}
                    initial={{ opacity: 0, y: 10 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ delay: index * 0.05 }}
                  >
                    <Card className="border-border/50 hover:shadow-md transition-all">
                      <CardContent className="p-4">
                        <div className="flex items-start gap-4">
                          <Avatar className="w-12 h-12 shrink-0">
                            {prof.foto_url && !prof.foto_url.startsWith('/avatars') && (
                              <AvatarImage src={prof.foto_url} alt={prof.nome_completo} />
                            )}
                            <AvatarFallback className="bg-primary/10 text-primary font-semibold text-sm">
                              {prof.nome_completo.split(' ').slice(0, 2).map((n: string) => n[0]).join('')}
                            </AvatarFallback>
                          </Avatar>

                          <div className="flex-1 min-w-0">
                            <div className="flex items-center gap-2 flex-wrap">
                              <h4 className="font-semibold text-sm text-foreground">
                                {prof.nome_completo}
                              </h4>
                              {prof.selo_verificado && (
                                <ShieldCheck className="h-4 w-4 text-primary shrink-0" aria-label="Verificado" />
                              )}
                              {prof.conselho && (
                                <Badge variant="outline" className="text-xs">
                                  {prof.conselho}
                                </Badge>
                              )}
                            </div>

                            {prof.bio && (
                              <p className="text-xs text-muted-foreground mt-1 line-clamp-2">
                                {prof.bio}
                              </p>
                            )}

                            {/* Especialidades */}
                            {prof.especialidades && prof.especialidades.length > 0 && (
                              <div className="flex flex-wrap gap-1 mt-2">
                                {(prof.especialidades as string[]).slice(0, 4).map((esp: string, i: number) => (
                                  <Badge key={i} variant="secondary" className="text-xs">
                                    {esp}
                                  </Badge>
                                ))}
                                {prof.especialidades.length > 4 && (
                                  <Badge variant="secondary" className="text-xs">
                                    +{prof.especialidades.length - 4}
                                  </Badge>
                                )}
                              </div>
                            )}

                            <div className="flex items-center gap-4 mt-2">
                              {prof.nota_media && (
                                <span className="flex items-center gap-1 text-xs">
                                  <Star className="h-3 w-3 text-warning fill-warning" />
                                  <span className="font-medium">{Number(prof.nota_media).toFixed(1)}</span>
                                  {prof.total_avaliacoes > 0 && (
                                    <span className="text-muted-foreground">({prof.total_avaliacoes})</span>
                                  )}
                                </span>
                              )}
                              {(prof.cidade || prof.estado) && (
                                <span className="flex items-center gap-1 text-xs text-muted-foreground">
                                  <MapPin className="h-3 w-3" />
                                  {[prof.cidade, prof.estado].filter(Boolean).join(', ')}
                                </span>
                              )}
                            </div>
                          </div>

                          <Button
                            size="sm"
                            variant="outline"
                            className="shrink-0"
                            onClick={() => window.location.href = '/marketplace'}
                          >
                            Ver perfil
                          </Button>
                        </div>
                      </CardContent>
                    </Card>
                  </motion.div>
                ))}
              </div>
            )}
          </TabsContent>
        </Tabs>
      </CardContent>
    </Card>
  );
}
