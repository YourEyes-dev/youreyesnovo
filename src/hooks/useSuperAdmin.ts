 import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
 import { supabase } from '@/integrations/supabase/client';
 import { useAuthContext } from '@/contexts/AuthContext';
import type { Database } from '@/integrations/supabase/types';
 import type { TenantFormData } from '@/components/admin/TenantForm';

type TenantPlan = Database['public']['Enums']['tenant_plan'];
 
 export interface Tenant {
   id: string;
   nome: string;
   slug: string;
  plano: TenantPlan;
   ativo: boolean;
   created_at: string;
   updated_at: string;
 }
 
 export interface TenantWithStats extends Tenant {
   total_usuarios: number;
  total_colaboradores: number;
  email?: string;
  telefone?: string;
  cnpj?: string;
  // Plano vigente no motor de entitlements (subscriptions -> plans.code).
  // É a fonte da verdade do plano; `plano` (enum) é o rótulo legado.
  plano_atual?: string | null;
}
 
 export interface SuperAdmin {
   id: string;
   user_id: string;
   email: string;
   nome: string | null;
   ativo: boolean;
   created_at: string;
 }
 
 export function useSuperAdmin() {
   const queryClient = useQueryClient();
   const { isSuperAdmin, user } = useAuthContext();
 
   // Listar todos os tenants
   const { data: tenants = [], isLoading: isLoadingTenants } = useQuery({
     queryKey: ['superadmin', 'tenants'],
     queryFn: async (): Promise<TenantWithStats[]> => {
        const { data, error } = await supabase.rpc('superadmin_tenants_list' as any);
        if (error) throw error;
        return ((data as unknown) as TenantWithStats[]) || [];
      },
     enabled: isSuperAdmin,
   });
 
   // Criar novo tenant
   const createTenantMutation = useMutation({
    mutationFn: async (data: TenantFormData) => {
      // Step 1: Create the tenant
      const { data: tenant, error: tenantError } = await supabase
        .from('tenants')
        .insert({
          nome: data.nome,
          slug: data.slug,
          // O plano real vive no motor (subscriptions), definido logo abaixo.
          // `tenants.plano` (enum legado) fica no default do banco.
          ativo: true,
        })
        .select()
        .single();

      if (tenantError) throw tenantError;

      // Step 1.5: Create the Matriz unit in empresa_cadastro
      const { error: ecError } = await supabase
        .from('empresa_cadastro')
        .insert({
          tenant_id: tenant.id,
          nome_fantasia: data.nome,
          razao_social: data.nome,
          email: data.email,
          telefone: data.telefone,
          cnpj: data.cnpj,
          tipo_unidade: 'matriz',
          ativo: true
        });

      if (ecError) {
        // Warning: if this fails, we still have the tenant. 
        // We could cleanup or just log it. 
        console.error('Error creating empresa_cadastro:', ecError);
      }

      // Step 2: Create owner for the tenant via edge function
      const { data: result, error: ownerError } = await supabase.functions.invoke(
        'onboarding-signup',
        {
          body: {
            tenantNome: '',
            tenantSlug: '',
            nomeCompleto: data.ownerNome,
            tenantId: tenant.id,
            email: data.ownerEmail,
            password: data.accessMethod === 'password' ? data.ownerPassword : undefined,
            inviteMode: data.accessMethod === 'invite',
          },
        }
      );

      if (ownerError) {
        // Cleanup: delete tenant if owner creation failed
        await supabase.from('tenants').delete().eq('id', tenant.id);
        throw new Error(ownerError.message || 'Erro ao criar usuário owner');
      }

      if (result?.error) {
        // Cleanup: delete tenant if owner creation failed
        await supabase.from('tenants').delete().eq('id', tenant.id);
        throw new Error(result.error);
      }

      // Define o plano da nova empresa no motor de entitlements.
      // Sem clientes pagantes ainda, o padrão é 'tester' (acesso total).
      // Falha aqui não desfaz a empresa: ela fica sem assinatura e o
      // superadmin ajusta o plano na tela "Assinatura e teste".
      const { error: planoError } = await supabase.rpc(
        'superadmin_set_tenant_plan' as any,
        { _tenant_id: tenant.id, _plan_code: data.planoCode || 'tester' }
      );
      if (planoError) console.error('Erro ao definir plano da empresa:', planoError);

      return { tenant, inviteSent: result?.inviteSent };
     },
     onSuccess: () => {
       queryClient.invalidateQueries({ queryKey: ['superadmin', 'tenants'] });
     },
   });
 
    // Atualizar tenant
    const updateTenantMutation = useMutation({
     mutationFn: async ({ id, email, telefone, cnpj, ...updateData }: { id: string; nome?: string; slug?: string; ativo?: boolean; email?: string; telefone?: string; cnpj?: string }) => {
        // Obs.: o plano NÃO é editado aqui — ele vive no motor e é definido
        // pela tela "Assinatura e teste" (setTenantPlano).
        // Atualiza a tabela principal
        const { error: tenantError } = await supabase
          .from('tenants')
          .update(updateData)
          .eq('id', id);
  
        if (tenantError) throw tenantError;

        // Atualiza os dados na empresa_cadastro (Matriz)
        if (email !== undefined || telefone !== undefined || cnpj !== undefined) {
          // Primeiro tenta atualizar a matriz existente
          const { data: matriz, error: fetchError } = await supabase
            .from('empresa_cadastro')
            .select('id')
            .eq('tenant_id', id)
            .eq('tipo_unidade', 'matriz')
            .order('created_at', { ascending: false })
            .limit(1)
            .maybeSingle();

          if (fetchError) throw fetchError;

          const updatePayload: any = {};
          if (email !== undefined) updatePayload.email = email;
          if (telefone !== undefined) updatePayload.telefone = telefone;
          if (cnpj !== undefined) updatePayload.cnpj = cnpj;
          if (updateData.nome) updatePayload.nome_fantasia = updateData.nome;

          if (matriz) {
            const { error: updateError } = await supabase
              .from('empresa_cadastro')
              .update(updatePayload)
              .eq('id', matriz.id);
            if (updateError) throw updateError;
          } else {
            // Se não existir matriz (estranho, mas possível), cria uma
            const { error: insertError } = await supabase
              .from('empresa_cadastro')
              .insert({
                tenant_id: id,
                tipo_unidade: 'matriz',
                ...updatePayload,
                razao_social: updateData.nome || '',
                ativo: true
              });
            if (insertError) throw insertError;
          }
        }
      },
     onSuccess: () => {
       queryClient.invalidateQueries({ queryKey: ['superadmin', 'tenants'] });
     },
   });
 
    // Excluir tenant (apenas superadmin)
    const deleteTenantMutation = useMutation({
      mutationFn: async (id: string) => {
        const { error } = await supabase.rpc('superadmin_delete_tenant' as any, {
          _tenant_id: id
        });
        if (error) throw error;
      },
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: ['superadmin', 'tenants'] });
      },
    });

    const toggleTenantMutation = useMutation({
      mutationFn: async ({ id, ativo }: { id: string; ativo: boolean }) => {
       const { error } = await supabase
         .from('tenants')
         .update({ ativo })
         .eq('id', id);
 
       if (error) throw error;
     },
     onSuccess: () => {
       queryClient.invalidateQueries({ queryKey: ['superadmin', 'tenants'] });
     },
   });
 
   // Listar superadmins
   const { data: superadmins = [], isLoading: isLoadingSuperadmins } = useQuery({
     queryKey: ['superadmin', 'superadmins'],
     queryFn: async (): Promise<SuperAdmin[]> => {
       const { data, error } = await supabase
         .from('superadmins')
         .select('*')
         .order('created_at', { ascending: false });
 
       if (error) throw error;
       return data || [];
     },
     enabled: isSuperAdmin,
   });
 
    // Buscar usuários de um tenant específico
    const getTenantUsers = async (tenantId: string) => {
      const { data, error } = await supabase.rpc('superadmin_list_tenant_users', {
        _tenant_id: tenantId
      });
  
      if (error) throw error;
      return (data as any[]) || [];
    };
 
   // Criar usuário owner para um tenant
   const createTenantOwnerMutation = useMutation({
     mutationFn: async (data: {
       tenantId: string;
       email: string;
       password: string;
       nomeCompleto: string;
     }) => {
       // Criar usuário via edge function (que tem service role)
       const { data: result, error } = await supabase.functions.invoke(
         'onboarding-signup',
         {
           body: {
             tenantNome: '', // já existe
             tenantSlug: '',
             nomeCompleto: data.nomeCompleto,
             tenantId: data.tenantId, // usar tenant existente
             email: data.email,
             password: data.password,
           },
         }
       );
 
       if (error) throw error;
       return result;
     },
     onSuccess: () => {
       queryClient.invalidateQueries({ queryKey: ['superadmin', 'tenants'] });
     },
   });
 
  // Alternar unidade principal (matriz) de um tenant
  const setPrincipalEmpresaMutation = useMutation({
    mutationFn: async ({ empresaId, tenantId }: { empresaId: string; tenantId: string }) => {
      const { error } = await supabase.rpc('superadmin_set_principal_empresa', {
        _empresa_id: empresaId,
        _tenant_id: tenantId
      });

      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['superadmin', 'tenants'] });
      queryClient.invalidateQueries({ queryKey: ['superadmin-empresas-all'] });
      queryClient.invalidateQueries({ queryKey: ['spinoff-empresas'] });
    },
  });

  // Definir o plano da empresa no motor de entitlements (subscriptions).
  const setTenantPlanoMutation = useMutation({
    mutationFn: async ({ tenantId, planoCode }: { tenantId: string; planoCode: string }) => {
      const { error } = await supabase.rpc('superadmin_set_tenant_plan' as any, {
        _tenant_id: tenantId,
        _plan_code: planoCode,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['superadmin', 'tenants'] });
    },
  });

  return {
     // Estado
     isSuperAdmin,
     tenants,
     superadmins,
     isLoading: isLoadingTenants || isLoadingSuperadmins,

     // Mutations
     createTenant: createTenantMutation.mutateAsync,
     updateTenant: updateTenantMutation.mutateAsync,
      toggleTenant: toggleTenantMutation.mutateAsync,
      deleteTenant: deleteTenantMutation.mutateAsync,
      createTenantOwner: createTenantOwnerMutation.mutateAsync,
      setPrincipalEmpresa: setPrincipalEmpresaMutation.mutateAsync,
      setTenantPlano: setTenantPlanoMutation.mutateAsync,
      getTenantUsers,

     // Status
     isCreatingTenant: createTenantMutation.isPending,
     isUpdatingTenant: updateTenantMutation.isPending,
     isSettingPlano: setTenantPlanoMutation.isPending,
   };
 }