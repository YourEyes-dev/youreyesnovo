import { useState } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Checkbox } from "@/components/ui/checkbox";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Shield, UserPlus } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { geocodeCidade } from "@/lib/nominatim";
import { DocumentUploadSection, DOC_CATEGORIES, type UploadedDoc } from "./DocumentUploadSection";
import { SelfieCapture } from "./SelfieCapture";
import { ProfilePhotoUpload } from "./ProfilePhotoUpload";
import { BUCKET_DOCS, BUCKET_FOTOS, caminhoDaFoto, caminhoDoDocumento } from "@/lib/marketyeAnexos";

const CONSELHOS = [
  "CREA", "CRP", "CREFITO", "CRM", "CRN", "CREF", "OAB", "CRA", "COREN", "CONFEA", "Outro"
];

const UFS = [
  "AC","AL","AP","AM","BA","CE","DF","ES","GO","MA","MT","MS","MG","PA",
  "PB","PR","PE","PI","RJ","RN","RS","RO","RR","SC","SP","SE","TO"
];

interface ProfissionalFormModalProps {
  open: boolean;
  onClose: () => void;
  onSuccess: () => void;
}

export function ProfissionalFormModal({ open, onClose, onSuccess }: ProfissionalFormModalProps) {
  const [isLoading, setIsLoading] = useState(false);
  const [documents, setDocuments] = useState<UploadedDoc[]>([]);
  const [selfieFile, setSelfieFile] = useState<File | null>(null);
  const [selfiePreview, setSelfiePreview] = useState<string | null>(null);
  const [profilePhoto, setProfilePhoto] = useState<File | null>(null);
  const [profilePhotoPreview, setProfilePhotoPreview] = useState<string | null>(null);
  const [form, setForm] = useState({
    nome_completo: "",
    email: "",
    telefone: "",
    cpf_cnpj: "",
    bio: "",
    formacao_academica: "",
    registro_profissional: "",
    conselho: "",
    uf_registro: "",
    registro_validade: "",
    certificacoes: "",
    especialidades: "",
    areas_atuacao: "",
    cidade: "",
    estado: "",
    modalidades: [] as string[],
    aceite_etica: false,
  });

  const updateField = (field: string, value: string | boolean) => {
    setForm((f) => ({ ...f, [field]: value }));
  };

  const toggleModalidade = (mod: string) => {
    setForm((f) => ({
      ...f,
      modalidades: f.modalidades.includes(mod)
        ? f.modalidades.filter((m) => m !== mod)
        : [...f.modalidades, mod],
    }));
  };

  const handleSelfieChange = (file: File | null, preview: string | null) => {
    setSelfieFile(file);
    setSelfiePreview(preview);
  };

  // Sobe cada documento para o bucket privado e registra na tabela. O caminho
  // começa pelo id do ESPECIALISTA (é o que a política de upload confere);
  // antes começava pelo id do usuário e o Storage recusava tudo: o cadastro
  // ficava criado e sem anexos. `arquivo_url` guarda o caminho no bucket; quem
  // exibe (moderação) gera um link assinado na hora.
  const uploadDocuments = async (profissionalId: string) => {
    const allFiles = [...documents.map((d) => ({ file: d.file, categoria: d.categoria }))];
    if (selfieFile) {
      allFiles.push({ file: selfieFile, categoria: "selfie_verificacao" });
    }

    for (const doc of allFiles) {
      const filePath = caminhoDoDocumento(profissionalId, doc.categoria, doc.file.name);
      const { error: uploadError } = await supabase.storage.from(BUCKET_DOCS).upload(filePath, doc.file);
      if (uploadError) throw new Error(`Erro ao enviar ${doc.file.name}: ${uploadError.message}`);

      const { error: registroError } = await supabase.from("marketplace_profissional_documentos").insert({
        profissional_id: profissionalId,
        categoria: doc.categoria,
        nome_arquivo: doc.file.name,
        arquivo_url: filePath,
        tamanho_bytes: doc.file.size,
        mime_type: doc.file.type,
      });
      if (registroError) throw new Error(`Erro ao registrar ${doc.file.name}: ${registroError.message}`);
    }
  };

  const handleSubmit = async () => {
    if (!form.nome_completo || !form.email || !form.cpf_cnpj) {
      toast.error("Preencha nome, e-mail e CPF/CNPJ");
      return;
    }
    if (!form.aceite_etica) {
      toast.error("É necessário aceitar o Código de Ética");
      return;
    }
    if (form.modalidades.length === 0) {
      toast.error("Selecione ao menos uma modalidade de atendimento");
      return;
    }

    // Validate required documents
    const requiredCategories = DOC_CATEGORIES.filter((c) => c.obrigatorio).map((c) => c.id);
    const uploadedCategories = new Set(documents.map((d) => d.categoria));
    const missing = requiredCategories.filter((c) => !uploadedCategories.has(c));
    if (missing.length > 0) {
      toast.error("Envie todos os documentos obrigatórios antes de continuar");
      return;
    }

    if (!selfieFile) {
      toast.error("A selfie de verificação é obrigatória");
      return;
    }
    if (!profilePhoto) {
      toast.error("A foto de perfil é obrigatória");
      return;
    }

    setIsLoading(true);
    try {
      // Geocode city/state via Nominatim
      const geo = await geocodeCidade(form.cidade, form.estado);

      // Cadastro por função do sistema (RN-021): nasce pendente, com consentimento
      // versionado, CPF/CNPJ validado e único. Nada de INSERT direto com status.
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data: cad, error } = await (supabase as any).rpc("marketye_cadastrar_especialista", {
        _dados: {
          nome_completo: form.nome_completo, email: form.email, telefone: form.telefone || null, cpf_cnpj: form.cpf_cnpj,
          bio: form.bio || null, formacao_academica: form.formacao_academica || null, registro_profissional: form.registro_profissional || null,
          conselho: form.conselho || null, uf_registro: form.uf_registro || null, registro_validade: form.registro_validade || null,
          certificacoes: form.certificacoes ? form.certificacoes.split(",").map((s) => s.trim()).filter(Boolean) : [],
          especialidades: form.especialidades ? form.especialidades.split(",").map((s) => s.trim()).filter(Boolean) : [],
          areas_atuacao: form.areas_atuacao ? form.areas_atuacao.split(",").map((s) => s.trim()).filter(Boolean) : [],
          modalidades: form.modalidades, cidade: form.cidade || null, estado: form.estado || null,
          latitude: geo?.lat ?? null, longitude: geo?.lng ?? null, aceite_termos: true, user_agent: navigator.userAgent, origem: "sistema",
        },
      });
      if (error) throw error;
      // Se o cadastro já existia (ex.: uma tentativa anterior criou o perfil
      // mas falhou nos anexos), seguimos em frente: documentos e foto entram
      // agora, sem duplicar o cadastro.
      const jaExistia = Boolean(cad?.ja_existia);
      const profissionalId = String(cad.id);

      try {
        await uploadDocuments(profissionalId);

        // Foto de perfil: bucket público, que é o que a vitrine mostra.
        const photoPath = caminhoDaFoto(profissionalId, profilePhoto.name);
        const { error: photoUpError } = await supabase.storage.from(BUCKET_FOTOS).upload(photoPath, profilePhoto);
        if (photoUpError) throw new Error(`Erro ao enviar foto de perfil: ${photoUpError.message}`);
        const { data: photoUrl } = supabase.storage.from(BUCKET_FOTOS).getPublicUrl(photoPath);
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const { error: fotoError } = await (supabase as any).rpc("marketye_meu_perfil_salvar", { _dados: { foto_url: photoUrl.publicUrl } });
        if (fotoError) throw new Error(`Erro ao guardar a foto de perfil: ${fotoError.message}`);
      } catch (anexoErr) {
        // O perfil já está guardado; o que falhou foi o anexo. Dizer isso com
        // clareza evita um segundo cadastro: basta enviar o formulário de novo.
        const detalhe = anexoErr instanceof Error ? anexoErr.message : "falha ao enviar os anexos";
        throw new Error(`${jaExistia ? "Seu cadastro já estava guardado" : "Seu cadastro foi guardado"}, mas os anexos não subiram (${detalhe}). Envie o formulário de novo para tentar outra vez; o cadastro não será duplicado.`);
      }

      toast.success(jaExistia
        ? "Documentos e foto enviados. Seu cadastro já estava guardado e segue para verificação."
        : "Cadastro enviado para verificação. Você acompanha tudo no seu portal de especialista.");
      onSuccess();
      onClose();
    } catch (err) {
      toast.error(err instanceof Error && err.message ? err.message : "Erro ao cadastrar");
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onClose}>
      <DialogContent className="sm:max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <UserPlus className="h-5 w-5" />
            Cadastro de Especialista — MarketYE
          </DialogTitle>
        </DialogHeader>

        <div className="space-y-6">
          {/* Info banner */}
          <div className="p-3 bg-indigo-50 border border-indigo-200 rounded-xl text-xs text-indigo-800">
            <p className="font-medium mb-1">📌 Validação obrigatória</p>
            <p>Seu perfil passa por verificação de dados antes de aparecer no MarketYE (o selo comunica dados verificados, não garantia de qualidade). Envie documentos comprobatórios e selfie. Registro profissional vencido tira o perfil da vitrine até a regularização.</p>
          </div>

          {/* Foto de Perfil */}
          <ProfilePhotoUpload
            file={profilePhoto}
            preview={profilePhotoPreview}
            onChange={(f, p) => { setProfilePhoto(f); setProfilePhotoPreview(p); }}
          />

          {/* Dados pessoais */}
          <div className="space-y-3">
            <h4 className="font-medium text-sm text-foreground">Dados Pessoais</h4>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label>Nome completo *</Label>
                <Input value={form.nome_completo} onChange={(e) => updateField("nome_completo", e.target.value)} />
              </div>
              <div className="space-y-1.5">
                <Label>E-mail *</Label>
                <Input type="email" value={form.email} onChange={(e) => updateField("email", e.target.value)} />
              </div>
              <div className="space-y-1.5">
                <Label>Telefone</Label>
                <Input value={form.telefone} onChange={(e) => updateField("telefone", e.target.value)} />
              </div>
              <div className="space-y-1.5">
                <Label>CPF/CNPJ *</Label>
                <Input value={form.cpf_cnpj} onChange={(e) => updateField("cpf_cnpj", e.target.value)} />
              </div>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label>Cidade</Label>
                <Input value={form.cidade} onChange={(e) => updateField("cidade", e.target.value)} />
              </div>
              <div className="space-y-1.5">
                <Label>Estado</Label>
                <Select value={form.estado} onValueChange={(v) => updateField("estado", v)}>
                  <SelectTrigger><SelectValue placeholder="Selecione" /></SelectTrigger>
                  <SelectContent>
                    {UFS.map((uf) => <SelectItem key={uf} value={uf}>{uf}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
            </div>
          </div>

          {/* Formação */}
          <div className="space-y-3">
            <h4 className="font-medium text-sm text-foreground">Formação e Registro</h4>
            <div className="space-y-1.5">
              <Label>Formação acadêmica</Label>
              <Input value={form.formacao_academica} onChange={(e) => updateField("formacao_academica", e.target.value)} placeholder="Ex: Fisioterapia - USP" />
            </div>
            <div className="grid grid-cols-3 gap-3">
              <div className="space-y-1.5">
                <Label>Conselho</Label>
                <Select value={form.conselho} onValueChange={(v) => updateField("conselho", v)}>
                  <SelectTrigger><SelectValue placeholder="Selecione" /></SelectTrigger>
                  <SelectContent>
                    {CONSELHOS.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1.5">
                <Label>Nº Registro</Label>
                <Input value={form.registro_profissional} onChange={(e) => updateField("registro_profissional", e.target.value)} />
              </div>
              <div className="space-y-1.5">
                <Label>UF Registro</Label>
                <Select value={form.uf_registro} onValueChange={(v) => updateField("uf_registro", v)}>
                  <SelectTrigger><SelectValue placeholder="UF" /></SelectTrigger>
                  <SelectContent>
                    {UFS.map((uf) => <SelectItem key={uf} value={uf}>{uf}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
            </div>
            <div className="space-y-1.5">
              <Label>Validade do registro</Label>
              <Input type="date" value={form.registro_validade} onChange={(e) => updateField("registro_validade", e.target.value)} />
            </div>
          </div>

          {/* Especialidades */}
          <div className="space-y-3">
            <h4 className="font-medium text-sm text-foreground">Especialidades e Atuação</h4>
            <div className="space-y-1.5">
              <Label>Especialidades (separadas por vírgula)</Label>
              <Input value={form.especialidades} onChange={(e) => updateField("especialidades", e.target.value)} placeholder="Ergonomia, NR-17, Saúde Mental" />
            </div>
            <div className="space-y-1.5">
              <Label>Certificações complementares (separadas por vírgula)</Label>
              <Input value={form.certificacoes} onChange={(e) => updateField("certificacoes", e.target.value)} placeholder="Pós em Ergonomia, Auditor ISO 45001" />
            </div>
            <div className="space-y-1.5">
              <Label>Áreas de atuação legal (separadas por vírgula)</Label>
              <Input value={form.areas_atuacao} onChange={(e) => updateField("areas_atuacao", e.target.value)} placeholder="AEP, AET, Laudo Ergonômico" />
            </div>
            <div className="space-y-1.5">
              <Label>Bio / Apresentação</Label>
              <Textarea value={form.bio} onChange={(e) => updateField("bio", e.target.value)} rows={3} placeholder="Descreva sua experiência e abordagem profissional..." />
            </div>
          </div>

          {/* Modalidades */}
          <div className="space-y-3">
            <h4 className="font-medium text-sm text-foreground">Modalidades de atendimento *</h4>
            <div className="flex gap-3">
              {(["presencial", "online", "hibrido"] as const).map((mod) => (
                <button
                  key={mod}
                  type="button"
                  onClick={() => toggleModalidade(mod)}
                  className={`px-4 py-2 rounded-lg border text-sm font-medium transition-colors ${
                    form.modalidades.includes(mod)
                      ? "bg-primary/10 border-primary/30 text-primary"
                      : "bg-card border-border text-muted-foreground hover:bg-muted"
                  }`}
                >
                  {mod.charAt(0).toUpperCase() + mod.slice(1)}
                </button>
              ))}
            </div>
          </div>

          {/* Documents Upload */}
          <DocumentUploadSection documents={documents} onChange={setDocuments} />

          {/* Selfie Capture */}
          <SelfieCapture
            selfieFile={selfieFile}
            selfiePreview={selfiePreview}
            onChange={handleSelfieChange}
          />

          {/* Código de ética */}
          <div className="p-4 bg-amber-50 border border-amber-200 rounded-xl space-y-3">
            <div className="flex items-start gap-2">
              <Shield className="h-5 w-5 text-amber-600 mt-0.5 shrink-0" />
              <div className="text-sm text-amber-800">
                <p className="font-semibold">Código de Ética e Conduta do YourEyes</p>
                <ul className="list-disc ml-4 mt-2 space-y-1 text-xs">
                  <li>Atuar exclusivamente dentro do escopo legal da profissão</li>
                  <li>Não armazenar conteúdo clínico ou sensível na plataforma</li>
                  <li>Não realizar gravações de atendimentos (vídeo, áudio ou chat)</li>
                  <li>Respeitar sigilo profissional e LGPD</li>
                  <li>Manter registro profissional válido e atualizado</li>
                  <li>Não ofertar serviços fora do escopo de habilitação</li>
                  <li>Confirmar execução de serviços com veracidade</li>
                </ul>
              </div>
            </div>
            <div className="flex items-center gap-2">
              <Checkbox
                id="etica"
                checked={form.aceite_etica}
                onCheckedChange={(v) => updateField("aceite_etica", !!v)}
              />
              <label htmlFor="etica" className="text-xs text-amber-800 font-medium cursor-pointer">
                Li, compreendo e aceito integralmente o Código de Ética e Conduta *
              </label>
            </div>
          </div>

          <Button
            onClick={handleSubmit}
            disabled={isLoading}
            className="w-full bg-gradient-to-r from-indigo-500 to-violet-600 text-white border-0"
          >
            {isLoading ? "Enviando cadastro e documentos..." : "Enviar Cadastro para Validação"}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
