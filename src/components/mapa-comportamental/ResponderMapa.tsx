import { useEffect, useMemo, useRef, useState } from "react";
import { ChevronLeft, ChevronRight, Loader2, Pause } from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Progress } from "@/components/ui/progress";
import { cn } from "@/lib/utils";
import {
  MAPA_ITENS,
  MAPA_TOTAL_ITENS,
  CODIGO_POR_MOTOR,
  MOTOR_POR_CODIGO,
  type MapaItem,
  type ItemAB,
  type ItemMotor,
  type MapaRespostas,
  type LadoAB,
} from "@/data/instrumentos/mapaComportamental";

interface Props {
  respostasIniciais?: MapaRespostas;
  onAutosave: (respostas: MapaRespostas) => void;
  onConcluir: (respostas: MapaRespostas, tempoTotalSegundos: number) => void;
  onPausar?: () => void;
  concluindo?: boolean;
}

// Ordem de exibição embaralhada por item (a posição das alternativas muda a
// cada aplicação — Anexo A.2, correção nº 4). O valor gravado é sempre canônico.
type OrdemAB = { leftIsFirst: boolean };
type OrdemMotor = { ordem: number[] };

function embaralhar<T>(arr: T[]): T[] {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

export function ResponderMapa({ respostasIniciais, onAutosave, onConcluir, onPausar, concluindo }: Props) {
  const [respostas, setRespostas] = useState<MapaRespostas>(respostasIniciais ?? {});
  const [idx, setIdx] = useState(0);
  const inicioRef = useRef<number>(Date.now());

  // Ordem de exibição estável durante toda a resposta.
  const ordens = useMemo(() => {
    const map: Record<number, OrdemAB | OrdemMotor> = {};
    for (const item of MAPA_ITENS) {
      if (item.tipo === "ab") map[item.id] = { leftIsFirst: Math.random() < 0.5 };
      else map[item.id] = { ordem: embaralhar([0, 1, 2]) };
    }
    return map;
  }, []);

  // Autosave com debounce (pausa/retomada — RF-004).
  const primeiraRender = useRef(true);
  useEffect(() => {
    if (primeiraRender.current) {
      primeiraRender.current = false;
      return;
    }
    const t = setTimeout(() => onAutosave(respostas), 700);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [respostas]);

  const item = MAPA_ITENS[idx];
  const respondidos = MAPA_ITENS.filter((i) => respostas[String(i.id)] != null).length;
  const todosRespondidos = respondidos === MAPA_TOTAL_ITENS;
  const atualRespondido = respostas[String(item.id)] != null;

  function setResposta(id: number, valor: number) {
    setRespostas((r) => ({ ...r, [String(id)]: valor }));
  }

  function avancar() {
    if (idx < MAPA_TOTAL_ITENS - 1) setIdx(idx + 1);
  }
  function voltar() {
    if (idx > 0) setIdx(idx - 1);
  }
  function concluir() {
    const tempo = Math.round((Date.now() - inicioRef.current) / 1000);
    onConcluir(respostas, tempo);
  }

  const isUltimo = idx === MAPA_TOTAL_ITENS - 1;

  return (
    <Card className="max-w-2xl mx-auto">
      <CardContent className="pt-6 space-y-6">
        <div className="space-y-2">
          <div className="flex items-center justify-between text-sm text-muted-foreground">
            <span>Pergunta {idx + 1} de {MAPA_TOTAL_ITENS}</span>
            <span>{respondidos} respondidas</span>
          </div>
          <Progress value={(respondidos / MAPA_TOTAL_ITENS) * 100} />
        </div>

        <div className="min-h-[220px]">
          <p className="text-lg font-medium mb-5">{item.enunciado}</p>
          {item.tipo === "ab" ? (
            <ItemABView
              item={item}
              ordem={ordens[item.id] as OrdemAB}
              valor={respostas[String(item.id)]}
              onSelecionar={(v) => setResposta(item.id, v)}
            />
          ) : (
            <ItemMotorView
              item={item}
              ordem={(ordens[item.id] as OrdemMotor).ordem}
              valor={respostas[String(item.id)]}
              onSelecionar={(v) => setResposta(item.id, v)}
            />
          )}
        </div>

        <div className="flex items-center justify-between gap-2 pt-2">
          <Button variant="ghost" onClick={voltar} disabled={idx === 0} className="gap-1">
            <ChevronLeft className="w-4 h-4" /> Voltar
          </Button>

          <div className="flex items-center gap-2">
            {onPausar && (
              <Button variant="outline" onClick={onPausar} className="gap-1">
                <Pause className="w-4 h-4" /> Pausar
              </Button>
            )}
            {isUltimo ? (
              <Button onClick={concluir} disabled={!todosRespondidos || concluindo} className="gap-1">
                {concluindo && <Loader2 className="w-4 h-4 animate-spin" />}
                Ver meu resultado
              </Button>
            ) : (
              <Button onClick={avancar} disabled={!atualRespondido} className="gap-1">
                Próxima <ChevronRight className="w-4 h-4" />
              </Button>
            )}
          </div>
        </div>

        {isUltimo && !todosRespondidos && (
          <p className="text-xs text-amber-600 text-right">
            Responda todas as {MAPA_TOTAL_ITENS} perguntas para ver o resultado.
          </p>
        )}
      </CardContent>
    </Card>
  );
}

// ── Item A/B: escala de 4 pontos entre as duas opções ────────────────────────
function ItemABView({
  item,
  ordem,
  valor,
  onSelecionar,
}: {
  item: ItemAB;
  ordem: OrdemAB;
  valor: number | undefined;
  onSelecionar: (v: number) => void;
}) {
  const optL = ordem.leftIsFirst ? item.opcoes[0] : item.opcoes[1];
  const optR = ordem.leftIsFirst ? item.opcoes[1] : item.opcoes[0];

  const valorPara = (lado: LadoAB, intensidade: number) => (lado === "A" ? -intensidade : intensidade);

  // Botões: 0=muito L, 1=pouco L, 2=pouco R, 3=muito R
  const valores = [
    valorPara(optL.lado, 2),
    valorPara(optL.lado, 1),
    valorPara(optR.lado, 1),
    valorPara(optR.lado, 2),
  ];
  const labels = ["Tem muito a ver", "Um pouco", "Um pouco", "Tem muito a ver"];

  return (
    <div className="space-y-3">
      <div className="grid grid-cols-2 gap-3">
        <OpcaoTexto texto={optL.texto} ativo={valor != null && valores.slice(0, 2).includes(valor)} />
        <OpcaoTexto texto={optR.texto} ativo={valor != null && valores.slice(2).includes(valor)} alinhar="right" />
      </div>
      <div className="grid grid-cols-4 gap-2">
        {valores.map((v, i) => (
          <button
            key={i}
            type="button"
            onClick={() => onSelecionar(v)}
            className={cn(
              "rounded-lg border py-2 text-xs font-medium transition-colors",
              valor === v
                ? "border-primary bg-primary text-primary-foreground shadow-sm"
                : "border-input hover:border-primary/60 hover:bg-accent",
            )}
          >
            {labels[i]}
          </button>
        ))}
      </div>
    </div>
  );
}

function OpcaoTexto({ texto, ativo, alinhar }: { texto: string; ativo: boolean; alinhar?: "right" }) {
  return (
    <div
      className={cn(
        "rounded-lg border p-3 text-sm transition-colors",
        alinhar === "right" ? "text-right" : "text-left",
        ativo ? "border-primary bg-primary/5" : "border-input",
      )}
    >
      {texto}
    </div>
  );
}

// ── Item Motor: escolha única entre 3 opções ─────────────────────────────────
function ItemMotorView({
  item,
  ordem,
  valor,
  onSelecionar,
}: {
  item: ItemMotor;
  ordem: number[];
  valor: number | undefined;
  onSelecionar: (v: number) => void;
}) {
  const selecionado = valor != null ? MOTOR_POR_CODIGO[valor] : null;
  return (
    <div className="space-y-2">
      {ordem.map((oi) => {
        const opt = item.opcoes[oi];
        const ativo = selecionado === opt.motor;
        return (
          <button
            key={opt.motor}
            type="button"
            onClick={() => onSelecionar(CODIGO_POR_MOTOR[opt.motor])}
            className={cn(
              "w-full rounded-lg border p-3 text-left text-sm transition-colors",
              ativo
                ? "border-primary bg-primary/10 shadow-sm"
                : "border-input hover:border-primary/60 hover:bg-accent",
            )}
          >
            {opt.texto}
          </button>
        );
      })}
    </div>
  );
}
