import { useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from "@/components/ui/dialog";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { Plus, Gift, Eye, Calculator, AlertTriangle, Users, CalendarClock, Settings2, Sun, FileText, Archive } from "lucide-react";
import { useFolhaCalculo } from "@/hooks/useFolhaCalculo";
import { useColaboradores } from "@/hooks/useColaboradores";
import {
  useDecimoTerceiro, useDecimoTerceiroLote, useDecimoTerceiroConfig,
  useDecimoTerceiroContabil,
  descreverAvos, descreverMedia13, descreverLote, nomeMes,
  CONFIG13_PADRAO,
  type Apuracao13, type Config13,
} from "@/hooks/useDecimoTerceiro";
import { useDecimoTerceiroDocumentos } from "@/hooks/useDecimoTerceiroDocumentos";
import { toast } from "sonner";

const fmtMoeda = (v: number) => (v || 0).toLocaleString("pt-BR", { minimumFractionDigits: 2 });

export function DecimoTerceiroTab() {
  const { use13Calculo, criar13Calculo, criando13 } = useFolhaCalculo();
  const [ano, setAno] = useState(new Date().getFullYear());
  const { data: calculos = [], isLoading } = use13Calculo(ano);
  const { colaboradores } = useColaboradores();
  const [showModal, setShowModal] = useState(false);
  const [showDetalhe, setShowDetalhe] = useState<any>(null);
  const { apurar, apurando } = useDecimoTerceiro();
  const { processar, processando } = useDecimoTerceiroLote();
  const { carregar: carregarConfig, salvar: salvarConfig, salvando: salvandoConfig } = useDecimoTerceiroConfig();
  const { adiantarNasFerias, ocupado: ocupadoContabil } = useDecimoTerceiroContabil();
  const { arquivar, visualizar, gerando: gerandoDoc } = useDecimoTerceiroDocumentos();

  // Recibo e memória: ver antes, arquivar depois (CA-008 — todo documento
  // produzido vai para Documentos com metadados).
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const handleDocumento = async (c: any, tipo: "recibo" | "memoria", arquivarTambem: boolean) => {
    try {
      if (!arquivarTambem) {
        if (!visualizar(c, tipo)) {
          toast.error("O navegador bloqueou a janela. Libere os pop-ups para ver o documento.");
        }
        return;
      }
      await arquivar(c, tipo);
      toast.success(
        `${tipo === "recibo" ? "Recibo" : "Memória de cálculo"} arquivado em Documentos, na pasta do colaborador.`);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Não foi possível gerar o documento");
    }
  };

  // O "adiantar 13º" da programação de férias era um botão órfão: ninguém
  // consumia a marcação (Lei 4.749/1965, art. 2º, § 2º).
  const handleAdiantamentoFerias = async () => {
    try {
      const r = await adiantarNasFerias(ano);
      if (!r) return;
      if (r.adiantamentos_gerados === 0 && r.ja_existiam === 0) {
        toast.info("Ninguém pediu o adiantamento do 13º junto às férias neste ano.");
        return;
      }
      const extra = r.pedidos_fora_de_janeiro > 0
        ? ` · ${r.pedidos_fora_de_janeiro} pedido(s) fora de janeiro (registrado na memória)` : "";
      toast.success(`${r.adiantamentos_gerados} adiantamento(s) gerado(s) no gozo das férias${extra}.`);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Não foi possível gerar os adiantamentos das férias");
    }
  };
  const [showConfig, setShowConfig] = useState(false);
  const [config, setConfig] = useState<Config13>(CONFIG13_PADRAO);

  const abrirConfig = async () => {
    try { setConfig(await carregarConfig()); } catch { /* usa o padrão */ }
    setShowConfig(true);
  };

  const gravarConfig = async () => {
    try {
      await salvarConfig(config);
      toast.success("Política do 13º salva. Os próximos cálculos já seguem estas regras.");
      setShowConfig(false);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Não foi possível salvar a configuração");
    }
  };
  // Memória da apuração. Fica ao lado dos valores para o DP conferir de
  // onde saíram antes de fechar o cálculo (Lei 4.090 / RNF-001).
  const [apuracao, setApuracao] = useState<Apuracao13 | null>(null);
  const [avosEditado, setAvosEditado] = useState(false);
  const [mediaEditada, setMediaEditada] = useState(false);

  const [form, setForm] = useState({
    ano: new Date().getFullYear(),
    colaborador_id: "",
    colaborador_nome: "",
    colaborador_cpf: "",
    parcela: 1 as 1 | 2,
    meses_trabalhados: 12,
    remuneracao_base: 0,
    media_variaveis: 0,
    valor_primeira_parcela: 0,
    dependentes_irrf: 0,
  });

  // Folha inteira de uma vez: o cálculo roda no banco (RNF-008), não
  // colaborador a colaborador num modal.
  const handleLote = async (parcela: 1 | 2) => {
    try {
      const r = await processar(ano, parcela);
      if (!r) return;
      if (r.erros.length > 0) toast.warning(`${parcela}ª parcela — ${descreverLote(r)}. Primeiro erro: ${r.erros[0].colaborador}: ${r.erros[0].erro}`);
      else if (r.criados === 0) toast.info(`${parcela}ª parcela — nada a gerar: ${descreverLote(r)}.`);
      else toast.success(`${parcela}ª parcela — ${descreverLote(r)}. Prazo legal: ${r.prazo_legal.split("-").reverse().join("/")}.`);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Não foi possível processar o lote");
    }
  };

  const limparApuracao = () => { setApuracao(null); setAvosEditado(false); setMediaEditada(false); };

  const handleApurar = async () => {
    if (!form.colaborador_cpf) return toast.error("Selecione o colaborador");
    try {
      const r = await apurar({
        cpf: form.colaborador_cpf,
        ano: form.ano,
        salario: form.remuneracao_base || undefined,
      });
      if (!r) return;
      setApuracao(r);
      setAvosEditado(false);
      setMediaEditada(false);
      setForm(p => ({
        ...p,
        meses_trabalhados: r.avos,
        media_variaveis: r.media_variaveis,
        remuneracao_base: r.remuneracao_base || p.remuneracao_base,
      }));
      if (r.avisos.length > 0) toast.warning(r.avisos[0]);
      else toast.success(`Apurado: ${r.avos}/12 avos`);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Não foi possível apurar o 13º");
    }
  };

  const handleColabSelect = (id: string) => {
    const c = colaboradores.find((c: any) => c.id === id) as any;
    if (c) {
      limparApuracao();
      setForm(p => ({
        ...p,
        colaborador_id: c.id,
        colaborador_nome: c.nome_completo,
        colaborador_cpf: c.cpf,
        remuneracao_base: c.salario || 0,
        meses_trabalhados: 12,
        media_variaveis: 0,
      }));
    }
  };

  const handleCalcular = async () => {
    if (!form.colaborador_nome) return toast.error("Selecione o colaborador");
    await criar13Calculo({
      ...form,
      remuneracao_base: form.remuneracao_base,
      // Origem dos valores + memória da apuração, para o 13º se reproduzir
      // depois (Lei 4.090 / Decreto 57.155 / RNF-001 e RNF-007).
      avos_origem: !apuracao ? "manual" : avosEditado ? "apurado_ajustado" : "apurado",
      media_origem: !apuracao ? "manual" : mediaEditada ? "apurado_ajustado" : "apurado",
      apuracao_memoria: apuracao,
    });
    setShowModal(false);
    limparApuracao();
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold flex items-center gap-2">
            <Gift className="w-5 h-5 text-primary" /> 13º Salário
          </h3>
          <p className="text-sm text-muted-foreground">Cálculo de 1ª e 2ª parcela com INSS/IRRF</p>
        </div>
        <div className="flex gap-2">
          <Input type="number" className="w-24" value={ano} onChange={e => setAno(Number(e.target.value))} />
          <Button variant="outline" size="icon" onClick={abrirConfig} title="Política do 13º">
            <Settings2 className="w-4 h-4" />
          </Button>
          <Button variant="outline" onClick={() => handleLote(1)} disabled={processando}>
            <Users className="w-4 h-4 mr-2" />
            {processando ? "Processando..." : "Lote 1ª parcela"}
          </Button>
          <Button variant="outline" onClick={() => handleLote(2)} disabled={processando}>
            <Users className="w-4 h-4 mr-2" />
            {processando ? "Processando..." : "Lote 2ª parcela"}
          </Button>
          <Button variant="outline" onClick={handleAdiantamentoFerias} disabled={ocupadoContabil}
                  title="Gera a 1ª parcela de quem pediu o adiantamento junto às férias">
            <Sun className="w-4 h-4 mr-2" />
            {ocupadoContabil ? "Gerando..." : "Adiantamento nas férias"}
          </Button>
          {/* Abre no MESMO ano que está sendo visto na lista: cálculo
              lançado num ano diferente do filtro some da tela e parece
              que não gravou. */}
          <Button onClick={() => { setForm(p => ({ ...p, ano })); setShowModal(true); }}>
            <Plus className="w-4 h-4 mr-2" /> Calcular 13º
          </Button>
        </div>
      </div>

      <Card>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Colaborador</TableHead>
                <TableHead className="text-center">Parcela</TableHead>
                <TableHead className="text-center">Avos</TableHead>
                <TableHead className="text-center">Situação</TableHead>
                <TableHead className="text-center">Prazo legal</TableHead>
                <TableHead className="text-right">13º integral</TableHead>
                <TableHead className="text-right">INSS</TableHead>
                <TableHead className="text-right">IRRF</TableHead>
                <TableHead className="text-right">Líquido</TableHead>
                <TableHead></TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {isLoading ? (
                <TableRow><TableCell colSpan={10} className="text-center py-8 text-muted-foreground">Carregando...</TableCell></TableRow>
              ) : calculos.length === 0 ? (
                <TableRow><TableCell colSpan={10} className="text-center py-8 text-muted-foreground">Nenhum cálculo de 13º para {ano}.</TableCell></TableRow>
              ) : calculos.map((c: any) => (
                <TableRow key={c.id}>
                  <TableCell className="font-medium">{c.colaborador_nome}</TableCell>
                  <TableCell className="text-center"><Badge variant="outline">{c.parcela}ª</Badge></TableCell>
                  <TableCell className="text-center">{c.meses_trabalhados}/12</TableCell>
                  <TableCell className="text-center">
                    <Badge variant={
                      c.status === "pago" ? "default"
                        : c.status === "aprovado" ? "secondary"
                          : c.status === "cancelado" ? "destructive" : "outline"
                    }>{c.status}</Badge>
                  </TableCell>
                  <TableCell className="text-center text-xs text-muted-foreground">
                    {c.data_prevista
                      ? <span className="inline-flex items-center gap-1">
                          <CalendarClock className="w-3 h-3" />
                          {String(c.data_prevista).split("-").reverse().join("/")}
                        </span>
                      : "—"}
                  </TableCell>
                  <TableCell className="text-right">R$ {fmtMoeda(c.valor_bruto)}</TableCell>
                  <TableCell className="text-right text-destructive">R$ {fmtMoeda(c.valor_inss)}</TableCell>
                  <TableCell className="text-right text-destructive">R$ {fmtMoeda(c.valor_irrf)}</TableCell>
                  <TableCell className="text-right font-bold">R$ {fmtMoeda(c.total_liquido)}</TableCell>
                  <TableCell>
                    <div className="flex items-center justify-end gap-0.5">
                      <Button variant="ghost" size="icon" onClick={() => setShowDetalhe(c)} title="Detalhe">
                        <Eye className="w-4 h-4" />
                      </Button>
                      <Button variant="ghost" size="icon" title="Ver recibo"
                              onClick={() => handleDocumento(c, "recibo", false)}>
                        <FileText className="w-4 h-4" />
                      </Button>
                      <Button variant="ghost" size="icon" title="Arquivar recibo em Documentos"
                              disabled={gerandoDoc}
                              onClick={() => handleDocumento(c, "recibo", true)}>
                        <Archive className="w-4 h-4" />
                      </Button>
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      {/* Política do 13º — as escolhas que a lei permite ficam com a empresa */}
      <Dialog open={showConfig} onOpenChange={setShowConfig}>
        <DialogContent className="sm:max-w-xl">
          <DialogHeader>
            <DialogTitle>Política do 13º salário</DialogTitle>
            <DialogDescription>
              Onde a legislação admite mais de uma leitura, a escolha é da empresa.
              Vale para os próximos cálculos; o que já foi apurado guarda a regra da época.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-5 py-2">
            <div className="space-y-2">
              <Label>Adiantamento (1ª parcela)</Label>
              <Select
                value={config.adiantamento_base}
                onValueChange={v => setConfig(c => ({ ...c, adiantamento_base: v }))}
              >
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="proporcional_apurado">Metade do 13º proporcional apurado</SelectItem>
                  <SelectItem value="remuneracao_mes_anterior">Metade da remuneração do mês anterior</SelectItem>
                </SelectContent>
              </Select>
              <p className="text-xs text-muted-foreground">
                A segunda é a letra do art. 2º da Lei 4.749/1965. A primeira é a prática de
                mercado e evita adiantar mais do que o 13º devido a quem tem menos de 12 avos.
                O 13º total é o mesmo nas duas — muda quanto entra em novembro.
              </p>
            </div>

            <div className="space-y-2">
              <Label>Média das horas extras</Label>
              <Select
                value={config.media_horas_extras}
                onValueChange={v => setConfig(c => ({ ...c, media_horas_extras: v }))}
              >
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="fisica">Média física — horas do ponto × valor da hora atual</SelectItem>
                  <SelectItem value="valores">Média dos valores pagos no ano</SelectItem>
                </SelectContent>
              </Select>
              <p className="text-xs text-muted-foreground">
                A média física é o entendimento da Súmula 347 do TST e protege a empresa quando
                houve aumento salarial no ano — a média por valores históricos pagaria a menos.
                Sem registro de ponto no ano, o sistema usa os valores e avisa.
              </p>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Divisor de horas no mês</Label>
                <Input
                  type="number" step="1"
                  value={config.divisor_horas_mes}
                  onChange={e => setConfig(c => ({ ...c, divisor_horas_mes: Number(e.target.value) }))}
                />
                <p className="text-xs text-muted-foreground">220 para jornada de 44h semanais.</p>
              </div>
              <div className="space-y-2">
                <Label>Dias de afastamento por conta da empresa</Label>
                <Input
                  type="number" step="1"
                  value={config.afastamento_dias_empregador}
                  onChange={e => setConfig(c => ({ ...c, afastamento_dias_empregador: Number(e.target.value) }))}
                />
                <p className="text-xs text-muted-foreground">15 dias antes do benefício do INSS.</p>
              </div>
            </div>

            <div className="space-y-2">
              <Label>Divisor da média das variáveis</Label>
              <Select
                value={config.media_divisor}
                onValueChange={v => setConfig(c => ({ ...c, media_divisor: v }))}
              >
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="avos_apurados">Pelos avos apurados</SelectItem>
                  <SelectItem value="meses_com_valor">Só pelos meses com valor</SelectItem>
                  <SelectItem value="doze_avos">Sempre por 12</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="flex items-start gap-2 rounded-md border border-amber-500/40 bg-amber-500/5 p-3">
              <AlertTriangle className="w-4 h-4 mt-0.5 shrink-0 text-amber-600 dark:text-amber-500" />
              <p className="text-xs text-muted-foreground">
                Estas escolhas mudam valores pagos. Confirme com a contabilidade antes de
                alterar, e refaça os cálculos ainda não aprovados para a nova regra valer neles.
              </p>
            </div>
          </div>

          <DialogFooter>
            <Button variant="outline" onClick={() => setShowConfig(false)}>Cancelar</Button>
            <Button onClick={gravarConfig} disabled={salvandoConfig}>
              {salvandoConfig ? "Salvando..." : "Salvar política"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Modal Calcular */}
      <Dialog open={showModal} onOpenChange={setShowModal}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>Calcular 13º Salário</DialogTitle>
            <DialogDescription>Preencha os dados para calcular a parcela</DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="space-y-2">
              <Label>Colaborador *</Label>
              <Select value={form.colaborador_id} onValueChange={handleColabSelect}>
                <SelectTrigger><SelectValue placeholder="Selecione..." /></SelectTrigger>
                <SelectContent>
                  {colaboradores.map((c: any) => (
                    <SelectItem key={c.id} value={c.id}>{c.nome_completo}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="grid grid-cols-3 gap-4">
              <div className="space-y-2">
                <Label>Parcela</Label>
                <Select value={String(form.parcela)} onValueChange={v => setForm(p => ({ ...p, parcela: Number(v) as 1 | 2 }))}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="1">1ª Parcela</SelectItem>
                    <SelectItem value="2">2ª Parcela</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <Label>Ano-base</Label>
                <Input
                  type="number"
                  value={form.ano}
                  onChange={e => { limparApuracao(); setForm(p => ({ ...p, ano: Number(e.target.value) })); }}
                />
              </div>
              <div className="space-y-2">
                <Label>Remuneração Base</Label>
                <Input type="number" step="0.01" value={form.remuneracao_base} onChange={e => setForm(p => ({ ...p, remuneracao_base: Number(e.target.value) }))} />
              </div>
            </div>

            {/* Apuração: avos da Lei 4.090 e média das variáveis do ano */}
            <div className="rounded-md border p-3 space-y-3">
              <div className="flex items-end gap-2">
                <div className="space-y-2 flex-1">
                  <Label>Avos (meses trabalhados)</Label>
                  <Input
                    type="number" min="0" max="12"
                    value={form.meses_trabalhados}
                    onChange={e => {
                      if (apuracao) setAvosEditado(true);
                      setForm(p => ({ ...p, meses_trabalhados: Number(e.target.value) }));
                    }}
                  />
                </div>
                <div className="space-y-2 flex-1">
                  <Label>Média das variáveis</Label>
                  <Input
                    type="number" step="0.01"
                    value={form.media_variaveis}
                    onChange={e => {
                      if (apuracao) setMediaEditada(true);
                      setForm(p => ({ ...p, media_variaveis: Number(e.target.value) }));
                    }}
                  />
                </div>
                <Button type="button" variant="outline" onClick={handleApurar} disabled={apurando}>
                  <Calculator className="w-4 h-4 mr-2" />
                  {apurando ? "Apurando..." : "Apurar"}
                </Button>
              </div>

              {!apuracao && (
                <p className="text-xs text-muted-foreground">
                  Apure para o sistema contar os avos a partir da admissão, das faltas e dos
                  afastamentos (1/12 por mês, fração de 15 dias) e somar a média das variáveis
                  do ano — ou digite, se a apuração for feita fora.
                </p>
              )}

              {apuracao && (
                <div className="space-y-2 text-xs">
                  <div className="flex flex-wrap items-center gap-2">
                    <Badge variant={avosEditado ? "outline" : "secondary"}>
                      {avosEditado ? "Avos apurados e ajustados à mão" : "Avos apurados"}
                    </Badge>
                    <span className="text-muted-foreground">{descreverAvos(apuracao)}</span>
                  </div>
                  <div className="flex flex-wrap items-center gap-2">
                    <Badge variant={mediaEditada ? "outline" : "secondary"}>
                      {mediaEditada ? "Média apurada e ajustada à mão" : "Média apurada"}
                    </Badge>
                    <span className="text-muted-foreground">{descreverMedia13(apuracao)}</span>
                  </div>

                  {apuracao.avisos.map((a, i) => (
                    <p key={i} className="flex items-start gap-1.5 text-amber-600 dark:text-amber-500">
                      <AlertTriangle className="w-3.5 h-3.5 mt-0.5 shrink-0" /> {a}
                    </p>
                  ))}

                  <details>
                    <summary className="cursor-pointer text-muted-foreground">Memória mês a mês</summary>
                    <div className="mt-1 space-y-0.5">
                      {apuracao.memoria_avos.meses?.map(m => (
                        <div key={m.mes} className="flex justify-between">
                          <span className={m.conta ? "" : "text-muted-foreground line-through"}>
                            {nomeMes(m.mes)}
                          </span>
                          <span className="tabular-nums text-muted-foreground">
                            {m.dias_computados} dia(s)
                            {m.faltas > 0 ? ` · ${m.faltas} falta(s)` : ""}
                            {m.dias_inss > 0 ? ` · ${m.dias_inss} dia(s) INSS` : ""}
                          </span>
                        </div>
                      ))}
                    </div>
                  </details>

                  {apuracao.memoria_media.rubricas?.length > 0 && (
                    <details>
                      <summary className="cursor-pointer text-muted-foreground">Rubricas somadas na média</summary>
                      <div className="mt-1 space-y-0.5">
                        {apuracao.memoria_media.rubricas.map((r, i) => (
                          <div key={i} className="flex justify-between">
                            <span>{r.descricao}</span>
                            <span className="tabular-nums">R$ {fmtMoeda(r.valor)}</span>
                          </div>
                        ))}
                      </div>
                    </details>
                  )}
                </div>
              )}
            </div>
            {form.parcela === 2 && (
              <div className="space-y-2">
                <Label>Valor 1ª Parcela (já paga)</Label>
                <Input type="number" step="0.01" value={form.valor_primeira_parcela} onChange={e => setForm(p => ({ ...p, valor_primeira_parcela: Number(e.target.value) }))} />
              </div>
            )}
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowModal(false)}>Cancelar</Button>
            <Button onClick={handleCalcular} disabled={criando13}>
              {criando13 ? "Calculando..." : "Calcular"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Modal Detalhe */}
      <Dialog open={!!showDetalhe} onOpenChange={() => setShowDetalhe(null)}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>13º Salário — {showDetalhe?.colaborador_nome}</DialogTitle>
          </DialogHeader>
          {showDetalhe && (
            <div className="space-y-3 text-sm">
              <div className="flex flex-wrap gap-2">
                <Button size="sm" variant="outline" onClick={() => handleDocumento(showDetalhe, "recibo", false)}>
                  <FileText className="w-4 h-4 mr-1.5" /> Ver recibo
                </Button>
                <Button size="sm" variant="outline" onClick={() => handleDocumento(showDetalhe, "memoria", false)}>
                  <Calculator className="w-4 h-4 mr-1.5" /> Ver memória
                </Button>
                <Button size="sm" variant="outline" disabled={gerandoDoc}
                        onClick={() => handleDocumento(showDetalhe, "recibo", true)}>
                  <Archive className="w-4 h-4 mr-1.5" /> Arquivar recibo
                </Button>
                <Button size="sm" variant="outline" disabled={gerandoDoc}
                        onClick={() => handleDocumento(showDetalhe, "memoria", true)}>
                  <Archive className="w-4 h-4 mr-1.5" /> Arquivar memória
                </Button>
              </div>
              <div className="grid grid-cols-2 gap-2">
                <div><span className="text-muted-foreground">Parcela:</span> {showDetalhe.parcela}ª</div>
                <div><span className="text-muted-foreground">Avos:</span> {showDetalhe.meses_trabalhados}/12</div>
              </div>
              {/* De onde vieram os números — é o que torna o cálculo auditável. */}
              <div className="flex flex-wrap gap-2">
                <Badge variant={showDetalhe.avos_origem === "apurado" ? "secondary" : "outline"}>
                  Avos: {showDetalhe.avos_origem === "apurado" ? "apurados do sistema"
                    : showDetalhe.avos_origem === "apurado_ajustado" ? "apurados e ajustados"
                      : "digitados"}
                </Badge>
                <Badge variant={showDetalhe.media_origem === "apurado" ? "secondary" : "outline"}>
                  Média: {showDetalhe.media_origem === "apurado" ? "apurada da folha"
                    : showDetalhe.media_origem === "apurado_ajustado" ? "apurada e ajustada"
                      : "digitada"}
                </Badge>
              </div>
              {showDetalhe.memoria_calculo?.apuracao && (
                <p className="text-xs text-muted-foreground">
                  {descreverAvos(showDetalhe.memoria_calculo.apuracao)}{" "}
                  {descreverMedia13(showDetalhe.memoria_calculo.apuracao)}
                </p>
              )}
              <Card>
                <CardContent className="space-y-2 pt-4">
                  <div className="flex justify-between"><span>13º Bruto</span><span className="font-medium">R$ {fmtMoeda(showDetalhe.valor_bruto)}</span></div>
                  {showDetalhe.parcela === 2 && <div className="flex justify-between text-muted-foreground"><span>(-) 1ª Parcela</span><span>R$ {fmtMoeda(showDetalhe.valor_primeira_parcela)}</span></div>}
                  <div className="flex justify-between text-destructive"><span>(-) INSS</span><span>R$ {fmtMoeda(showDetalhe.valor_inss)}</span></div>
                  <div className="flex justify-between text-destructive"><span>(-) IRRF</span><span>R$ {fmtMoeda(showDetalhe.valor_irrf)}</span></div>
                  <div className="flex justify-between"><span>FGTS</span><span className="text-muted-foreground">R$ {fmtMoeda(showDetalhe.valor_fgts)}</span></div>
                  <div className="border-t pt-2 flex justify-between font-bold text-lg"><span>Líquido</span><span className="text-primary">R$ {fmtMoeda(showDetalhe.total_liquido)}</span></div>
                </CardContent>
              </Card>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
