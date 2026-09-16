import { useEffect, useMemo, useState } from "react";
import { Gavel, SlidersHorizontal, BarChart3, Megaphone, FileBarChart, Sparkles, Loader2, RotateCcw, Check } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Textarea } from "@/components/ui/textarea";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { format } from "date-fns";
import { ptBR } from "date-fns/locale";
import { toast } from "sonner";
import { useMarketYEModeracao, useMarketYECategorias, NIVEL_LABEL } from "@/hooks/useMarketYE";
import { marketyeIA } from "@/hooks/useMarketYEPortal";

// ---------------------------------------------------------------------
// Pedidos de revisão (contestações): quem decide é uma pessoa.
// ---------------------------------------------------------------------
interface Contestacao { id: string; especialista: string; especialista_status: string; decisao_tipo: string; motivo: string; status: string; resposta: string | null; created_at: string; trilha: { evento: string; em: string; por: string }[] }

const tipoLabel: Record<string, string> = {
  rejeicao_cadastro: "Cadastro não aprovado", suspensao: "Perfil suspenso", remocao_anuncio: "Serviço retirado da vitrine", ajuste_nivel: "Mudança de nível",
  reflexo_visibilidade: "Ocorrência registrada", avaliacao: "Avaliação recebida", outro: "Outro",
};
const statusRevisao: Record<string, string> = { aberta: "Aguardando análise", em_analise: "Em análise", deferida: "Pedido aceito", indeferida: "Decisão mantida" };

export function ContestacoesPanel({ ativo }: { ativo: boolean }) {
  const { contestacoes, decidirContestacao } = useMarketYEModeracao(ativo);
  const [resposta, setResposta] = useState<Record<string, string>>({});
  const lista = (contestacoes.data ?? []) as Contestacao[];
  return (
    <div className="space-y-4">
      <div className="p-3 bg-indigo-50 border border-indigo-200 rounded-xl text-xs text-indigo-800 flex gap-2"><Gavel className="h-4 w-4 mt-0.5 shrink-0" /><p>Quando um especialista discorda de uma decisão (cadastro não aprovado, suspensão, ocorrência, avaliação), ele pede revisão aqui. Uma pessoa da equipe lê, responde e decide. A resposta fica guardada como registro.</p></div>
      {lista.length === 0 ? <p className="text-sm text-muted-foreground text-center py-6">Nenhum pedido de revisão no momento.</p> : lista.map((c) => (
        <div key={c.id} className="rounded-2xl border border-border p-4 space-y-2">
          <div className="flex items-center justify-between gap-2 flex-wrap">
            <div><p className="font-medium">{c.especialista}</p><p className="text-xs text-muted-foreground">{tipoLabel[c.decisao_tipo] ?? c.decisao_tipo} · pedido feito em {format(new Date(c.created_at), "dd/MM/yyyy HH:mm", { locale: ptBR })}</p></div>
            <Badge variant="secondary">{statusRevisao[c.status] ?? c.status}</Badge>
          </div>
          <p className="text-sm">{c.motivo}</p>
          {c.resposta && <p className="text-sm text-muted-foreground border-l-2 pl-2">Resposta da equipe: {c.resposta}</p>}
          {(c.status === "aberta" || c.status === "em_analise") && (
            <div className="space-y-2">
              <Textarea rows={2} placeholder="Escreva a resposta para o especialista (obrigatória)" value={resposta[c.id] ?? ""} onChange={(e) => setResposta((r) => ({ ...r, [c.id]: e.target.value }))} />
              <div className="flex gap-2 justify-end flex-wrap">
                {c.status === "aberta" && <Button size="sm" variant="ghost" onClick={() => decidirContestacao.mutate({ id: c.id, resultado: "em_analise", resposta: resposta[c.id] ?? "" })}>Marcar "em análise"</Button>}
                <Button size="sm" variant="outline" disabled={(resposta[c.id] ?? "").trim().length < 10} onClick={() => decidirContestacao.mutate({ id: c.id, resultado: "indeferida", resposta: resposta[c.id] })}>Manter a decisão</Button>
                <Button size="sm" className="bg-emerald-600 hover:bg-emerald-700 text-white" disabled={(resposta[c.id] ?? "").trim().length < 10} onClick={() => decidirContestacao.mutate({ id: c.id, resultado: "deferida", resposta: resposta[c.id] })}>Aceitar o pedido</Button>
              </div>
            </div>
          )}
          <details className="text-[11px] text-muted-foreground"><summary>Histórico ({c.trilha?.length ?? 0})</summary><ul>{(c.trilha ?? []).map((t, i) => <li key={i}>{t.evento} · {t.por} · {format(new Date(t.em), "dd/MM HH:mm")}</li>)}</ul></details>
        </div>
      ))}
    </div>
  );
}

