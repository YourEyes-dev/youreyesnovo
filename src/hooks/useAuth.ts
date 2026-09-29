/**
 * Ponto de entrada da autenticação para as telas.
 *
 * `useAuth` lê o estado do `AuthContext` — que é montado UMA única vez pelo
 * `AuthProvider` (em `src/contexts/AuthContext.tsx`). Antes, este arquivo
 * continha a própria máquina de estado com `useState`/`useEffect`; como 190+
 * telas e hooks chamavam `useAuth`, cada uma instanciava sua própria máquina
 * (assinatura de auth + `getSession` + 5 consultas de perfil), e a query de
 * dados de cada tela só começava depois que essa cópia local resolvia o
 * `tenantId`. Era a causa de "tela vazia → 1-3s → dados". Agora todos leem o
 * mesmo estado já pronto do contexto.
 *
 * `useAuthState` (a máquina pesada) fica exportada só para o `AuthProvider` e
 * para os testes exercitarem-na isoladamente — NÃO a use nas telas.
 */
export { useAuthContext as useAuth, useAuthState } from '@/contexts/AuthContext';
