import { useEffect, useState } from "react";
import { ShieldCheck, CheckCircle2, AlertTriangle } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Skeleton } from "@/components/ui/skeleton";
import { useMapaComportamentalPolitica } from "@/hooks/useMapaComportamentalCampanhas";

const AVISO_PADRAO =
  "O Mapa Comportamental é uma ferramenta de autopercepção e desenvolvimento. Você vê o seu resultado primeiro; ninguém mais vê o que você marcou em cada questão. Responder é voluntário e o resultado não é usado para admissão, promoção, remuneração ou desligamento.";
const POLITICA_PADRAO =
  "Finalidade: desenvolvimento de pessoas e adaptação da gestão. O perfil não decide sozinho sobre a carreira de ninguém (revisão humana garantida). O gestor vê apenas subordinados diretos; o RH vê o resultado interpretado, nunca as respostas item a item. O colaborador pode consultar quem acessou o próprio mapa. Retenção conforme a política interna da empresa.";

export function GovernancaTab() {
  const { politica, isLoading, publicar, politicaPublicada } = useMapaComportamentalPolitica();
  const [textoPolitica, setTextoPolitica] = useState("");
  const [textoAviso, setTextoAviso] = useState("");

  useEffect(() => {
    setTextoPolitica(politica?.texto_politica ?? POLITICA_PADRAO);
    setTextoAviso(politica?.texto_aviso ?? AVISO_PADRAO);
  }, [politica]);

  if (isLoading) return <Skeleton className="h-64 max-w-2xl mx-auto" />;

  return (
    <div className="max-w-2xl mx-auto space-y-4">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <ShieldCheck className="w-5 h-5 text-emerald-600" /> Política de uso e aviso de tratamento
            {politicaPublicada ? (
              <Badge variant="secondary" className="ml-auto gap-1">
                <CheckCircle2 className="w-3 h-3" /> Publicada
              </Badge>
            ) : (
              <Badge variant="outline" className="ml-auto">Não publicada</Badge>
            )}
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          {!politicaPublicada && (
            <Alert>
              <AlertTriangle className="h-4 w-4" />
              <AlertDescription>
                Enquanto a política não estiver publicada, <strong>nenhuma campanha pode ser ativada</strong> (RF-001).
              </AlertDescription>
            </Alert>
          )}

          <div className="space-y-1">
            <label className="text-sm font-medium">Aviso de tratamento (mostrado ao colaborador antes de responder)</label>
            <Textarea rows={4} value={textoAviso} onChange={(e) => setTextoAviso(e.target.value)} />
          </div>

          <div className="space-y-1">
            <label className="text-sm font-medium">Política de uso</label>
            <Textarea rows={6} value={textoPolitica} onChange={(e) => setTextoPolitica(e.target.value)} />
          </div>

          <div className="flex items-center gap-3">
            <Button
              onClick={() => publicar.mutate({ texto_politica: textoPolitica, texto_aviso: textoAviso })}
              disabled={publicar.isPending || !textoPolitica.trim() || !textoAviso.trim()}
            >
              {politicaPublicada ? "Atualizar e republicar" : "Publicar política"}
            </Button>
            {politica?.publicada_em && (
              <span className="text-xs text-muted-foreground">
                Publicada em {new Date(politica.publicada_em).toLocaleString("pt-BR")}
                {politica.publicada_por_nome ? ` por ${politica.publicada_por_nome}` : ""}
              </span>
            )}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
