import { useState, useRef } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { toast } from "sonner";
import { Upload, Trash2, ImageIcon, Info } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";

const MAX_FILE_SIZE = 2 * 1024 * 1024; // 2MB
const ACCEPTED_TYPES = ["image/png", "image/jpeg", "image/webp", "image/svg+xml"];
const BUCKET = "empresas-logos";

interface EmpresaLogoTabProps {
  /** Empresa cuja logo é gerida (a que está em edição na tela Empresa). */
  empresaId: string | null;
  /** Logo atual dessa empresa. */
  logoUrl: string | null | undefined;
  /** Avisa a tela-mãe da nova logo (ou null ao remover), sem marcar o formulário como alterado. */
  onChange?: (url: string | null) => void;
}

export function EmpresaLogoTab({ empresaId: empresaAtivaId, logoUrl: logoUrlAtual, onChange }: EmpresaLogoTabProps) {
  const queryClient = useQueryClient();
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = useState(false);

  const logoUrl = logoUrlAtual ?? null;

  const uploadMutation = useMutation({
    mutationFn: async (file: File) => {
      if (!empresaAtivaId) throw new Error("Nenhuma empresa selecionada");

      // Validate
      if (!ACCEPTED_TYPES.includes(file.type)) {
        throw new Error("Formato não suportado. Use PNG, JPG, WebP ou SVG.");
      }
      if (file.size > MAX_FILE_SIZE) {
        throw new Error("Arquivo muito grande. Máximo 2MB.");
      }

      const ext = file.name.split(".").pop()?.toLowerCase() || "png";
      const filePath = `${empresaAtivaId}/logo.${ext}`;

      // Upload to storage
      const { error: uploadError } = await supabase.storage
        .from(BUCKET)
        .upload(filePath, file, { upsert: true });

      if (uploadError) throw uploadError;

      // Get public URL
      const { data: urlData } = supabase.storage
        .from(BUCKET)
        .getPublicUrl(filePath);

      const publicUrl = urlData.publicUrl + `?t=${Date.now()}`;

      // Update empresa_cadastro
      const { error: updateError } = await (supabase as any)
        .from("empresa_cadastro")
        .update({ logo_url: publicUrl })
        .eq("id", empresaAtivaId);

      if (updateError) throw updateError;

      return publicUrl;
    },
    onSuccess: (publicUrl) => {
      toast.success("Logo atualizada com sucesso!");
      onChange?.(publicUrl);
      queryClient.invalidateQueries({ queryKey: ["empresa_cadastro_list_ativa"] });
      queryClient.invalidateQueries({ queryKey: ["empresa_cadastro_list"] });
      queryClient.invalidateQueries({ queryKey: ["empresa_cadastro", empresaAtivaId] });
    },
    onError: (err: any) => {
      toast.error(err.message || "Erro ao enviar logo");
    },
  });

  const removeMutation = useMutation({
    mutationFn: async () => {
      if (!empresaAtivaId) throw new Error("Nenhuma empresa selecionada");

      // List and remove files from storage
      const { data: files } = await supabase.storage
        .from(BUCKET)
        .list(empresaAtivaId);

      if (files?.length) {
        await supabase.storage
          .from(BUCKET)
          .remove(files.map((f) => `${empresaAtivaId}/${f.name}`));
      }

      // Clear logo_url in database
      const { error } = await (supabase as any)
        .from("empresa_cadastro")
        .update({ logo_url: null })
        .eq("id", empresaAtivaId);

      if (error) throw error;
    },
    onSuccess: () => {
      toast.success("Logo removida");
      onChange?.(null);
      queryClient.invalidateQueries({ queryKey: ["empresa_cadastro_list_ativa"] });
      queryClient.invalidateQueries({ queryKey: ["empresa_cadastro_list"] });
      queryClient.invalidateQueries({ queryKey: ["empresa_cadastro", empresaAtivaId] });
    },
    onError: () => {
      toast.error("Erro ao remover logo");
    },
  });

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploading(true);
    uploadMutation.mutate(file, {
      onSettled: () => {
        setUploading(false);
        if (fileInputRef.current) fileInputRef.current.value = "";
      },
    });
  };

  if (!empresaAtivaId) {
    return (
      <Card>
        <CardContent className="py-10 text-center text-muted-foreground">
          Salve o cadastro da empresa para poder enviar a logo.
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-6 max-w-2xl">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <ImageIcon className="w-5 h-5 text-primary" />
            Logo da Empresa
          </CardTitle>
          <CardDescription>
            Personalize o sistema com a identidade visual da empresa.
            A logo será utilizada em todos os documentos gerados (PDF, relatórios, laudos).
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-6">
          {/* Preview */}
          <div className="flex items-center gap-6">
            <div className="w-40 h-40 rounded-xl border-2 border-dashed border-border bg-muted/30 flex items-center justify-center overflow-hidden shrink-0">
              {logoUrl ? (
                <img
                  src={logoUrl}
                  alt="Logo da empresa"
                  className="w-full h-full object-contain p-2"
                  onError={(e) => {
                    (e.target as HTMLImageElement).style.display = "none";
                  }}
                />
              ) : (
                <div className="flex flex-col items-center gap-2 text-muted-foreground">
                  <ImageIcon className="w-10 h-10" />
                  <span className="text-xs">Sem logo</span>
                </div>
              )}
            </div>

            <div className="space-y-3">
              <input
                type="file"
                ref={fileInputRef}
                onChange={handleFileChange}
                accept=".png,.jpg,.jpeg,.webp,.svg"
                className="hidden"
              />
              <Button
                onClick={() => fileInputRef.current?.click()}
                disabled={uploading || removeMutation.isPending}
                className="gap-2"
              >
                <Upload className="w-4 h-4" />
                {logoUrl ? "Alterar Logo" : "Enviar Logo"}
              </Button>

              {logoUrl && (
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => removeMutation.mutate()}
                  disabled={uploading || removeMutation.isPending}
                  className="gap-2 text-destructive hover:text-destructive"
                >
                  <Trash2 className="w-4 h-4" />
                  Remover
                </Button>
              )}
            </div>
          </div>

          {/* Instructions */}
          <Alert>
            <Info className="w-4 h-4" />
            <AlertDescription className="text-xs space-y-1">
              <p><strong>Formatos aceitos:</strong> PNG, JPG, WebP ou SVG</p>
              <p><strong>Tamanho máximo:</strong> 2 MB</p>
              <p><strong>Recomendações:</strong> Use preferencialmente PNG com fundo transparente para melhor resultado nos documentos. Dimensão ideal: 400×150 pixels (proporção horizontal).</p>
            </AlertDescription>
          </Alert>
        </CardContent>
      </Card>
    </div>
  );
}
