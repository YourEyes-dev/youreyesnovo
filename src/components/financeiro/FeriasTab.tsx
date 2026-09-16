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
import { Switch } from "@/components/ui/switch";
import { Plus, Sun, Eye, Calculator, AlertTriangle } from "lucide-react";
import { useFolhaCalculo } from "@/hooks/useFolhaCalculo";
import { useColaboradores } from "@/hooks/useColaboradores";
import { toast } from "sonner";
import {
  useFeriasMediaVariaveis, descreverMedia, type MediaVariaveis, type MediaCompetencia,
} from "@/hooks/useFeriasMediaVariaveis";
import { FeriasEsocialEventos } from "@/components/ferias/FeriasEsocialEventos";

const fmtMoeda = (v: number) => (v || 0).toLocaleString("pt-BR", { minimumFractionDigits: 2 });

export function FeriasTab() {
  const { useFeriasCalculo, criarFeriasCalculo, criandoFerias } = useFolhaCalculo();
  const { data: ferias = [], isLoading } = useFeriasCalculo();
  const { colaboradores } = useColaboradores();
  const [showModal, setShowModal] = useState(false);
  const [showDetalhe, setShowDetalhe] = useState<any>(null);
  const { apurar, apurando } = useFeriasMediaVariaveis();
  // Memória da média apurada. Fica ao lado do valor para o DP conferir de
  // onde ele saiu antes de fechar o cálculo (art. 142 / RNF-008).
  const [media, setMedia] = useState<MediaVariaveis | null>(null);
  const [mediaEditada, setMediaEditada] = useState(false);

  const [form, setForm] = useState({
    colaborador_id: "",
    colaborador_nome: "",
    colaborador_cpf: "",
    periodo_aquisitivo_inicio: "",
    periodo_aquisitivo_fim: "",
    data_inicio_gozo: "",
    data_fim_gozo: "",
    dias_gozo: 30,
    dias_abono: 0,
    remuneracao_base: 0,
    media_variaveis: 0,
    em_dobro: false,
    dependentes_irrf: 0,
  });

  const limparMedia = () => { setMedia(null); setMediaEditada(false); };

  const handleApurarMedia = async () => {
    if (!form.colaborador_cpf) return toast.error("Selecione o colaborador");
    if (!form.periodo_aquisitivo_inicio || !form.periodo_aquisitivo_fim) {
      return toast.error("Informe o período aquisitivo para apurar a média");
    }
    try {
      const r = await apurar({
        cpf: form.colaborador_cpf,
        aquisitivoInicio: form.periodo_aquisitivo_inicio,
        aquisitivoFim: form.periodo_aquisitivo_fim,
        inicioGozo: form.data_inicio_gozo || undefined,
      });
      if (!r) return;
      setMedia(r);
      setMediaEditada(false);
      setForm(p => ({ ...p, media_variaveis: r.media }));
      if (r.avisos.length > 0) toast.warning(r.avisos[0]);
      else toast.success(`Média apurada: R$ ${fmtMoeda(r.media)}`);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Não foi possível apurar a média");
    }
  };

  const handleColabSelect = (id: string) => {
    const c = colaboradores.find((c: any) => c.id === id) as any;
    if (c) {
      limparMedia();
      setForm(p => ({
        ...p,
        colaborador_id: c.id,
        colaborador_nome: c.nome_completo,
        colaborador_cpf: c.cpf,
        remuneracao_base: c.salario || 0,
        media_variaveis: 0,
      }));
    }
  };

  const handleCalcular = async () => {
    if (!form.colaborador_nome || !form.data_inicio_gozo) return toast.error("Preencha os campos obrigatórios");
    await criarFeriasCalculo({
      ...form,
      remuneracao_base: form.remuneracao_base, // fix naming
      // Origem da média + memória do art. 142, para o valor se reproduzir depois.
      media_origem: !media ? "manual" : mediaEditada ? "apurada_ajustada" : "apurada",
      media_memoria: media,
    });
    setShowModal(false);
    limparMedia();
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold flex items-center gap-2">
            <Sun className="w-5 h-5 text-primary" /> Cálculo de Férias
          </h3>
          <p className="text-sm text-muted-foreground">Cálculo com 1/3, abono e incidências CLT</p>
        </div>
        <Button onClick={() => setShowModal(true)}>
          <Plus className="w-4 h-4 mr-2" /> Calcular Férias
        </Button>
      </div>

      <Card>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Colaborador</TableHead>
                <TableHead>Período Aquisitivo</TableHead>
                <TableHead>Gozo</TableHead>
                <TableHead className="text-center">Dias</TableHead>
                <TableHead className="text-right">Bruto</TableHead>
                <TableHead className="text-right">Líquido</TableHead>
                <TableHead className="text-center">Status</TableHead>
                <TableHead></TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {isLoading ? (
                <TableRow><TableCell colSpan={8} className="text-center py-8 text-muted-foreground">Carregando...</TableCell></TableRow>
              ) : ferias.length === 0 ? (
                <TableRow><TableCell colSpan={8} className="text-center py-8 text-muted-foreground">Nenhum cálculo de férias registrado.</TableCell></TableRow>
              ) : ferias.map((f: any) => (
                <TableRow key={f.id}>
                  <TableCell className="font-medium">{f.colaborador_nome}</TableCell>
                  <TableCell className="text-sm">{f.periodo_aquisitivo_inicio ? `${new Date(f.periodo_aquisitivo_inicio).toLocaleDateString("pt-BR")} a ${new Date(f.periodo_aquisitivo_fim).toLocaleDateString("pt-BR")}` : "—"}</TableCell>
                  <TableCell className="text-sm">{f.data_inicio_gozo ? `${new Date(f.data_inicio_gozo).toLocaleDateString("pt-BR")} a ${new Date(f.data_fim_gozo).toLocaleDateString("pt-BR")}` : "—"}</TableCell>
                  <TableCell className="text-center">{f.dias_gozo}{f.dias_abono > 0 ? ` (+${f.dias_abono} abono)` : ""}</TableCell>
                  <TableCell className="text-right">R$ {fmtMoeda(f.total_bruto)}</TableCell>
                  <TableCell className="text-right font-bold">R$ {fmtMoeda(f.total_liquido)}</TableCell>
                  <TableCell className="text-center">
                    <Badge variant={f.em_dobro ? "destructive" : "secondary"} className="text-xs">
                      {f.em_dobro ? "Em Dobro" : f.status}
                    </Badge>
                  </TableCell>
                  <TableCell>
                    <Button variant="ghost" size="icon" onClick={() => setShowDetalhe(f)}>
                      <Eye className="w-4 h-4" />
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      {/* Modal Calcular */}
      <Dialog open={showModal} onOpenChange={setShowModal}>
        <DialogContent className="sm:max-w-xl">
          <DialogHeader>
            <DialogTitle>Calcular Férias</DialogTitle>
            <DialogDescription>Preencha os dados para calcular as férias</DialogDescription>
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
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Início Per. Aquisitivo</Label>
                <Input type="date" value={form.periodo_aquisitivo_inicio} onChange={e => { limparMedia(); setForm(p => ({ ...p, periodo_aquisitivo_inicio: e.target.value })); }} />
              </div>
              <div className="space-y-2">
                <Label>Fim Per. Aquisitivo</Label>
                <Input type="date" value={form.periodo_aquisitivo_fim} onChange={e => { limparMedia(); setForm(p => ({ ...p, periodo_aquisitivo_fim: e.target.value })); }} />
              </div>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Início do Gozo *</Label>
                <Input type="date" value={form.data_inicio_gozo} onChange={e => setForm(p => ({ ...p, data_inicio_gozo: e.target.value }))} />
              </div>
              <div className="space-y-2">
                <Label>Fim do Gozo</Label>
                <Input type="date" value={form.data_fim_gozo} onChange={e => setForm(p => ({ ...p, data_fim_gozo: e.target.value }))} />
              </div>
            </div>
            <div className="grid grid-cols-3 gap-4">
              <div className="space-y-2">
                <Label>Dias de Gozo</Label>
                <Input type="number" value={form.dias_gozo} onChange={e => setForm(p => ({ ...p, dias_gozo: Number(e.target.value) }))} />
              </div>
              <div className="space-y-2">
                <Label>Dias Abono</Label>
                <Input type="number" value={form.dias_abono} onChange={e => setForm(p => ({ ...p, dias_abono: Number(e.target.value) }))} />
              </div>
              <div className="space-y-2">
                <Label>Remuneração Base</Label>
                <Input type="number" step="0.01" value={form.remuneracao_base} onChange={e => setForm(p => ({ ...p, remuneracao_base: Number(e.target.value) }))} />
              </div>
            </div>
            {/* Média das variáveis — art. 142 */}
            <div className="rounded-lg border p-3 space-y-3">
              <div className="flex items-end gap-3">
                <div className="flex-1 space-y-2">
                  <Label>Média de variáveis (art. 142)</Label>
                  <Input
                    type="number" step="0.01" value={form.media_variaveis}
                    onChange={e => {
                      if (media) setMediaEditada(true);
                      setForm(p => ({ ...p, media_variaveis: Number(e.target.value) }));
                    }}
                  />
                </div>
                <Button type="button" variant="outline" onClick={handleApurarMedia} disabled={apurando}>
                  <Calculator className="w-4 h-4 mr-2" />
                  {apurando ? "Apurando..." : "Apurar da folha"}
                </Button>
              </div>

              {!media && (
                <p className="text-xs text-muted-foreground">
                  Horas extras, comissões e adicionais habituais entram nas férias pela média.
                  Apure da folha para o valor sair com memória — ou digite, se a apuração for feita fora.
                </p>
              )}

              {media && (
                <div className="space-y-2 text-xs">
                  <div className="flex flex-wrap items-center gap-2">
                    <Badge variant={mediaEditada ? "outline" : "secondary"}>
                      {mediaEditada ? "Apurada e ajustada à mão" : "Apurada da folha"}
                    </Badge>
                    <span className="text-muted-foreground">{descreverMedia(media)}</span>
                  </div>

                  {media.avisos.map((a, i) => (
                    <p key={i} className="flex items-start gap-1.5 text-amber-600 dark:text-amber-500">
                      <AlertTriangle className="w-3.5 h-3.5 mt-0.5 shrink-0" /> {a}
                    </p>
                  ))}

                  {media.rubricas.length > 0 && (
                    <div className="space-y-1">
                      <p className="text-muted-foreground">Rubricas somadas:</p>
                      {media.rubricas.map((r, i) => (
                        <div key={i} className="flex justify-between">
                          <span>{r.descricao}</span>
                          <span className="tabular-nums">R$ {fmtMoeda(r.valor)}</span>
                        </div>
                      ))}
                    </div>
                  )}

                  {media.competencias.length > 0 && (
                    <details>
                      <summary className="cursor-pointer text-muted-foreground">
                        Ver competência a competência ({media.competencias.length})
                      </summary>
                      <div className="mt-1 space-y-1">
                        {media.competencias.map((c, i) => (
                          <div key={i} className="flex justify-between">
                            <span>{c.competencia}</span>
                            <span className="tabular-nums">R$ {fmtMoeda(c.valor)}</span>
                          </div>
                        ))}
                      </div>
                    </details>
                  )}
                </div>
              )}
            </div>

            <div className="flex items-center gap-2">
              <Switch checked={form.em_dobro} onCheckedChange={v => setForm(p => ({ ...p, em_dobro: v }))} />
              <Label>Férias em dobro (período concessivo vencido)</Label>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowModal(false)}>Cancelar</Button>
            <Button onClick={handleCalcular} disabled={criandoFerias}>
              {criandoFerias ? "Calculando..." : "Calcular"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Modal Detalhe */}
      <Dialog open={!!showDetalhe} onOpenChange={() => setShowDetalhe(null)}>
        <DialogContent className="sm:max-w-xl">
          <DialogHeader>
            <DialogTitle>Férias — {showDetalhe?.colaborador_nome}</DialogTitle>
          </DialogHeader>
          {showDetalhe && (
            <div className="space-y-3 text-sm">
              <div className="grid grid-cols-2 gap-2">
                <div><span className="text-muted-foreground">Dias gozo:</span> {showDetalhe.dias_gozo}</div>
                <div><span className="text-muted-foreground">Abono:</span> {showDetalhe.dias_abono} dias</div>
                <div><span className="text-muted-foreground">Pagamento até:</span> {showDetalhe.prazo_legal ? new Date(showDetalhe.prazo_legal).toLocaleDateString("pt-BR") : "—"}</div>
                {showDetalhe.em_dobro && <Badge variant="destructive">Férias em Dobro</Badge>}
              </div>
              <Card>
                <CardContent className="space-y-2 pt-4">
                  <div className="flex justify-between"><span>Férias Gozadas</span><span className="font-medium">R$ {fmtMoeda(showDetalhe.valor_ferias)}</span></div>
                  <div className="flex justify-between"><span>1/3 Constitucional</span><span className="font-medium">R$ {fmtMoeda(showDetalhe.valor_terco)}</span></div>
                  {showDetalhe.valor_abono > 0 && <div className="flex justify-between"><span>Abono Pecuniário</span><span className="font-medium">R$ {fmtMoeda(showDetalhe.valor_abono)}</span></div>}
                  {showDetalhe.valor_abono_terco > 0 && <div className="flex justify-between"><span>1/3 do Abono</span><span className="font-medium">R$ {fmtMoeda(showDetalhe.valor_abono_terco)}</span></div>}
                  <div className="border-t pt-2 flex justify-between font-semibold"><span>Total Bruto</span><span>R$ {fmtMoeda(showDetalhe.total_bruto)}</span></div>
                  <div className="flex justify-between text-destructive"><span>INSS</span><span>- R$ {fmtMoeda(showDetalhe.valor_inss)}</span></div>
                  <div className="flex justify-between text-destructive"><span>IRRF</span><span>- R$ {fmtMoeda(showDetalhe.valor_irrf)}</span></div>
                  <div className="border-t pt-2 flex justify-between font-bold text-lg"><span>Líquido</span><span className="text-primary">R$ {fmtMoeda(showDetalhe.total_liquido)}</span></div>
                </CardContent>
              </Card>

              {/* Memória da média — de onde saiu o valor das variáveis */}
              {showDetalhe.memoria_calculo?.media_variaveis && (
                <Card>
                  <CardContent className="pt-4 space-y-2 text-xs">
                    <div className="flex items-center justify-between">
                      <span className="font-medium text-sm">Média de variáveis (art. 142)</span>
                      <Badge variant="secondary">
                        {showDetalhe.media_origem === "apurada" ? "Apurada da folha"
                          : showDetalhe.media_origem === "apurada_ajustada" ? "Apurada e ajustada"
                          : "Informada à mão"}
                      </Badge>
                    </div>
                    <p className="text-muted-foreground">
                      {descreverMedia(showDetalhe.memoria_calculo.media_variaveis)}
                    </p>
                    {(showDetalhe.memoria_calculo.media_variaveis.competencias || []).map((c: MediaCompetencia, i: number) => (
                      <div key={i} className="flex justify-between">
                        <span>{c.competencia}</span>
                        <span className="tabular-nums">R$ {fmtMoeda(c.valor)}</span>
                      </div>
                    ))}
                  </CardContent>
                </Card>
              )}

              {/* Eventos do eSocial desta concessão (RF-008) */}
              <div className="border-t pt-3">
                <FeriasEsocialEventos calculoId={showDetalhe.id} />
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
