import { BookOpen, Compass } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { useMapaPorCpf } from "@/hooks/useMapaComportamentalTime";
import { ARQUETIPO_LABEL, type Arquetipo } from "@/data/instrumentos/mapaComportamental";
import { GUIA_PERFIS } from "@/data/mapaComportamentalGuia";

// Blocos do Guia mais úteis no momento de dar um feedback.
const BLOCOS_FEEDBACK = ["feedback", "motiva", "pressao", "precisa"];

interface Props {
  cpf: string | null | undefined;
}

/**
 * Painel de orientação do Guia do Líder na tela de Feedback (Fatia 6). Aparece
 * apenas quando o colaborador selecionado já concluiu o Mapa Comportamental e o
 * usuário tem permissão de leitura. Renderiza nada caso contrário — a tela de
 * Feedback funciona igual sem o mapa.
 */
export function GuiaFeedbackPanel({ cpf }: Props) {
  const { data: mapa } = useMapaPorCpf(cpf);

  if (!mapa) return null;

  const primario = (mapa.arquetipo?.split("-")[0] ?? null) as Arquetipo | null;
  const guia = primario && GUIA_PERFIS[primario] ? GUIA_PERFIS[primario] : null;
  if (!guia) return null;

  const arqLabel = ARQUETIPO_LABEL[guia.arquetipo] ?? guia.arquetipo;

  return (
    <Card className="border-indigo-200 bg-indigo-50/40 dark:bg-indigo-950/20">
      <CardHeader className="pb-3">
        <CardTitle className="flex flex-wrap items-center gap-2 text-sm">
          <Compass className="w-4 h-4 text-indigo-600" />
          Guia do Líder — como dar feedback a um
          <Badge variant="secondary">{arqLabel}</Badge>
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        {guia.blocos
          .filter((b) => BLOCOS_FEEDBACK.includes(b.chave))
          .map((b) => (
            <div key={b.chave} className="border-l-2 border-indigo-300 pl-3">
              <p className="text-sm font-semibold flex items-center gap-1.5">
                <BookOpen className="w-3.5 h-3.5 text-muted-foreground" /> {b.titulo}
              </p>
              <p className="text-sm text-muted-foreground mt-0.5">{b.texto}</p>
            </div>
          ))}
        <p className="text-xs text-muted-foreground">
          Orientação do MODUS™ para adaptar a conversa — não é medida de competência e não muda o
          conteúdo do feedback. Baseada no MODUS que essa pessoa respondeu.
        </p>
      </CardContent>
    </Card>
  );
}