// ---------------------------------------------------------------------
// Ajustes do MarketYE: controles simples por cima da parametrização
// versionada (cada "Salvar" grava uma versão nova em marketplace_config).
// ---------------------------------------------------------------------
type Cfg = Record<string, unknown>;
const PESOS_PADRAO: Record<string, number> = { fit: 25, reputacao: 20, saude: 20, proximidade: 15, exploracao: 10, preco: 5, destaque: 5 };
const PESOS_INFO: { key: string; label: string; ajuda: string }[] = [
  { key: "fit", label: "Encaixe com o que a empresa precisa", ajuda: "Quanto vale atender exatamente a obrigação ou a área que a empresa está buscando." },
  { key: "reputacao", label: "Avaliações e nível", ajuda: "Quem é bem avaliado e já subiu de nível aparece antes." },
  { key: "saude", label: "Atendimento recente", ajuda: "Responde rápido e não cancela nos últimos 90 dias." },
  { key: "proximidade", label: "Perto da empresa (ou atende remoto)", ajuda: "Distância até a empresa; quem atende remoto conta como perto." },
  { key: "exploracao", label: "Chance para quem está começando", ajuda: "Empurrão para especialistas novos conseguirem as primeiras avaliações." },
  { key: "preco", label: "Preço e promoções", ajuda: "Preço informado e promoções ativas. Peso pequeno de propósito." },
  { key: "destaque", label: "Destaque pago", ajuda: "Sempre rotulado como Patrocinado e nunca acima de quem está abaixo da nota mínima." },
];

function Secao({ titulo, descricao, children, onSalvar, salvando, alterado, onPadrao }: { titulo: string; descricao: string; children: React.ReactNode; onSalvar: () => void; salvando: boolean; alterado: boolean; onPadrao?: () => void }) {
  return (
    <div className="rounded-2xl border border-border p-4 space-y-3">
      <div><h4 className="font-semibold">{titulo}</h4><p className="text-xs text-muted-foreground">{descricao}</p></div>
      {children}
      <div className="flex justify-end gap-2">
        {onPadrao && <Button size="sm" variant="ghost" onClick={onPadrao}><RotateCcw className="h-3.5 w-3.5 mr-1" />Voltar ao padrão</Button>}
        <Button size="sm" disabled={!alterado || salvando} onClick={onSalvar}><Check className="h-3.5 w-3.5 mr-1" />Salvar</Button>
      </div>
    </div>
  );
}

function Campo({ label, children, ajuda }: { label: string; children: React.ReactNode; ajuda?: string }) {
  return <div className="space-y-1"><Label className="text-sm">{label}</Label>{children}{ajuda && <p className="text-[11px] text-muted-foreground">{ajuda}</p>}</div>;
}

