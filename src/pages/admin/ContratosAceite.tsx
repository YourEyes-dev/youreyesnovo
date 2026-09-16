import { useState } from "react";
import { useNavigate } from "react-router-dom";
import {
  ArrowLeft, Plus, FileSignature, Copy, Eye, Edit, Trash2, Link as LinkIcon,
  Power, Search, Shield, Download, MapPin, Hash, Smartphone, Printer,
} from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { Switch } from "@/components/ui/switch";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from "@/components/ui/table";
import {
  Tabs, TabsContent, TabsList, TabsTrigger,
} from "@/components/ui/tabs";
import { confirm } from "@/components/ui/confirm-dialog";
import { toast } from "sonner";
import { format } from "date-fns";
import { ptBR } from "date-fns/locale";
import {
  useContratosAceite,
  useAssinaturasContrato,
  useGerarLinkAssinatura,
  type ContratoAceite,
  type ContratoAssinatura,
  type ContratoCategoria,
} from "@/hooks/useContratosAceite";

const CATEGORIAS: { value: ContratoCategoria; label: string }[] = [
  { value: "live", label: "LIVE / Webinar" },
  { value: "aula", label: "Aula / Curso" },
  { value: "uso_sistema", label: "Uso do Sistema" },
  { value: "parceria", label: "Parceria" },
  { value: "nda", label: "NDA / Sigilo" },
  { value: "evento", label: "Evento" },
  { value: "outro", label: "Outro" },
];

const PUBLIC_BASE = "https://www.youreyes.com.br";

// Converte texto plano em HTML formatado automaticamente
function textoParaHtml(texto: string): string {
  if (!texto.trim()) return "";
  // Se já parece HTML, retorna como está
  if (/<(p|div|h[1-6]|ul|ol|li|strong|em|br)[\s>]/i.test(texto)) return texto;

  const escape = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const inline = (s: string) =>
    escape(s)
      .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
      .replace(/__(.+?)__/g, "<strong>$1</strong>")
      .replace(/\*(.+?)\*/g, "<em>$1</em>");

  const blocos = texto.replace(/\r\n/g, "\n").split(/\n{2,}/);
  const html: string[] = [];

  for (const bloco of blocos) {
    const linhas = bloco.split("\n").map(l => l.trim()).filter(Boolean);
    if (!linhas.length) continue;

    // Heading markdown: # Título
    const h = linhas[0].match(/^(#{1,3})\s+(.+)$/);
    if (h && linhas.length === 1) {
      const lvl = h[1].length + 1; // # -> h2
      html.push(`<h${lvl}>${inline(h[2])}</h${lvl}>`);
      continue;
    }

    // Cláusula / título em CAPS curto
    if (linhas.length === 1 && linhas[0].length < 80 && linhas[0] === linhas[0].toUpperCase() && /[A-ZÀ-Ý]/.test(linhas[0])) {
      html.push(`<h3 style="margin-top:1.5em">${inline(linhas[0])}</h3>`);
      continue;
    }

    // Lista numerada (1. / 1) / a))
    if (linhas.every(l => /^(\d+[\.\)]|[a-z][\.\)])\s+/i.test(l))) {
      html.push("<ol>" + linhas.map(l => `<li>${inline(l.replace(/^(\d+[\.\)]|[a-z][\.\)])\s+/i, ""))}</li>`).join("") + "</ol>");
      continue;
    }

    // Lista com marcadores
    if (linhas.every(l => /^[-•*]\s+/.test(l))) {
      html.push("<ul>" + linhas.map(l => `<li>${inline(l.replace(/^[-•*]\s+/, ""))}</li>`).join("") + "</ul>");
      continue;
    }

    // Parágrafo normal (quebras de linha viram <br>)
    html.push(`<p>${linhas.map(inline).join("<br>")}</p>`);
  }

  return html.join("\n");
}

function emptyContrato(): Partial<ContratoAceite> {
  return {
    titulo: "",
    categoria: "live",
    descricao_publica: "",
    corpo_html: "",
    requer_cpf: true,
    requer_rg: false,
    requer_endereco: false,
    requer_telefone: false,
    requer_selfie: false,
    requer_geolocalizacao: false,
    requer_cnpj: false,
    requer_razao_social: false,
    requer_representante: false,
    validade_dias: 30,
    limite_assinaturas: null,
    ativo: true,
  };
}

