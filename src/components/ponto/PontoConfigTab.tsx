import { useState, useEffect } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { motion } from "framer-motion";
import { Settings, Monitor, Link2, Globe2, Camera, MapPin, Save, Loader2, Info, FileText, CalendarDays } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { useFeriados } from "@/hooks/useFeriados";
import { Switch } from "@/components/ui/switch";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import { Badge } from "@/components/ui/badge";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/useAuth";
import { useToast } from "@/hooks/use-toast";

import { ConfigJustificativasModal } from "./ConfigJustificativasModal";
import { GeofenceConfigCard } from "./GeofenceConfigCard";

interface PontoConfig {
  id: string;
  modo_registro: string;
  exigir_selfie_link: boolean;
  exigir_selfie_interno: boolean;
  exigir_localizacao: boolean;
  tolerancia_atraso: number;
  tolerancia_hora_extra: number;
  permitir_registro_fora_horario: boolean;
  bloquear_dispositivo_nao_autorizado: boolean;
  /**
   * Portaria 671 / CLT art. 74, §4º: o registro por link externo é sistema
   * ALTERNATIVO (REP-A) e só é autorizado por acordo ou instrumento coletivo.
   * O banco recusa ativar o modo sem isso.
   */
  link_externo_acordo_url: string;
}

