 import { useState } from 'react';
 import { Button } from '@/components/ui/button';
 import { Input } from '@/components/ui/input';
 import { Label } from '@/components/ui/label';
 import {
   Select,
   SelectContent,
   SelectItem,
   SelectTrigger,
   SelectValue,
 } from '@/components/ui/select';
 import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
 import { Separator } from '@/components/ui/separator';
 import { Loader2, Eye, EyeOff, Mail, Key } from 'lucide-react';
import { usePlanosCatalogo } from '@/hooks/usePlanosCatalogo';

type AccessMethod = 'invite' | 'password';

  export interface TenantFormData {
    nome: string;
    slug: string;
    planoCode: string;
    email?: string;
    telefone?: string;
    cnpj?: string;
    ownerNome: string;
    ownerEmail: string;
    accessMethod: AccessMethod;
    ownerPassword?: string;
  }

  interface TenantFormProps {
   onSubmit: (data: TenantFormData) => Promise<void>;
    isLoading?: boolean;
    onCancel: () => void;
    initialData?: {
      nome?: string;
      slug?: string;
      email?: string;
      telefone?: string;
      cnpj?: string;
    };
  }
 
  export function TenantForm({ onSubmit, isLoading, onCancel, initialData }: TenantFormProps) {
    const isEditing = !!initialData;
    const { planos } = usePlanosCatalogo();
     const [nome, setNome] = useState(initialData?.nome || '');
     const [slug, setSlug] = useState(initialData?.slug || '');
     const [planoCode, setPlanoCode] = useState<string>('tester');
     const [email, setEmail] = useState(initialData?.email || '');
     const [telefone, setTelefone] = useState(initialData?.telefone || '');
     const [cnpj, setCnpj] = useState(initialData?.cnpj || '');
     
     // Owner fields - only for new tenants
     const [ownerNome, setOwnerNome] = useState('');
     const [ownerEmail, setOwnerEmail] = useState('');
     const [accessMethod, setAccessMethod] = useState<AccessMethod>('invite');
     const [ownerPassword, setOwnerPassword] = useState('');
     const [showPassword, setShowPassword] = useState(false);
  
    const generateSlug = (name: string) => {
      return name
        .toLowerCase()
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-|-$/g, '');
    };
  
    const handleNomeChange = (value: string) => {
      setNome(value);
      if (!isEditing) {
        setSlug(generateSlug(value));
      }
    };
 
   const handleSubmit = async (e: React.FormEvent) => {
     e.preventDefault();
     await onSubmit({
       nome,
       slug,
       planoCode,
       email,
       telefone,
       cnpj,
       ownerNome,
       ownerEmail,
       accessMethod,
       ownerPassword: accessMethod === 'password' ? ownerPassword : undefined,
     });
   };
 
   const isFormValid = nome && slug && (isEditing || (ownerNome && ownerEmail && 
     (accessMethod === 'invite' || (accessMethod === 'password' && ownerPassword.length >= 6))));
 
   return (
     <form onSubmit={handleSubmit} className="space-y-4">
      {/* Dados da Empresa */}
      <div className="space-y-4">
        <h3 className="text-sm font-medium text-muted-foreground uppercase tracking-wide">
          Dados da Empresa
        </h3>
        
       <div className="space-y-2">
         <Label htmlFor="nome">Nome da Empresa</Label>
         <Input
           id="nome"
           placeholder="Ex: Empresa ABC Ltda"
           value={nome}
           onChange={(e) => handleNomeChange(e.target.value)}
           required
         />
       </div>
 
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div className="space-y-2">
            <Label htmlFor="email">E-mail da Empresa</Label>
            <Input
              id="email"
              type="email"
              placeholder="contato@empresa.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="telefone">Telefone</Label>
            <Input
              id="telefone"
              placeholder="(00) 00000-0000"
              value={telefone}
              onChange={(e) => setTelefone(e.target.value)}
            />
          </div>
        </div>

        <div className="space-y-2">
          <Label htmlFor="cnpj">CNPJ</Label>
          <Input
            id="cnpj"
            placeholder="00.000.000/0000-00"
            value={cnpj}
            onChange={(e) => setCnpj(e.target.value)}
          />
        </div>

        <div className="space-y-2">
         <Label htmlFor="slug">Slug (identificador único)</Label>
         <Input
           id="slug"
           placeholder="empresa-abc"
           value={slug}
           onChange={(e) => setSlug(e.target.value)}
           required
         />
         <p className="text-xs text-muted-foreground">
           Usado para URLs e identificação interna
         </p>
       </div>
 
       {!isEditing && (
         <div className="space-y-2">
           <Label htmlFor="plano">Plano inicial</Label>
           <Select value={planoCode} onValueChange={setPlanoCode}>
             <SelectTrigger>
               <SelectValue placeholder="Selecione o plano" />
             </SelectTrigger>
             <SelectContent>
               {planos.map((p) => (
                 <SelectItem key={p.code} value={p.code}>
                   {p.name}{!p.is_public ? ' (interno)' : ''}
                 </SelectItem>
               ))}
             </SelectContent>
           </Select>
           <p className="text-xs text-muted-foreground">
             Pode ser ajustado depois em "Assinatura e teste". Padrão: Tester (acesso total).
           </p>
         </div>
       )}
      </div>
 
       {!isEditing && (
        <>
          <Separator />
          
          {/* Dados do Administrador */}
          <div className="space-y-4">
            <h3 className="text-sm font-medium text-muted-foreground uppercase tracking-wide">
              Administrador Principal
            </h3>
            
            <div className="space-y-2">
              <Label htmlFor="ownerNome">Nome Completo</Label>
              <Input
                id="ownerNome"
                placeholder="Nome do administrador"
                value={ownerNome}
                onChange={(e) => setOwnerNome(e.target.value)}
                required={!isEditing}
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="ownerEmail">E-mail</Label>
              <Input
                id="ownerEmail"
                type="email"
                placeholder="admin@empresa.com"
                value={ownerEmail}
                onChange={(e) => setOwnerEmail(e.target.value)}
                required={!isEditing}
              />
            </div>

            <div className="space-y-3">
              <Label>Método de Acesso</Label>
              <RadioGroup 
                value={accessMethod} 
                onValueChange={(v) => setAccessMethod(v as AccessMethod)}
                className="space-y-2"
              >
                <div className="flex items-start space-x-3 p-3 rounded-lg border bg-card hover:bg-accent/50 transition-colors cursor-pointer">
                  <RadioGroupItem value="invite" id="invite" className="mt-0.5" />
                  <label htmlFor="invite" className="flex-1 cursor-pointer">
                    <div className="flex items-center gap-2">
                      <Mail className="w-4 h-4 text-primary" />
                      <span className="font-medium">Enviar link de convite</span>
                    </div>
                    <p className="text-xs text-muted-foreground mt-1">
                      O usuário receberá um e-mail com link para definir sua senha
                    </p>
                  </label>
                </div>
                
                <div className="flex items-start space-x-3 p-3 rounded-lg border bg-card hover:bg-accent/50 transition-colors cursor-pointer">
                  <RadioGroupItem value="password" id="password" className="mt-0.5" />
                  <label htmlFor="password" className="flex-1 cursor-pointer">
                    <div className="flex items-center gap-2">
                      <Key className="w-4 h-4 text-primary" />
                      <span className="font-medium">Definir senha manualmente</span>
                    </div>
                    <p className="text-xs text-muted-foreground mt-1">
                      Você define a senha e informa ao cliente
                    </p>
                  </label>
                </div>
              </RadioGroup>
            </div>

            {accessMethod === 'password' && (
              <div className="space-y-2">
                <Label htmlFor="ownerPassword">Senha</Label>
                <div className="relative">
                  <Input
                    id="ownerPassword"
                    type={showPassword ? 'text' : 'password'}
                    placeholder="Senha inicial"
                    value={ownerPassword}
                    onChange={(e) => setOwnerPassword(e.target.value)}
                    required={accessMethod === 'password' && !isEditing}
                    minLength={6}
                  />
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon"
                    className="absolute right-0 top-0"
                    onClick={() => setShowPassword(!showPassword)}
                  >
                    {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                  </Button>
                </div>
                <p className="text-xs text-muted-foreground">Mínimo de 6 caracteres</p>
              </div>
            )}
          </div>
        </>
      )}
 
       <div className="flex justify-end gap-2 pt-4">
         <Button type="button" variant="outline" onClick={onCancel}>
           Cancelar
         </Button>
        <Button type="submit" disabled={isLoading || !isFormValid}>
           {isLoading && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}
          {isEditing ? 'Salvar Alterações' : (accessMethod === 'invite' ? 'Criar e Enviar Convite' : 'Criar Empresa')}
         </Button>
       </div>
     </form>
   );
 }