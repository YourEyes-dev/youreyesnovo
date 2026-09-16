import { useRef } from "react";
import { Camera, X, UserCircle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Avatar, AvatarImage, AvatarFallback } from "@/components/ui/avatar";

interface ProfilePhotoUploadProps {
  file: File | null;
  preview: string | null;
  onChange: (file: File | null, preview: string | null) => void;
}

export function ProfilePhotoUpload({ file, preview, onChange }: ProfilePhotoUploadProps) {
  const inputRef = useRef<HTMLInputElement>(null);

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const selected = e.target.files?.[0];
    if (!selected) return;
    if (!selected.type.startsWith("image/")) return;
    if (preview) URL.revokeObjectURL(preview);
    onChange(selected, URL.createObjectURL(selected));
  };

  const handleRemove = () => {
    if (preview) URL.revokeObjectURL(preview);
    onChange(null, null);
    if (inputRef.current) inputRef.current.value = "";
  };

  return (
    <div className="flex flex-col items-center gap-2">
      <div className="flex items-center justify-between w-full mb-1">
        <h4 className="font-medium text-sm text-foreground">Foto de Perfil</h4>
        <Badge variant={file ? "default" : "destructive"} className="text-[10px] px-1.5 py-0">
          {file ? "✓ Enviada" : "Obrigatório"}
        </Badge>
      </div>
      <div className="relative group cursor-pointer" onClick={() => inputRef.current?.click()}>
        <Avatar className="h-24 w-24 border-2 border-dashed border-border group-hover:border-primary transition-colors">
          {preview ? (
            <AvatarImage src={preview} alt="Foto de perfil" className="object-cover" />
          ) : (
            <AvatarFallback className="bg-muted">
              <UserCircle className="h-10 w-10 text-muted-foreground" />
            </AvatarFallback>
          )}
        </Avatar>
        <div className="absolute bottom-0 right-0 bg-primary text-primary-foreground rounded-full p-1.5 shadow-md">
          <Camera className="h-3.5 w-3.5" />
        </div>
      </div>
      {file && (
        <Button type="button" variant="ghost" size="sm" onClick={handleRemove} className="text-xs text-muted-foreground h-6 px-2">
          <X className="h-3 w-3 mr-1" /> Remover
        </Button>
      )}
      <p className="text-[11px] text-muted-foreground text-center">
        Esta foto será exibida no seu perfil público no MarketYE.
      </p>
      <input ref={inputRef} type="file" accept="image/*" className="hidden" onChange={handleFileChange} />
    </div>
  );
}