export function PontoConfigTab() {
  const { feriados, criar: criarFeriado, excluir: excluirFeriado } = useFeriados();
  const [novoFeriado, setNovoFeriado] = useState({ data: "", nome: "", abrangencia: "nacional" as "nacional" | "estadual" | "municipal", uf: "", municipio: "" });
  const { tenantId } = useAuth();
  const { toast } = useToast();
  const queryClient = useQueryClient();

  const [showJustificativasModal, setShowJustificativasModal] = useState(false);

  const { data: config, isLoading } = useQuery({
    queryKey: ["ponto-config", tenantId],
    queryFn: async () => {
      if (!tenantId) return null;
      const { data, error } = await supabase
        .from("ponto_configuracao" as any)
        .select("*")
        .eq("tenant_id", tenantId)
        .maybeSingle();
      if (error) throw error;
      return data as any as PontoConfig | null;
    },
    enabled: !!tenantId,
  });

  const [form, setForm] = useState({
    modo_registro: "ambos",
    link_externo_acordo_url: "",
    exigir_selfie_link: true,
    exigir_selfie_interno: false,
    exigir_localizacao: true,
    tolerancia_atraso: 10,
    tolerancia_hora_extra: 10,
    permitir_registro_fora_horario: false,
    bloquear_dispositivo_nao_autorizado: false,
  });

  useEffect(() => {
    if (config) {
      setForm({
        modo_registro: config.modo_registro || "ambos",
        link_externo_acordo_url: (config as any).link_externo_acordo_url || "",
        exigir_selfie_link: config.exigir_selfie_link ?? true,
        exigir_selfie_interno: config.exigir_selfie_interno ?? false,
        exigir_localizacao: config.exigir_localizacao ?? true,
        tolerancia_atraso: config.tolerancia_atraso ?? 10,
        tolerancia_hora_extra: config.tolerancia_hora_extra ?? 10,
        permitir_registro_fora_horario: config.permitir_registro_fora_horario ?? false,
        bloquear_dispositivo_nao_autorizado: config.bloquear_dispositivo_nao_autorizado ?? false,
      });
    }
  }, [config]);

  const salvar = useMutation({
    mutationFn: async () => {
      if (!tenantId) throw new Error("Tenant não encontrado");
      if (config?.id) {
        const { error } = await supabase
          .from("ponto_configuracao" as any)
          .update(form as any)
          .eq("id", config.id);
        if (error) throw error;
      } else {
        const { error } = await supabase
          .from("ponto_configuracao" as any)
          .insert({ ...form, tenant_id: tenantId } as any);
        if (error) throw error;
      }
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["ponto-config"] });
      toast({ title: "Configurações salvas com sucesso!" });
    },
    onError: (e: any) => {
      // A trava do REP-A vem do banco com o texto legal completo; na tela ela
      // vira uma frase que o RH entende e sabe resolver.
      const msg = String(e?.message || "");
      if (msg.includes("REP-A") || msg.includes("alternativo")) {
        toast({
          title: "Falta o instrumento coletivo",
          description:
            "O registro por link é sistema alternativo e precisa estar autorizado em acordo ou " +
            "convenção coletiva. Informe o instrumento no campo acima, ou cadastre um acordo " +
            "vigente em Compliance › Acordos, e salve de novo.",
          variant: "destructive",
        });
        return;
      }
      toast({ title: "Erro ao salvar", description: e.message, variant: "destructive" });
    },
  });

  const MODOS = [
    {
      value: "interno",
      label: "Somente Interno (REP-C)",
      desc: "Registro apenas pelo painel do gestor/RH. Ideal para operações presenciais com relógio de ponto fixo.",
      icon: <Monitor className="w-5 h-5" />,
    },
    {
      value: "link_externo",
      label: "Somente Link Externo (REP-P)",
      desc: "Cada colaborador registra pelo próprio celular via link único. Ideal para equipes de campo e home office.",
      icon: <Link2 className="w-5 h-5" />,
    },
    {
      value: "ambos",
      label: "Ambos (Recomendado)",
      desc: "Permite registro interno pelo gestor e via link individual pelo colaborador. Máxima flexibilidade operacional.",
      icon: <Globe2 className="w-5 h-5" />,
    },
  ];

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-12">
        <Loader2 className="w-6 h-6 animate-spin text-muted-foreground" />
      </div>
    );
  }

  return (
    <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="space-y-6">
      {/* Modo de Registro */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-base">
            <Settings className="w-5 h-5 text-primary" /> Modo de Registro
          </CardTitle>
          <CardDescription>
            Defina como os colaboradores poderão registrar ponto. Conforme Portaria 671/2021.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <RadioGroup
            value={form.modo_registro}
            onValueChange={(v) => setForm((f) => ({ ...f, modo_registro: v }))}
            className="space-y-3"
          >
            {MODOS.map((modo) => (
              <label
                key={modo.value}
                className={`flex items-start gap-3 p-4 rounded-lg border-2 cursor-pointer transition-colors ${
                  form.modo_registro === modo.value
                    ? "border-primary bg-primary/5"
                    : "border-border hover:border-muted-foreground/30"
                }`}
              >
                <RadioGroupItem value={modo.value} className="mt-0.5" />
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    {modo.icon}
                    <span className="font-medium text-sm">{modo.label}</span>
                    {modo.value === "ambos" && (
                      <Badge variant="secondary" className="text-[10px]">Recomendado</Badge>
                    )}
                  </div>
                  <p className="text-xs text-muted-foreground mt-1">{modo.desc}</p>
                </div>
              </label>
            ))}
          </RadioGroup>

          {/* CLT art. 74, §4º / Portaria 671: o link externo é sistema
              ALTERNATIVO de registro (REP-A) — só vale autorizado por acordo
              ou instrumento coletivo. O banco recusa salvar o modo sem isso,
              então o campo aparece junto da escolha, não escondido em outra
              tela. */}
          {(form.modo_registro === "link_externo" || form.modo_registro === "ambos") && (
            <div className="mt-4 rounded-lg border border-amber-300 bg-amber-50 p-3 space-y-2">
              <Label className="text-sm font-medium text-amber-900">
                Instrumento que autoriza o registro por link (REP-A)
              </Label>
              <Input
                value={form.link_externo_acordo_url}
                onChange={(e) => setForm((f) => ({ ...f, link_externo_acordo_url: e.target.value }))}
                placeholder="Link ou referência do acordo/convenção coletiva"
              />
              <p className="text-xs text-amber-900">
                O registro pelo celular do colaborador é <strong>sistema alternativo</strong> e
                depende de autorização em acordo ou convenção coletiva (CLT art. 74, §4º; Portaria
                MTP 671/2021). Informe aqui o instrumento — ou cadastre um acordo coletivo vigente
                em Compliance › Acordos. Sem um dos dois, o sistema não deixa ativar este modo.
              </p>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Verificação */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-base">
            <Camera className="w-5 h-5 text-primary" /> Verificação e Segurança
          </CardTitle>
          <CardDescription>Configure selfie e geolocalização para prevenir fraudes.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {(form.modo_registro === "link_externo" || form.modo_registro === "ambos") && (
            <div className="flex items-center justify-between p-3 rounded-lg bg-muted/50">
              <div className="flex items-center gap-2">
                <Camera className="w-4 h-4 text-muted-foreground" />
                <div>
                  <Label className="text-sm font-medium">Selfie obrigatória (Link Externo)</Label>
                  <p className="text-xs text-muted-foreground">Colaborador deve tirar selfie ao registrar via link</p>
                </div>
              </div>
              <Switch
                checked={form.exigir_selfie_link}
                onCheckedChange={(v) => setForm((f) => ({ ...f, exigir_selfie_link: v }))}
              />
            </div>
          )}

          {(form.modo_registro === "interno" || form.modo_registro === "ambos") && (
            <div className="flex items-center justify-between p-3 rounded-lg bg-muted/50">
              <div className="flex items-center gap-2">
                <Camera className="w-4 h-4 text-muted-foreground" />
                <div>
                  <Label className="text-sm font-medium">Selfie obrigatória (Painel Interno)</Label>
                  <p className="text-xs text-muted-foreground">Exigir selfie no registro feito pelo gestor/RH</p>
                </div>
              </div>
              <Switch
                checked={form.exigir_selfie_interno}
                onCheckedChange={(v) => setForm((f) => ({ ...f, exigir_selfie_interno: v }))}
              />
            </div>
          )}

          <div className="flex items-center justify-between p-3 rounded-lg bg-muted/50">
            <div className="flex items-center gap-2">
              <MapPin className="w-4 h-4 text-muted-foreground" />
              <div>
                <Label className="text-sm font-medium">Geolocalização obrigatória</Label>
                <p className="text-xs text-muted-foreground">Capturar localização em todos os registros</p>
              </div>
            </div>
            <Switch
              checked={form.exigir_localizacao}
              onCheckedChange={(v) => setForm((f) => ({ ...f, exigir_localizacao: v }))}
            />
          </div>
        </CardContent>
      </Card>

      {/* Cerca de Geolocalização — só gestor vê o resultado das batidas */}
      <GeofenceConfigCard />



      {/* Tolerâncias */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-base">
            <Info className="w-5 h-5 text-primary" /> Tolerâncias (CLT Art. 58)
          </CardTitle>
          <CardDescription>Variações de até 5 min (entrada/saída) e 10 min diários não são descontadas nem pagas como extra.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div className="space-y-1">
              <Label className="text-sm">Tolerância atraso (min)</Label>
              <input
                type="number"
                min={0}
                max={30}
                value={form.tolerancia_atraso}
                onChange={(e) => setForm((f) => ({ ...f, tolerancia_atraso: Number(e.target.value) }))}
                className="flex h-9 w-full rounded-md border border-input bg-background px-3 py-1 text-sm"
              />
            </div>
            <div className="space-y-1">
              <Label className="text-sm">Tolerância hora extra (min)</Label>
              <input
                type="number"
                min={0}
                max={30}
                value={form.tolerancia_hora_extra}
                onChange={(e) => setForm((f) => ({ ...f, tolerancia_hora_extra: Number(e.target.value) }))}
                className="flex h-9 w-full rounded-md border border-input bg-background px-3 py-1 text-sm"
              />
            </div>
          </div>

          <div className="flex items-center justify-between p-3 rounded-lg bg-muted/50">
            <div>
              <Label className="text-sm font-medium">Permitir registro fora do horário</Label>
              <p className="text-xs text-muted-foreground">Permitir marcação fora da janela de tolerância</p>
            </div>
            <Switch
              checked={form.permitir_registro_fora_horario}
              onCheckedChange={(v) => setForm((f) => ({ ...f, permitir_registro_fora_horario: v }))}
            />
          </div>
        </CardContent>
      </Card>

      {/* Justificativas */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-base">
            <FileText className="w-5 h-5 text-primary" /> Justificativas e Abonos
          </CardTitle>
          <CardDescription>Gerencie os motivos que os colaboradores podem usar para justificar ausências ou ajustes.</CardDescription>
        </CardHeader>
        <CardContent>
          <Button 
            variant="outline" 
            className="w-full sm:w-auto gap-2"
            onClick={() => setShowJustificativasModal(true)}
          >
            <FileText className="w-4 h-4" />
            Configurar Justificativas
          </Button>
        </CardContent>
      </Card>

      <ConfigJustificativasModal 
        open={showJustificativasModal} 
        onOpenChange={setShowJustificativasModal} 
      />

      {/* Feriados (RN02 da equalização mensal): nacionais padrão + locais do RH */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-base">
            <CalendarDays className="w-4 h-4" /> Feriados
          </CardTitle>
          <CardDescription>
            Feriados nacionais fixos já vêm cadastrados. Cadastre aqui os móveis
            (Sexta-feira Santa, Corpus Christi, Carnaval) e os estaduais/municipais
            da sua região. Apenas feriados (não pontos facultativos) são deduzidos
            do cálculo da equalização mensal.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="flex flex-wrap items-end gap-2">
            <div>
              <Label className="text-xs">Data</Label>
              <Input type="date" className="h-8 w-[150px]" value={novoFeriado.data}
                onChange={(e) => setNovoFeriado((p) => ({ ...p, data: e.target.value }))} />
            </div>
            <div className="flex-1 min-w-[180px]">
              <Label className="text-xs">Nome</Label>
              <Input className="h-8" placeholder="Ex.: Padroeira do município" value={novoFeriado.nome}
                onChange={(e) => setNovoFeriado((p) => ({ ...p, nome: e.target.value }))} />
            </div>
            <div>
              <Label className="text-xs">Âmbito</Label>
              <select
                className="h-8 rounded-md border bg-background px-2 text-sm block"
                value={novoFeriado.abrangencia}
                onChange={(e) => setNovoFeriado((p) => ({ ...p, abrangencia: e.target.value as any }))}
              >
                <option value="nacional">Nacional</option>
                <option value="estadual">Estadual</option>
                <option value="municipal">Municipal</option>
              </select>
            </div>
            {novoFeriado.abrangencia !== "nacional" && (
              <div>
                <Label className="text-xs">UF</Label>
                <Input className="h-8 w-[70px]" placeholder="PR" maxLength={2} value={novoFeriado.uf}
                  onChange={(e) => setNovoFeriado((p) => ({ ...p, uf: e.target.value.toUpperCase() }))} />
              </div>
            )}
            {novoFeriado.abrangencia === "municipal" && (
              <div>
                <Label className="text-xs">Município</Label>
                <Input className="h-8 w-[160px]" placeholder="Maringá" value={novoFeriado.municipio}
                  onChange={(e) => setNovoFeriado((p) => ({ ...p, municipio: e.target.value }))} />
              </div>
            )}
            <Button size="sm" className="h-8"
              disabled={!novoFeriado.data || !novoFeriado.nome.trim() || criarFeriado.isPending}
              onClick={() => criarFeriado.mutate(
                {
                  data: novoFeriado.data,
                  nome: novoFeriado.nome,
                  abrangencia: novoFeriado.abrangencia,
                  uf: novoFeriado.uf || null,
                  municipio: novoFeriado.municipio || null,
                },
                { onSuccess: () => setNovoFeriado({ data: "", nome: "", abrangencia: "nacional", uf: "", municipio: "" }) }
              )}
            >
              {criarFeriado.isPending ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : "Adicionar"}
            </Button>
          </div>

          <div className="max-h-56 overflow-y-auto divide-y rounded-md border">
            {feriados.length === 0 && (
              <p className="text-xs text-muted-foreground p-3">Nenhum feriado cadastrado.</p>
            )}
            {feriados.map((f) => (
              <div key={f.id} className="flex items-center justify-between gap-2 px-3 py-1.5 text-sm">
                <span className="font-mono text-xs w-[80px] shrink-0">
                  {String(f.data).split("-").reverse().join("/")}
                </span>
                <span className="flex-1 truncate">{f.nome}</span>
                <Badge variant="outline" className="text-[10px]">
                  {f.abrangencia === "nacional" ? "Nacional" : f.abrangencia === "estadual" ? `Estadual${f.uf ? ` · ${f.uf}` : ""}` : `Municipal${f.municipio ? ` · ${f.municipio}` : ""}`}
                </Badge>
                {f.tipo === "facultativo" && (
                  <Badge variant="secondary" className="text-[10px]">Facultativo</Badge>
                )}
                {f.tenant_id === null ? (
                  <Badge variant="secondary" className="text-[10px]">Padrão</Badge>
                ) : (
                  <Button variant="ghost" size="sm" className="h-6 w-6 p-0 text-destructive"
                    onClick={() => excluirFeriado.mutate(f.id)} title="Remover">
                    ×
                  </Button>
                )}
              </div>
            ))}
          </div>
        </CardContent>
      </Card>

      {/* Save */}
      <div className="flex justify-end">
        <Button onClick={() => salvar.mutate()} disabled={salvar.isPending} className="min-w-[160px]">
          {salvar.isPending ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <Save className="w-4 h-4 mr-2" />}
          Salvar Configurações
        </Button>
      </div>
    </motion.div>
  );
}