export function ParametrosPanel({ ativo }: { ativo: boolean }) {
  const { config, salvarConfig } = useMarketYEModeracao(ativo);
  const cfg = useMemo(() => Object.fromEntries((config.data ?? []).map((c) => [c.chave, c.valor as Cfg])), [config.data]);

  // --- pesos da vitrine
  const [pesos, setPesos] = useState<Record<string, number>>(PESOS_PADRAO);
  const [objetivo, setObjetivo] = useState("");
  const [explicacaoIA, setExplicacaoIA] = useState("");
  const [gerando, setGerando] = useState(false);
  useEffect(() => { const p = cfg.relevancia_pesos as Record<string, number> | undefined; if (p) setPesos(Object.fromEntries(Object.entries(p).map(([k, v]) => [k, Math.round(Number(v) * 100)]))); }, [cfg.relevancia_pesos]);
  const total = Object.values(pesos).reduce((a, b) => a + b, 0);
  const pesosSalvos = cfg.relevancia_pesos ? JSON.stringify(Object.fromEntries(Object.entries(cfg.relevancia_pesos as Record<string, number>).map(([k, v]) => [k, Math.round(Number(v) * 100)]))) : "";
  const salvarPesos = () => {
    if (total <= 0) return;
    const normal = Object.fromEntries(Object.entries(pesos).map(([k, v]) => [k, +(v / total).toFixed(4)]));
    salvarConfig.mutate({ chave: "relevancia_pesos", valor: normal, descricao: "Pesos da ordenação da vitrine (ajustados pela tela de Ajustes)" });
  };
  const sugerirIA = async () => {
    if (!objetivo.trim()) return toast.error("Diga em uma frase o que você quer priorizar");
    setGerando(true);
    try {
      const r = await marketyeIA<{ pesos: Record<string, number>; explicacao: string }>("sugerir_parametros", { objetivo, pesos_atuais: pesos });
      setPesos(Object.fromEntries(PESOS_INFO.map((p) => [p.key, Math.max(0, Math.round(Number(r.pesos[p.key] ?? 0)))])));
      setExplicacaoIA(r.explicacao);
    } catch (e) { toast.error(e instanceof Error ? e.message : "A IA não respondeu"); } finally { setGerando(false); }
  };

  // --- demais grupos: estado local por chave, salvo separadamente
  const [piso, setPiso] = useState({ nota: "3.5", minimo_avaliacoes: "3" });
  const [novato, setNovato] = useState({ dias: "30", ate_avaliacoes: "3" });
  const [saude, setSaude] = useState({ janela_dias: "90", verde: "75", amarelo: "50" });
  const [demanda, setDemanda] = useState({ piso_celula: "5", janela_dias: "30" });
  const [mascarar, setMascarar] = useState(true);
  const [janelaAval, setJanelaAval] = useState("14");
  const [destaque, setDestaque] = useState({ teto_slots_por_categoria: "2", exige_acima_do_piso: true });
  const [termos, setTermos] = useState({ termos_especialista: "", privacidade_nao_usuario: "", codigo_etica: "", termos_cliente: "" });
  const [niveis, setNiveis] = useState<{ amortecedor_dias: string; requisitos: Record<string, Record<string, string>> }>({ amortecedor_dias: "14", requisitos: {} });
  const [localizacao, setLocalizacao] = useState({ pais: "BR", moeda: "BRL", idioma: "pt-BR" });
  useEffect(() => {
    const g = (k: string) => (cfg[k] ?? {}) as Record<string, unknown>;
    if (cfg.piso_nota) setPiso({ nota: String(g("piso_nota").nota ?? "3.5"), minimo_avaliacoes: String(g("piso_nota").minimo_avaliacoes ?? "3") });
    if (cfg.protecao_novato) setNovato({ dias: String(g("protecao_novato").dias ?? "30"), ate_avaliacoes: String(g("protecao_novato").ate_avaliacoes ?? "3") });
    if (cfg.saude_recente) setSaude({ janela_dias: String(g("saude_recente").janela_dias ?? "90"), verde: String(g("saude_recente").verde ?? "75"), amarelo: String(g("saude_recente").amarelo ?? "50") });
    if (cfg.demanda_latente) setDemanda({ piso_celula: String(g("demanda_latente").piso_celula ?? "5"), janela_dias: String(g("demanda_latente").janela_dias ?? "30") });
    if (cfg.mascaramento_contato) setMascarar((g("mascaramento_contato").ate ?? "contato_qualificado") !== "nunca");
    if (cfg.janela_avaliacao_dias) setJanelaAval(String(g("janela_avaliacao_dias").dias ?? "14"));
    if (cfg.destaque) setDestaque({ teto_slots_por_categoria: String(g("destaque").teto_slots_por_categoria ?? "2"), exige_acima_do_piso: g("destaque").exige_acima_do_piso !== false });
    if (cfg.termos_versoes) { const t = g("termos_versoes"); setTermos({ termos_especialista: String(t.termos_especialista ?? ""), privacidade_nao_usuario: String(t.privacidade_nao_usuario ?? ""), codigo_etica: String(t.codigo_etica ?? ""), termos_cliente: String(t.termos_cliente ?? "") }); }
    if (cfg.localizacao) { const l = g("localizacao"); setLocalizacao({ pais: String(l.pais ?? "BR"), moeda: String(l.moeda ?? "BRL"), idioma: String(l.idioma ?? "pt-BR") }); }
    if (cfg.niveis) {
      const n = g("niveis"); const req = (n.requisitos ?? {}) as Record<string, Record<string, unknown>>;
      setNiveis({ amortecedor_dias: String(n.amortecedor_dias ?? "14"), requisitos: Object.fromEntries(Object.entries(req).map(([niv, r]) => [niv, Object.fromEntries(Object.entries(r).map(([k, v]) => [k, String(v)]))])) });
    }
  }, [cfg]);

  const salvar = (chave: string, valor: unknown, descricao: string) => salvarConfig.mutate({ chave, valor, descricao });
  const num = (v: string, f: number) => { const n = Number(String(v).replace(",", ".")); return Number.isFinite(n) ? n : f; };
  const reqLabel: Record<string, string> = { servicos: "Serviços combinados", clientes_unicos: "Empresas diferentes atendidas", media: "Nota média mínima", taxa_resposta: "Taxa de resposta (0 a 1)", ocorrencias: "Ocorrências permitidas" };
  const ordemNiveis = ((cfg.niveis as Cfg | undefined)?.ordem as string[] | undefined) ?? ["novo", "bronze", "prata", "ouro", "top"];

  if (config.isLoading) return <p className="text-sm text-muted-foreground">Carregando ajustes...</p>;

  return (
    <div className="space-y-4">
      <div className="p-3 bg-indigo-50 border border-indigo-200 rounded-xl text-xs text-indigo-800 flex gap-2"><SlidersHorizontal className="h-4 w-4 mt-0.5 shrink-0" /><p>Aqui você ajusta como o MarketYE funciona, sem mexer em código. Cada "Salvar" guarda uma versão nova e a anterior fica no histórico. Nada aqui bloqueia um especialista de trabalhar: os ajustes só mudam o que aparece primeiro na vitrine e as regras de convivência.</p></div>

      <Secao titulo="O que aparece primeiro na vitrine" descricao="Distribua a importância entre os critérios. O total é ajustado para 100% ao salvar." onSalvar={salvarPesos} salvando={salvarConfig.isPending} alterado={pesosSalvos !== JSON.stringify(pesos)} onPadrao={() => setPesos(PESOS_PADRAO)}>
        <div className="rounded-xl border border-violet-200 bg-violet-50 p-3 space-y-2">
          <Label className="text-violet-900 flex items-center gap-1"><Sparkles className="h-4 w-4" />Quer que a IA sugira? Diga o que você quer priorizar</Label>
          <div className="flex gap-2 flex-wrap">
            <Input value={objetivo} onChange={(e) => setObjetivo(e.target.value)} placeholder='Ex.: "quero dar mais chance para quem responde rápido e para os novos"' className="flex-1 min-w-[240px]" />
            <Button type="button" variant="outline" onClick={sugerirIA} disabled={gerando}>{gerando ? <Loader2 className="h-4 w-4 animate-spin" /> : "Sugerir com IA"}</Button>
          </div>
          {explicacaoIA && <p className="text-xs text-violet-900">{explicacaoIA}</p>}
        </div>
        <div className="grid md:grid-cols-2 gap-3">
          {PESOS_INFO.map((p) => (
            <div key={p.key} className="space-y-1">
              <div className="flex items-center justify-between"><Label className="text-sm">{p.label}</Label><span className="text-sm font-semibold tabular-nums">{Math.round((pesos[p.key] / Math.max(total, 1)) * 100)}%</span></div>
              <input type="range" min={0} max={50} value={pesos[p.key] ?? 0} onChange={(e) => setPesos((s) => ({ ...s, [p.key]: Number(e.target.value) }))} className="w-full accent-indigo-600" />
              <p className="text-[11px] text-muted-foreground">{p.ajuda}</p>
            </div>
          ))}
        </div>
      </Secao>

      <div className="grid md:grid-cols-2 gap-4">
        <Secao titulo="Nota mínima para aparecer bem" descricao="Abaixo desta nota o especialista continua na vitrine, mas mais abaixo, e não pode comprar destaque." onSalvar={() => salvar("piso_nota", { nota: num(piso.nota, 3.5), minimo_avaliacoes: num(piso.minimo_avaliacoes, 3) }, "Nota mínima (tela de Ajustes)")} salvando={salvarConfig.isPending} alterado={true}>
          <div className="grid grid-cols-2 gap-2">
            <Campo label="Nota mínima (1 a 5)"><Input type="number" step="0.1" min={1} max={5} value={piso.nota} onChange={(e) => setPiso({ ...piso, nota: e.target.value })} /></Campo>
            <Campo label="Só vale a partir de quantas avaliações"><Input type="number" min={1} value={piso.minimo_avaliacoes} onChange={(e) => setPiso({ ...piso, minimo_avaliacoes: e.target.value })} /></Campo>
          </div>
        </Secao>
        <Secao titulo="Boas-vindas a quem está começando" descricao="Quem acabou de entrar ganha um empurrão na vitrine para conseguir as primeiras avaliações." onSalvar={() => salvar("protecao_novato", { dias: num(novato.dias, 30), ate_avaliacoes: num(novato.ate_avaliacoes, 3) }, "Boas-vindas ao novato (tela de Ajustes)")} salvando={salvarConfig.isPending} alterado={true}>
          <div className="grid grid-cols-2 gap-2">
            <Campo label="Por quantos dias"><Input type="number" min={0} value={novato.dias} onChange={(e) => setNovato({ ...novato, dias: e.target.value })} /></Campo>
            <Campo label="Ou até quantas avaliações"><Input type="number" min={0} value={novato.ate_avaliacoes} onChange={(e) => setNovato({ ...novato, ate_avaliacoes: e.target.value })} /></Campo>
          </div>
        </Secao>
        <Secao titulo="Sinal do atendimento recente" descricao="O sinal verde, amarelo ou vermelho que a empresa vê no card resume os últimos dias de atendimento." onSalvar={() => salvar("saude_recente", { janela_dias: num(saude.janela_dias, 90), verde: num(saude.verde, 75), amarelo: num(saude.amarelo, 50) }, "Sinal do atendimento recente (tela de Ajustes)")} salvando={salvarConfig.isPending} alterado={true}>
          <div className="grid grid-cols-3 gap-2">
            <Campo label="Olhar os últimos (dias)"><Input type="number" min={7} value={saude.janela_dias} onChange={(e) => setSaude({ ...saude, janela_dias: e.target.value })} /></Campo>
            <Campo label="Verde a partir de"><Input type="number" min={0} max={100} value={saude.verde} onChange={(e) => setSaude({ ...saude, verde: e.target.value })} /></Campo>
            <Campo label="Amarelo a partir de"><Input type="number" min={0} max={100} value={saude.amarelo} onChange={(e) => setSaude({ ...saude, amarelo: e.target.value })} /></Campo>
          </div>
        </Secao>
        <Secao titulo="Contato entre empresa e especialista" descricao="Enquanto a empresa não liberar o contato, telefones, e-mails e links ficam ocultos nas mensagens." onSalvar={() => salvar("mascaramento_contato", { ate: mascarar ? "contato_qualificado" : "nunca" }, "Ocultar contato até a liberação (tela de Ajustes)")} salvando={salvarConfig.isPending} alterado={true}>
          <div className="flex items-center gap-3"><Switch checked={mascarar} onCheckedChange={setMascarar} /><span className="text-sm">{mascarar ? "Ocultar contato até a empresa liberar (recomendado)" : "Mostrar contato desde a primeira mensagem"}</span></div>
          <Campo label="Prazo para avaliar depois do serviço (dias)" ajuda="Vale para a empresa e para o especialista."><Input type="number" min={1} value={janelaAval} onChange={(e) => setJanelaAval(e.target.value)} onBlur={() => salvar("janela_avaliacao_dias", { dias: num(janelaAval, 14) }, "Prazo para avaliar (tela de Ajustes)")} /></Campo>
        </Secao>
        <Secao titulo="Vagas de demanda na página pública" descricao="A página pública mostra quantas empresas procuraram uma área sem encontrar. Para ninguém ser identificado, só aparece quando há um número mínimo de empresas." onSalvar={() => salvar("demanda_latente", { piso_celula: num(demanda.piso_celula, 5), janela_dias: num(demanda.janela_dias, 30) }, "Vagas de demanda (tela de Ajustes)")} salvando={salvarConfig.isPending} alterado={true}>
          <div className="grid grid-cols-2 gap-2">
            <Campo label="Mínimo de empresas para mostrar"><Input type="number" min={2} value={demanda.piso_celula} onChange={(e) => setDemanda({ ...demanda, piso_celula: e.target.value })} /></Campo>
            <Campo label="Olhar os últimos (dias)"><Input type="number" min={7} value={demanda.janela_dias} onChange={(e) => setDemanda({ ...demanda, janela_dias: e.target.value })} /></Campo>
          </div>
        </Secao>
        <Secao titulo="Destaque pago" descricao="Posição extra, sempre com o rótulo Patrocinado. A cobrança em si ainda não está ligada." onSalvar={() => salvar("destaque", { teto_slots_por_categoria: num(destaque.teto_slots_por_categoria, 2), exige_acima_do_piso: destaque.exige_acima_do_piso }, "Destaque pago (tela de Ajustes)")} salvando={salvarConfig.isPending} alterado={true}>
          <Campo label="Máximo de destaques por área ao mesmo tempo"><Input type="number" min={0} value={destaque.teto_slots_por_categoria} onChange={(e) => setDestaque({ ...destaque, teto_slots_por_categoria: e.target.value })} /></Campo>
          <div className="flex items-center gap-3"><Switch checked={destaque.exige_acima_do_piso} onCheckedChange={(v) => setDestaque({ ...destaque, exige_acima_do_piso: v })} /><span className="text-sm">Só quem está acima da nota mínima pode ter destaque</span></div>
        </Secao>
      </div>

      <Secao titulo="Níveis dos especialistas" descricao="Para subir de nível é preciso cumprir TODAS as condições da linha. Cair de nível só acontece depois de um aviso e de um prazo para recuperar, e muda apenas a posição na vitrine." onSalvar={() => salvar("niveis", { ...(cfg.niveis as Cfg ?? {}), ordem: ordemNiveis, amortecedor_dias: num(niveis.amortecedor_dias, 14), requisitos: Object.fromEntries(Object.entries(niveis.requisitos).map(([niv, r]) => [niv, Object.fromEntries(Object.entries(r).map(([k, v]) => [k, num(v, 0)]))])) }, "Níveis (tela de Ajustes)")} salvando={salvarConfig.isPending} alterado={true}>
        <Campo label="Dias de aviso antes de ajustar um nível para baixo"><Input type="number" min={0} className="max-w-[160px]" value={niveis.amortecedor_dias} onChange={(e) => setNiveis({ ...niveis, amortecedor_dias: e.target.value })} /></Campo>
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead><tr className="text-left text-muted-foreground"><th className="py-1 pr-2">Nível</th>{Object.keys(reqLabel).map((k) => <th key={k} className="py-1 pr-2">{reqLabel[k]}</th>)}</tr></thead>
            <tbody>
              {ordemNiveis.filter((n) => niveis.requisitos[n]).map((niv) => (
                <tr key={niv} className="border-t">
                  <td className="py-1 pr-2 font-medium">{NIVEL_LABEL[niv] ?? niv}</td>
                  {Object.keys(reqLabel).map((k) => <td key={k} className="py-1 pr-2"><Input className="h-8 w-24" value={niveis.requisitos[niv]?.[k] ?? ""} onChange={(e) => setNiveis((s) => ({ ...s, requisitos: { ...s.requisitos, [niv]: { ...s.requisitos[niv], [k]: e.target.value } } }))} /></td>)}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Secao>

      <div className="grid md:grid-cols-2 gap-4">
        <Secao titulo="Versões dos termos" descricao="Quando um termo muda, altere a versão aqui: cada especialista verá o pedido de aceite no portal, e o aceite fica registrado com data e versão." onSalvar={() => salvar("termos_versoes", termos, "Versões dos termos (tela de Ajustes)")} salvando={salvarConfig.isPending} alterado={true}>
          <div className="grid grid-cols-2 gap-2">
            <Campo label="Termos do especialista"><Input value={termos.termos_especialista} onChange={(e) => setTermos({ ...termos, termos_especialista: e.target.value })} /></Campo>
            <Campo label="Política de privacidade"><Input value={termos.privacidade_nao_usuario} onChange={(e) => setTermos({ ...termos, privacidade_nao_usuario: e.target.value })} /></Campo>
            <Campo label="Código de ética"><Input value={termos.codigo_etica} onChange={(e) => setTermos({ ...termos, codigo_etica: e.target.value })} /></Campo>
            <Campo label="Termos da empresa cliente"><Input value={termos.termos_cliente} onChange={(e) => setTermos({ ...termos, termos_cliente: e.target.value })} /></Campo>
          </div>
        </Secao>
        <Secao titulo="País, moeda e idioma padrão" descricao="Preparado para outros países da América do Sul. Hoje: Brasil, real e português." onSalvar={() => salvar("localizacao", localizacao, "Localização padrão (tela de Ajustes)")} salvando={salvarConfig.isPending} alterado={true}>
          <div className="grid grid-cols-3 gap-2">
            <Campo label="País"><Input value={localizacao.pais} onChange={(e) => setLocalizacao({ ...localizacao, pais: e.target.value.toUpperCase() })} /></Campo>
            <Campo label="Moeda"><Input value={localizacao.moeda} onChange={(e) => setLocalizacao({ ...localizacao, moeda: e.target.value.toUpperCase() })} /></Campo>
            <Campo label="Idioma"><Input value={localizacao.idioma} onChange={(e) => setLocalizacao({ ...localizacao, idioma: e.target.value })} /></Campo>
          </div>
        </Secao>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------
// Oferta e procura (painel de liquidez em linguagem simples)
// ---------------------------------------------------------------------
export function LiquidezPanel({ ativo }: { ativo: boolean }) {
  const { painel, transparencia } = useMarketYEModeracao(ativo);
  const p = painel.data as {
    especialistas: { ativos: number; pendentes: number; novos_30d: number; excluidos_30d: number }; anuncios_publicados: number;
    densidade: { categoria: string; uf: string | null; especialistas: number }[]; cobertura: { celulas_total: number; celulas_densas: number };
    leads: { abertos_30d: number; respondidos_30d: number; ganhos_30d: number; tempo_resposta_mediano_min: number | null };
    demanda_latente: { categoria: string; uf: string | null; empresas: number; avisar: boolean }[]; tempo_ate_primeira_venda_dias: number | null; contestacoes_abertas: number;
  } | null | undefined;
  const t = transparencia.data as Record<string, unknown> | null | undefined;
  if (!p) return <p className="text-sm text-muted-foreground">Carregando...</p>;
  const Kpi = ({ label, value, hint }: { label: string; value: string | number; hint?: string }) => (
    <div className="rounded-2xl border border-border p-4"><p className="text-xs text-muted-foreground">{label}</p><p className="text-2xl font-bold">{value}</p>{hint && <p className="text-[11px] text-muted-foreground">{hint}</p>}</div>
  );
  const taxaResp = p.leads.abertos_30d ? Math.round((p.leads.respondidos_30d / p.leads.abertos_30d) * 100) : null;
  const conv = p.leads.abertos_30d ? Math.round((p.leads.ganhos_30d / p.leads.abertos_30d) * 100) : null;
  return (
    <div className="space-y-6">
      <div className="p-3 bg-indigo-50 border border-indigo-200 rounded-xl text-xs text-indigo-800 flex gap-2"><BarChart3 className="h-4 w-4 mt-0.5 shrink-0" /><p>O MarketYE só funciona se, para cada área e estado que as empresas procuram, houver especialistas suficientes (a meta é pelo menos 3) e eles responderem rápido. Esta tela mostra onde está bom e onde falta gente.</p></div>
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <Kpi label="Especialistas na vitrine" value={p.especialistas.ativos} hint={`${p.especialistas.pendentes} aguardando aprovação · ${p.especialistas.novos_30d} novos em 30 dias`} />
        <Kpi label="Serviços publicados" value={p.anuncios_publicados} />
        <Kpi label="Áreas bem atendidas" value={`${p.cobertura.celulas_densas} de ${p.cobertura.celulas_total}`} hint="área × estado com 3 ou mais especialistas" />
        <Kpi label="Contatos de empresas (30 dias)" value={p.leads.abertos_30d} hint={`${taxaResp ?? "—"}% respondidos · ${conv ?? "—"}% viraram serviço`} />
        <Kpi label="Tempo até a 1ª resposta" value={p.leads.tempo_resposta_mediano_min != null ? `${Math.round(p.leads.tempo_resposta_mediano_min)} min` : "—"} hint="metade responde antes disso" />
        <Kpi label="Tempo até o 1º serviço" value={p.tempo_ate_primeira_venda_dias != null ? `${p.tempo_ate_primeira_venda_dias} dias` : "—"} hint="do cadastro ao primeiro serviço combinado" />
        <Kpi label="Saíram em 30 dias" value={p.especialistas.excluidos_30d} hint="perfis excluídos pelo próprio especialista" />
        <Kpi label="Pedidos de revisão abertos" value={p.contestacoes_abertas} />
      </div>
      <div className="grid md:grid-cols-2 gap-4">
        <div className="rounded-2xl border border-border p-4">
          <h4 className="font-medium mb-2">Quantos especialistas por área e estado</h4>
          {p.densidade.length === 0 ? <p className="text-xs text-muted-foreground">Ainda não há serviços publicados.</p> : (
            <table className="w-full text-xs"><tbody>{p.densidade.slice(0, 20).map((d, i) => <tr key={i} className="border-t"><td className="py-1">{d.categoria}</td><td className="py-1">{d.uf ?? "—"}</td><td className="py-1 text-right font-medium">{d.especialistas}</td></tr>)}</tbody></table>
          )}
        </div>
        <div className="rounded-2xl border border-border p-4">
          <h4 className="font-medium mb-2">O que as empresas procuraram e não encontraram (30 dias)</h4>
          {p.demanda_latente.length === 0 ? <p className="text-xs text-muted-foreground">Nenhuma busca sem resposta registrada.</p> : (
            <table className="w-full text-xs"><tbody>{p.demanda_latente.slice(0, 20).map((d, i) => <tr key={i} className="border-t"><td className="py-1">{d.categoria}</td><td className="py-1">{d.uf ?? "—"}</td><td className="py-1 text-right font-medium">{d.empresas} empresa(s){d.avisar ? " · pediram aviso" : ""}</td></tr>)}</tbody></table>
          )}
          <p className="text-[11px] text-muted-foreground mt-2">É por aqui que vale a pena convidar especialistas primeiro.</p>
        </div>
      </div>
      {t && (
        <div className="rounded-2xl border border-border p-4">
          <h4 className="font-medium mb-2 flex items-center gap-2"><FileBarChart className="h-4 w-4" />Números do ano {String(t.ano)} (relatório de transparência)</h4>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-2 text-xs">
            <p>Denúncias recebidas: <b>{String(t.denuncias_recebidas)}</b></p><p>Denúncias procedentes: <b>{String(t.denuncias_procedentes)}</b></p>
            <p>Cadastros aprovados: <b>{String(t.cadastros_aprovados)}</b></p><p>Cadastros não aprovados: <b>{String(t.cadastros_rejeitados)}</b></p>
            <p>Serviços publicados: <b>{String(t.anuncios_publicados)}</b></p><p>Destaques pagos: <b>{String(t.impulsionamentos)}</b></p>
            <p>Perfis excluídos a pedido: <b>{String(t.exclusoes_lgpd)}</b></p><p>Pedidos de revisão: <b>{(() => { const c = t.contestacoes as Record<string, number> | undefined; return c ? `${c.abertas ?? 0} abertos · ${c.deferidas ?? 0} aceitos · ${c.indeferidas ?? 0} mantidos` : "—"; })()}</b></p>
          </div>
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------
// Destaque pago (registro do período; a cobrança vem em outra onda)
// ---------------------------------------------------------------------
export function DestaquesPanel({ ativo }: { ativo: boolean }) {
  const { criarDestaque, especialistasAtivos } = useMarketYEModeracao(ativo);
  const { data: cats } = useMarketYECategorias();
  const [f, setF] = useState({ profissional_id: "", tipo: "categoria", categoria_id: "", uf: "", inicio: format(new Date(), "yyyy-MM-dd"), fim: "", valor: "" });
  return (
    <div className="space-y-4 max-w-xl">
      <div className="p-3 bg-amber-50 border border-amber-200 rounded-xl text-xs text-amber-800 flex gap-2"><Megaphone className="h-4 w-4 mt-0.5 shrink-0" /><p>Um destaque coloca o especialista numa posição extra, sempre com o rótulo "Patrocinado". Ele não passa por cima de quem está abaixo da nota mínima. Aqui você só registra o período; a cobrança ainda não está ligada.</p></div>
      <div className="grid gap-3">
        <div><Label>Especialista</Label>
          <Select value={f.profissional_id} onValueChange={(v) => setF({ ...f, profissional_id: v })}>
            <SelectTrigger><SelectValue placeholder="Escolha um especialista aprovado" /></SelectTrigger>
            <SelectContent>{(especialistasAtivos.data ?? []).map((e) => <SelectItem key={e.id} value={e.id}>{e.nome_completo}{e.cidade ? ` · ${e.cidade}/${e.estado ?? ""}` : ""}</SelectItem>)}</SelectContent>
          </Select>
        </div>
        <div><Label>Onde destacar</Label>
          <Select value={f.tipo} onValueChange={(v) => setF({ ...f, tipo: v })}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent><SelectItem value="categoria">Numa área</SelectItem><SelectItem value="regiao">Num estado</SelectItem><SelectItem value="topo">No topo geral</SelectItem></SelectContent></Select>
        </div>
        {f.tipo === "categoria" && <div><Label>Área</Label>
          <Select value={f.categoria_id} onValueChange={(v) => setF({ ...f, categoria_id: v })}><SelectTrigger><SelectValue placeholder="Escolha" /></SelectTrigger><SelectContent>{(cats?.todas ?? []).map((c) => <SelectItem key={c.id} value={c.id}>{c.pai_id ? "— " : ""}{c.nome}</SelectItem>)}</SelectContent></Select>
        </div>}
        {f.tipo === "regiao" && <div><Label>Estado (UF)</Label><Input value={f.uf} onChange={(e) => setF({ ...f, uf: e.target.value.toUpperCase() })} maxLength={2} /></div>}
        <div className="grid grid-cols-2 gap-2"><div><Label>Começa em</Label><Input type="date" value={f.inicio} onChange={(e) => setF({ ...f, inicio: e.target.value })} /></div><div><Label>Termina em</Label><Input type="date" value={f.fim} onChange={(e) => setF({ ...f, fim: e.target.value })} /></div></div>
        <div><Label>Valor combinado (só registro, em R$)</Label><Input type="number" value={f.valor} onChange={(e) => setF({ ...f, valor: e.target.value })} /></div>
        <Button disabled={!f.profissional_id || !f.fim || criarDestaque.isPending} onClick={() => criarDestaque.mutate({ profissional_id: f.profissional_id, tipo: f.tipo as "categoria" | "regiao" | "topo", categoria_id: f.categoria_id || null, uf: f.uf || null, inicio: f.inicio, fim: f.fim, valor: f.valor ? Number(f.valor) : null })}><Megaphone className="h-4 w-4 mr-1" />Registrar destaque</Button>
      </div>
    </div>
  );
}
