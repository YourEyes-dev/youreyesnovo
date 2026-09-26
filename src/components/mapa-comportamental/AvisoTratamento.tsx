import { useState } from "react";
import { ShieldCheck, Eye, Ban, RefreshCw } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";

/** Versão do aviso de tratamento apresentado (RF-003). Muda quando o texto muda. */
export const AVISO_TRATAMENTO_VERSAO = "v1";

interface Props {
  onAceitar: () => void;
  onCancelar?: () => void;
}

/**
 * Aviso de tratamento de dados exibido antes de o colaborador responder (RF-003).
 * Sem o aceite, o questionário não abre. Linguagem clara para leitor não-técnico.
 */
export function AvisoTratamento({ onAceitar, onCancelar }: Props) {
  const [lido, setLido] = useState(false);

  return (
    <Card className="max-w-2xl mx-auto">
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <ShieldCheck className="w-5 h-5 text-emerald-600" />
          Antes de começar
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4 text-sm leading-relaxed">
        <p>
          O Mapa Comportamental é uma ferramenta de <strong>autopercepção e desenvolvimento</strong>.
          Ele descreve o seu jeito de trabalhar em termos de <em>tendência e preferência</em> — não
          existe perfil melhor nem pior, e ele não mede a sua competência.
        </p>

        <ul className="space-y-2">
          <li className="flex gap-2">
            <Eye className="w-4 h-4 mt-0.5 text-indigo-600 shrink-0" />
            <span><strong>Você vê o seu resultado primeiro.</strong> Ninguém, além de você, verá o que
            você marcou em cada questão — o que fica visível para a empresa é o resultado interpretado.</span>
          </li>
          <li className="flex gap-2">
            <Ban className="w-4 h-4 mt-0.5 text-rose-600 shrink-0" />
            <span>O resultado <strong>não</strong> é usado para admissão, promoção, remuneração ou
            desligamento, e responder é <strong>voluntário</strong> — a recusa não gera consequência.</span>
          </li>
          <li className="flex gap-2">
            <RefreshCw className="w-4 h-4 mt-0.5 text-sky-600 shrink-0" />
            <span>São 28 perguntas rápidas (cerca de 7 minutos). Você pode <strong>pausar e voltar</strong>
            depois. O mapa pode mudar com o tempo — dá para refazer.</span>
          </li>
        </ul>

        <p className="text-muted-foreground">
          Escolha o lado que mais parece com você no trabalho de hoje — não como você gostaria de ser.
          Não existe resposta certa.
        </p>

        <label className="flex items-center gap-2 pt-2 cursor-pointer select-none">
          <input
            type="checkbox"
            className="h-4 w-4 rounded border-input"
            checked={lido}
            onChange={(e) => setLido(e.target.checked)}
          />
          <span>Li e entendi como os meus dados serão tratados.</span>
        </label>

        <div className="flex gap-3 pt-2">
          <Button onClick={onAceitar} disabled={!lido}>
            Começar
          </Button>
          {onCancelar && (
            <Button variant="ghost" onClick={onCancelar}>
              Agora não
            </Button>
          )}
        </div>
      </CardContent>
    </Card>
  );
}