export default function ContratosAceite() {
  const navigate = useNavigate();
  const { data: contratos, isLoading, createContrato, updateContrato, deleteContrato } = useContratosAceite();


  const [search, setSearch] = useState("");
  const [editorOpen, setEditorOpen] = useState(false);
  const [editing, setEditing] = useState<Partial<ContratoAceite> | null>(null);
  const [assinaturasOpen, setAssinaturasOpen] = useState(false);
  const [contratoAtivo, setContratoAtivo] = useState<ContratoAceite | null>(null);

  const filtered = (contratos || []).filter(c =>
    c.titulo.toLowerCase().includes(search.toLowerCase())
  );

  const handleSave = async () => {
    if (!editing?.titulo || !editing?.corpo_html) {
      toast.error("Título e corpo do contrato são obrigatórios");
      return;
    }
    // Converte texto plano em HTML automaticamente ao salvar
    const payload = { ...editing, corpo_html: textoParaHtml(editing.corpo_html) };
    if (editing.id) {
      await updateContrato.mutateAsync(payload as ContratoAceite);
    } else {
      await createContrato.mutateAsync(payload);
    }
    setEditorOpen(false);
    setEditing(null);
  };

  const handleDelete = async (c: ContratoAceite) => {
    const ok = await confirm({
      title: "Excluir contrato?",
      description: `O contrato "${c.titulo}" e todas as assinaturas associadas serão removidos.`,
      confirmLabel: "Excluir",
      variant: "destructive",
    });
    if (ok) deleteContrato.mutate(c.id);
  };

  return (
    <div className="min-h-screen bg-background p-4 md:p-6">
      <div className="max-w-[1400px] mx-auto space-y-6">
        <div className="flex items-center justify-between gap-4 flex-wrap">
          <div className="flex items-center gap-4">
            <Button variant="ghost" size="icon" onClick={() => navigate("/admin")}>
              <ArrowLeft className="w-5 h-5" />
            </Button>
            <div>
              <h1 className="text-2xl font-bold flex items-center gap-2">
                <FileSignature className="w-6 h-6 text-primary" />
                Contratos & Termos de Aceite
              </h1>
              <p className="text-sm text-muted-foreground mt-1">
                Crie contratos, gere links de assinatura e gerencie aceites com validade jurídica
              </p>
            </div>
          </div>
          <Button onClick={() => { setEditing(emptyContrato()); setEditorOpen(true); }}>
            <Plus className="w-4 h-4 mr-2" />Novo Contrato
          </Button>
        </div>

        <Card className="bg-primary/5 border-primary/20">
          <CardContent className="pt-6 flex gap-3">
            <Shield className="w-5 h-5 text-primary mt-0.5 shrink-0" />
            <div className="text-sm">
              <strong>Validade jurídica:</strong> Toda assinatura é registrada com IP, geolocalização (se exigida),
              selfie (se exigida), hash SHA-256 do documento e carimbo de tempo — conforme{" "}
              <strong>Lei 14.063/2020</strong> e <strong>MP 2.200-2/2001</strong>.
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between">
            <CardTitle>Contratos Cadastrados</CardTitle>
            <div className="relative w-64">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
              <Input placeholder="Buscar..." value={search} onChange={e => setSearch(e.target.value)} className="pl-9" />
            </div>
          </CardHeader>
          <CardContent>
            {isLoading ? (
              <div className="text-center py-8 text-muted-foreground">Carregando...</div>
            ) : filtered.length === 0 ? (
              <div className="text-center py-12 text-muted-foreground">
                <FileSignature className="w-12 h-12 mx-auto mb-3 opacity-30" />
                Nenhum contrato cadastrado ainda
              </div>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Título</TableHead>
                    <TableHead>Categoria</TableHead>
                    <TableHead>Validade</TableHead>
                    <TableHead>Limite</TableHead>
                    <TableHead>Status</TableHead>
                    <TableHead>Criado</TableHead>
                    <TableHead className="text-right">Ações</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {filtered.map(c => (
                    <TableRow key={c.id}>
                      <TableCell className="font-medium">{c.titulo}</TableCell>
                      <TableCell><Badge variant="outline">{CATEGORIAS.find(x => x.value === c.categoria)?.label || c.categoria}</Badge></TableCell>
                      <TableCell>{c.validade_dias ? `${c.validade_dias} dias` : "—"}</TableCell>
                      <TableCell>{c.limite_assinaturas ?? "Ilimitado"}</TableCell>
                      <TableCell>
                        {c.ativo
                          ? <Badge className="bg-emerald-500/10 text-emerald-600 border-emerald-500/20">Ativo</Badge>
                          : <Badge variant="destructive">Inativo</Badge>}
                      </TableCell>
                      <TableCell className="text-xs">{format(new Date(c.created_at), "dd/MM/yy", { locale: ptBR })}</TableCell>
                      <TableCell className="text-right">
                        <div className="flex gap-1 justify-end">
                          <Button size="icon" variant="ghost" title="Ver assinaturas"
                            onClick={() => { setContratoAtivo(c); setAssinaturasOpen(true); }}>
                            <Eye className="w-4 h-4" />
                          </Button>
                          <Button size="icon" variant="ghost" title="Editar"
                            onClick={() => { setEditing(c); setEditorOpen(true); }}>
                            <Edit className="w-4 h-4" />
                          </Button>
                          <Button size="icon" variant="ghost" title={c.ativo ? "Desativar" : "Ativar"}
                            onClick={() => updateContrato.mutate({ id: c.id, ativo: !c.ativo })}>
                            <Power className="w-4 h-4" />
                          </Button>
                          <Button size="icon" variant="ghost" title="Excluir" onClick={() => handleDelete(c)}>
                            <Trash2 className="w-4 h-4 text-destructive" />
                          </Button>
                        </div>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Editor */}
      <Dialog open={editorOpen} onOpenChange={setEditorOpen}>
        <DialogContent className="max-w-3xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{editing?.id ? "Editar Contrato" : "Novo Contrato"}</DialogTitle>
            <DialogDescription>Cadastre o termo que será apresentado ao signatário</DialogDescription>
          </DialogHeader>
          {editing && (
            <div className="space-y-4">
              <div className="grid md:grid-cols-2 gap-4">
                <div className="md:col-span-2">
                  <Label>Título *</Label>
                  <Input value={editing.titulo || ""} onChange={e => setEditing({ ...editing, titulo: e.target.value })} />
                </div>
                <div>
                  <Label>Categoria</Label>
                  <Select value={editing.categoria} onValueChange={(v: ContratoCategoria) => setEditing({ ...editing, categoria: v })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      {CATEGORIAS.map(c => <SelectItem key={c.value} value={c.value}>{c.label}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
                <div>
                  <Label>Validade do link (dias)</Label>
                  <Input type="number" value={editing.validade_dias ?? ""} onChange={e =>
                    setEditing({ ...editing, validade_dias: e.target.value ? Number(e.target.value) : null })} />
                </div>
                <div>
                  <Label>Limite de assinaturas (vazio = ilimitado)</Label>
                  <Input type="number" value={editing.limite_assinaturas ?? ""} onChange={e =>
                    setEditing({ ...editing, limite_assinaturas: e.target.value ? Number(e.target.value) : null })} />
                </div>
                <div className="flex items-center gap-2">
                  <Switch checked={editing.ativo} onCheckedChange={v => setEditing({ ...editing, ativo: v })} />
                  <Label>Contrato ativo</Label>
                </div>
              </div>

              <div>
                <Label>Descrição pública (mostrada ao signatário antes do contrato)</Label>
                <Textarea rows={2} value={editing.descricao_publica || ""}
                  onChange={e => setEditing({ ...editing, descricao_publica: e.target.value })} />
              </div>

              <div>
                <div className="flex items-center justify-between mb-1">
                  <Label>Corpo do contrato *</Label>
                  <p className="text-[11px] text-muted-foreground">
                    Cole o texto puro do contrato — o sistema formata automaticamente. Suporta também HTML se preferir.
                  </p>
                </div>
                <Tabs defaultValue="texto" className="w-full">
                  <TabsList className="h-8">
                    <TabsTrigger value="texto" className="text-xs h-7">Editor</TabsTrigger>
                    <TabsTrigger value="preview" className="text-xs h-7">Pré-visualização</TabsTrigger>
                  </TabsList>
                  <TabsContent value="texto" className="mt-2">
                    <Textarea
                      rows={14}
                      className="text-sm"
                      value={editing.corpo_html || ""}
                      onChange={e => setEditing({ ...editing, corpo_html: e.target.value })}
                      placeholder={`Cole aqui o seu contrato em texto puro. Exemplo:\n\nCONTRATO DE PRESTAÇÃO DE SERVIÇOS\n\n# Cláusula 1 - Objeto\n\nO presente contrato tem por objeto...\n\n- Item de lista\n- Outro item\n\n1. Cláusula numerada\n2. Outra cláusula\n\nUse **negrito** e *itálico* quando precisar.`}
                    />
                    <p className="text-[11px] text-muted-foreground mt-1">
                      💡 Dicas: linhas em <strong>CAIXA ALTA</strong> viram títulos · linhas começando com <code>-</code> viram lista · use <code>**negrito**</code> e <code>*itálico*</code> · linhas em branco separam parágrafos.
                    </p>
                  </TabsContent>
                  <TabsContent value="preview" className="mt-2">
                    <div
                      className="prose prose-sm max-w-none border rounded-md p-4 min-h-[280px] bg-card"
                      dangerouslySetInnerHTML={{ __html: textoParaHtml(editing.corpo_html || "") || "<p class='text-muted-foreground'>Nada para visualizar ainda.</p>" }}
                    />
                  </TabsContent>
                </Tabs>
              </div>

              <div className="space-y-2 border rounded-lg p-4">
                <Label className="font-semibold">Dados exigidos do signatário</Label>
                <div className="grid grid-cols-2 gap-2 text-sm">
                  {[
                    { k: "requer_cpf", l: "CPF" },
                    { k: "requer_rg", l: "RG" },
                    { k: "requer_telefone", l: "Telefone" },
                    { k: "requer_endereco", l: "Endereço completo" },
                    { k: "requer_selfie", l: "Selfie (foto ao vivo)" },
                    { k: "requer_geolocalizacao", l: "Geolocalização" },
                    { k: "requer_cnpj", l: "CNPJ" },
                    { k: "requer_razao_social", l: "Razão Social" },
                    { k: "requer_representante", l: "Representante Legal" },
                  ].map(f => (
                    <div key={f.k} className="flex items-center gap-2">
                      <Switch
                        checked={(editing as any)[f.k]}
                        onCheckedChange={v => setEditing({ ...editing, [f.k]: v })}
                      />
                      <Label>{f.l}</Label>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => setEditorOpen(false)}>Cancelar</Button>
            <Button onClick={handleSave}>{editing?.id ? "Salvar" : "Criar contrato"}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Painel de assinaturas */}
      <Dialog open={assinaturasOpen} onOpenChange={setAssinaturasOpen}>
        <DialogContent className="max-w-5xl max-h-[90vh] overflow-y-auto">
          {contratoAtivo && (
            <AssinaturasPainel contrato={contratoAtivo} />
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}

function AssinaturasPainel({ contrato }: { contrato: ContratoAceite }) {
  const { data: assinaturas, isLoading, refetch } = useAssinaturasContrato(contrato.id);
  const gerarLink = useGerarLinkAssinatura();
  const [novoEmail, setNovoEmail] = useState("");
  const [novoNome, setNovoNome] = useState("");
  const [detalhe, setDetalhe] = useState<ContratoAssinatura | null>(null);

  const copyLink = (token: string) => {
    const url = `${PUBLIC_BASE}/assinar-contrato/${token}`;
    navigator.clipboard.writeText(url);
    toast.success("Link copiado!");
  };

  const handleGerar = async () => {
    const a = await gerarLink.mutateAsync({
      contrato_id: contrato.id,
      validade_dias: contrato.validade_dias,
      signatario_email: novoEmail || undefined,
      signatario_nome: novoNome || undefined,
    });
    const url = `${PUBLIC_BASE}/assinar-contrato/${a.token}`;
    navigator.clipboard.writeText(url);
    toast.success("Link gerado e copiado para a área de transferência!");
    setNovoEmail(""); setNovoNome("");
    refetch();
  };

  return (
    <div className="space-y-4">
      <DialogHeader>
        <DialogTitle className="flex items-center gap-2">
          <FileSignature className="w-5 h-5" />
          {contrato.titulo}
        </DialogTitle>
        <DialogDescription>
          Gerar links de assinatura e acompanhar aceites
        </DialogDescription>
      </DialogHeader>

      <Tabs defaultValue="gerar">
        <TabsList>
          <TabsTrigger value="gerar">Gerar Link</TabsTrigger>
          <TabsTrigger value="assinaturas">
            Assinaturas ({assinaturas?.length || 0})
          </TabsTrigger>
        </TabsList>

        <TabsContent value="gerar" className="space-y-4">
          <Card>
            <CardContent className="pt-6 space-y-4">
              <div className="grid md:grid-cols-2 gap-3">
                <div>
                  <Label>Nome do signatário (opcional)</Label>
                  <Input value={novoNome} onChange={e => setNovoNome(e.target.value)} placeholder="João Silva" />
                </div>
                <div>
                  <Label>E-mail (opcional)</Label>
                  <Input type="email" value={novoEmail} onChange={e => setNovoEmail(e.target.value)} placeholder="joao@empresa.com" />
                </div>
              </div>
              <p className="text-xs text-muted-foreground">
                Você pode gerar um link sem signatário definido (genérico) ou pré-vincular a uma pessoa.
                {contrato.validade_dias && ` O link expira em ${contrato.validade_dias} dias.`}
              </p>
              <Button onClick={handleGerar} disabled={gerarLink.isPending} className="w-full">
                <LinkIcon className="w-4 h-4 mr-2" />
                {gerarLink.isPending ? "Gerando..." : "Gerar link de assinatura"}
              </Button>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="assinaturas">
          {isLoading ? (
            <div className="text-center py-8 text-muted-foreground">Carregando...</div>
          ) : !assinaturas?.length ? (
            <div className="text-center py-12 text-muted-foreground">
              Nenhuma assinatura gerada ainda
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Signatário</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Assinado em</TableHead>
                  <TableHead>IP</TableHead>
                  <TableHead className="text-right">Ações</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {assinaturas.map(a => (
                  <TableRow key={a.id}>
                    <TableCell>
                      <div className="font-medium text-sm">{a.signatario_nome || "—"}</div>
                      <div className="text-xs text-muted-foreground">{a.signatario_email || a.signatario_cpf || "Sem identificação"}</div>
                    </TableCell>
                    <TableCell>
                      <Badge variant={
                        a.status === "assinado" ? "default" :
                        a.status === "expirado" ? "destructive" :
                        a.status === "revogado" ? "destructive" : "outline"
                      } className={a.status === "assinado" ? "bg-emerald-500/10 text-emerald-600 border-emerald-500/20" : ""}>
                        {a.status}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-xs">
                      {a.assinado_em ? format(new Date(a.assinado_em), "dd/MM/yy HH:mm", { locale: ptBR }) : "—"}
                    </TableCell>
                    <TableCell className="text-xs">{a.ip_address || "—"}</TableCell>
                    <TableCell className="text-right">
                      <div className="flex gap-1 justify-end">
                        {a.status === "assinado" && (
                          <Button size="sm" variant="ghost" onClick={() => setDetalhe(a)} title="Ver assinatura">
                            <Eye className="w-3 h-3 mr-1" />Ver
                          </Button>
                        )}
                        {a.status === "pendente" && (
                          <Button size="sm" variant="ghost" onClick={() => copyLink(a.token)}>
                            <Copy className="w-3 h-3 mr-1" />Copiar link
                          </Button>
                        )}
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </TabsContent>
      </Tabs>

      <DetalheAssinaturaModal
        contrato={contrato}
        assinatura={detalhe}
        onClose={() => setDetalhe(null)}
      />
    </div>
  );
}

function DetalheAssinaturaModal({
  contrato,
  assinatura,
  onClose,
}: {
  contrato: ContratoAceite;
  assinatura: ContratoAssinatura | null;
  onClose: () => void;
}) {
  const open = !!assinatura;

  const imprimir = () => {
    if (!assinatura) return;
    const w = window.open("", "_blank", "width=900,height=900");
    if (!w) { toast.error("Permita pop-ups para imprimir"); return; }
    const dataAss = assinatura.assinado_em
      ? format(new Date(assinatura.assinado_em), "dd/MM/yyyy HH:mm:ss", { locale: ptBR })
      : "—";
    w.document.write(`<!DOCTYPE html><html><head><meta charset="utf-8"><title>${contrato.titulo}</title>
      <style>
        body{font-family:system-ui,-apple-system,sans-serif;max-width:780px;margin:24px auto;padding:0 24px;color:#111;}
        h1{font-size:20px;border-bottom:2px solid #0a0a0a;padding-bottom:8px;margin-bottom:16px;}
        h2{font-size:14px;text-transform:uppercase;letter-spacing:0.05em;color:#444;margin-top:24px;border-bottom:1px solid #ddd;padding-bottom:4px;}
        .row{display:flex;gap:24px;margin:6px 0;font-size:13px;}
        .row b{min-width:140px;color:#555;font-weight:600;}
        .corpo{font-size:13px;line-height:1.6;border:1px solid #eee;padding:16px;border-radius:6px;background:#fafafa;}
        .corpo.gerado{border:0;padding:0;background:#fff;}
        .sig-box{display:flex;gap:24px;margin-top:24px;flex-wrap:wrap;}
        .sig-box > div{flex:1;min-width:240px;}
        .sig-box img{max-width:100%;border:1px solid #ccc;background:#fff;border-radius:4px;}
        .hash{font-family:ui-monospace,monospace;font-size:10px;word-break:break-all;background:#f3f3f3;padding:6px;border-radius:4px;}
        .legal{margin-top:24px;font-size:11px;color:#666;border-top:1px solid #ddd;padding-top:12px;}
      </style></head><body>
      <h1>${contrato.titulo}</h1>
      <h2>Conteúdo do contrato (versão ${contrato.versao})</h2>
      <div class="corpo${assinatura.html_assinado ? " gerado" : ""}">${assinatura.html_assinado || contrato.corpo_html}</div>
      <h2>Dados do signatário</h2>
      <div class="row"><b>Nome:</b> ${assinatura.signatario_nome || "—"}</div>
      <div class="row"><b>CPF:</b> ${assinatura.signatario_cpf || "—"}</div>
      <div class="row"><b>RG:</b> ${assinatura.signatario_rg || "—"}</div>
      <div class="row"><b>E-mail:</b> ${assinatura.signatario_email || "—"}</div>
      <div class="row"><b>Telefone:</b> ${assinatura.signatario_telefone || "—"}</div>
      <div class="row"><b>Endereço:</b> ${assinatura.signatario_endereco || "—"}</div>
      <h2>Evidências de autoria</h2>
      <div class="row"><b>Assinado em:</b> ${dataAss}</div>
      <div class="row"><b>IP:</b> ${assinatura.ip_address || "—"}</div>
      <div class="row"><b>Geolocalização:</b> ${assinatura.geo_lat ? `${assinatura.geo_lat}, ${assinatura.geo_lng}` : "—"}</div>
      <div class="row"><b>Dispositivo:</b> <span style="font-size:11px">${assinatura.user_agent || "—"}</span></div>
      <div class="row"><b>Hash SHA-256:</b></div>
      <div class="hash">${assinatura.hash_documento || "—"}</div>
      <div class="sig-box">
        ${assinatura.assinatura_imagem ? `<div><b>Assinatura</b><br/><img src="${assinatura.assinatura_imagem}"/></div>` : ""}
        ${assinatura.selfie_imagem ? `<div><b>Selfie de verificação</b><br/><img src="${assinatura.selfie_imagem}"/></div>` : ""}
      </div>
      <div class="legal">
        Documento assinado eletronicamente conforme <b>Lei 14.063/2020</b> (assinatura eletrônica avançada)
        e <b>MP 2.200-2/2001</b>, art. 10, §2º. Autoria e integridade comprovadas pelo hash criptográfico,
        IP, dispositivo, data/hora e dados pessoais do signatário registrados neste documento.
      </div>
      <script>window.onload=()=>setTimeout(()=>window.print(),300);</script>
      </body></html>`);
    w.document.close();
  };

  if (!assinatura) return null;

  return (
    <Dialog open={open} onOpenChange={v => !v && onClose()}>
      <DialogContent className="max-w-3xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Shield className="w-5 h-5 text-emerald-600" />
            Contrato Assinado
          </DialogTitle>
          <DialogDescription>{contrato.titulo}</DialogDescription>
        </DialogHeader>

        <div className="space-y-5">
          <Card>
            <CardHeader className="pb-2"><CardTitle className="text-sm">Dados do signatário</CardTitle></CardHeader>
            <CardContent className="grid md:grid-cols-2 gap-x-6 gap-y-2 text-sm">
              <Campo label="Nome" value={assinatura.signatario_nome} />
              <Campo label="CPF" value={assinatura.signatario_cpf} />
              <Campo label="RG" value={assinatura.signatario_rg} />
              <Campo label="E-mail" value={assinatura.signatario_email} />
              <Campo label="Telefone" value={assinatura.signatario_telefone} />
              <Campo label="Endereço" value={assinatura.signatario_endereco} className="md:col-span-2" />
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="pb-2"><CardTitle className="text-sm">Evidências de autoria</CardTitle></CardHeader>
            <CardContent className="space-y-2 text-sm">
              <Campo
                label="Assinado em"
                value={assinatura.assinado_em ? format(new Date(assinatura.assinado_em), "dd/MM/yyyy HH:mm:ss", { locale: ptBR }) : null}
              />
              <Campo label="IP" value={assinatura.ip_address} icon={<MapPin className="w-3 h-3" />} />
              <Campo
                label="Geolocalização"
                value={assinatura.geo_lat ? `${assinatura.geo_lat}, ${assinatura.geo_lng}` : null}
                icon={<MapPin className="w-3 h-3" />}
              />
              <Campo
                label="Dispositivo"
                value={assinatura.user_agent}
                icon={<Smartphone className="w-3 h-3" />}
                small
              />
              <div>
                <div className="text-xs text-muted-foreground flex items-center gap-1 mb-1">
                  <Hash className="w-3 h-3" /> Hash SHA-256
                </div>
                <code className="block text-[10px] bg-muted p-2 rounded font-mono break-all">
                  {assinatura.hash_documento || "—"}
                </code>
              </div>
            </CardContent>
          </Card>

          <div className="grid md:grid-cols-2 gap-4">
            {assinatura.assinatura_imagem && (
              <Card>
                <CardHeader className="pb-2"><CardTitle className="text-sm">Assinatura</CardTitle></CardHeader>
                <CardContent>
                  <img
                    src={assinatura.assinatura_imagem}
                    alt="Assinatura"
                    className="w-full border rounded bg-white"
                  />
                </CardContent>
              </Card>
            )}
            {assinatura.selfie_imagem && (
              <Card>
                <CardHeader className="pb-2"><CardTitle className="text-sm">Selfie de verificação</CardTitle></CardHeader>
                <CardContent>
                  <img
                    src={assinatura.selfie_imagem}
                    alt="Selfie"
                    className="w-full rounded border object-cover"
                  />
                </CardContent>
              </Card>
            )}
          </div>

          <Card>
            <CardHeader className="pb-2"><CardTitle className="text-sm">{assinatura.html_assinado ? `Contrato gerado para o signatário (v${contrato.versao})` : `Conteúdo do contrato (v${contrato.versao})`}</CardTitle></CardHeader>
            <CardContent>
              <div
                className={assinatura.html_assinado ? "max-h-[420px] overflow-y-auto border rounded bg-white" : "prose prose-sm max-w-none max-h-[300px] overflow-y-auto border rounded p-3 bg-muted/30"}
                dangerouslySetInnerHTML={{ __html: assinatura.html_assinado || contrato.corpo_html }}
              />
            </CardContent>
          </Card>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Fechar</Button>
          <Button onClick={imprimir}>
            <Printer className="w-4 h-4 mr-2" />Imprimir / Salvar PDF
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function Campo({
  label, value, icon, small, className,
}: { label: string; value: string | null; icon?: React.ReactNode; small?: boolean; className?: string }) {
  return (
    <div className={className}>
      <div className="text-xs text-muted-foreground flex items-center gap-1">{icon}{label}</div>
      <div className={small ? "text-xs break-all" : "text-sm font-medium"}>{value || "—"}</div>
    </div>
  );
}

