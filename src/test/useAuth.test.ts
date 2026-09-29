import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook, act, waitFor } from "@testing-library/react";

// ============================================================
// Mock do Supabase — must use vi.hoisted for factory mocks
// ============================================================

const {
  supabaseMock,
  unsubscribeMock,
  getAuthStateCallback,
  setAuthStateCallback,
} = vi.hoisted(() => {
  const unsubscribeMock = vi.fn();
  let _authStateCallback: any = null;

  const supabaseMock = {
    auth: {
      getSession: vi.fn().mockResolvedValue({ data: { session: null } }),
      onAuthStateChange: vi.fn((cb: any) => {
        _authStateCallback = cb;
        return { data: { subscription: { unsubscribe: unsubscribeMock } } };
      }),
      signInWithPassword: vi.fn(),
      signUp: vi.fn(),
      signOut: vi.fn().mockResolvedValue({}),
    },
    from: vi.fn(),
    functions: { invoke: vi.fn() },
  };

  return {
    supabaseMock,
    unsubscribeMock,
    getAuthStateCallback: () => _authStateCallback,
    setAuthStateCallback: (v: any) => { _authStateCallback = v; },
  };
});

vi.mock("@/integrations/supabase/client", () => ({
  supabase: supabaseMock,
}));

// Exercita a máquina de estado pesada diretamente (sem provider). Nas telas,
// o app usa `useAuth`, que lê o contexto montado uma única vez pelo
// AuthProvider; aqui testamos a implementação subjacente isoladamente.
import { useAuthState as useAuth } from "@/hooks/useAuth";

// ============================================================
// Helpers
// ============================================================

const mockSession = {
  user: { id: "user-123", email: "test@example.com" },
  access_token: "token",
  refresh_token: "refresh",
};

const mockProfile = {
  user_id: "user-123",
  tenant_id: "tenant-abc",
  nome_completo: "João Teste",
  cargo: "Analista",
};

function mockFromChain(results: Record<string, { data: any; error: any }>) {
  supabaseMock.from.mockImplementation((table: string) => {
    const result = results[table] || { data: null, error: null };
    const chain: any = {
      select: vi.fn().mockReturnThis(),
      insert: vi.fn().mockReturnThis(),
      eq: vi.fn().mockReturnThis(),
      maybeSingle: vi.fn().mockResolvedValue(result),
      single: vi.fn().mockResolvedValue(result),
    };
    if (table === "user_roles") {
      chain.eq = vi.fn().mockResolvedValue(result);
    }
    return chain;
  });
}

// ============================================================
// Tests
// ============================================================

describe("useAuth", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    setAuthStateCallback(null);
    supabaseMock.auth.getSession.mockResolvedValue({ data: { session: null } });
  });

  it("inicia com loading=true e sem usuário", () => {
    mockFromChain({});
    const { result } = renderHook(() => useAuth());
    expect(result.current.loading).toBe(true);
    expect(result.current.user).toBeNull();
    expect(result.current.isAuthenticated).toBe(false);
  });

  it("fica loading=false após getSession retornar null", async () => {
    mockFromChain({});
    const { result } = renderHook(() => useAuth());
    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.isAuthenticated).toBe(false);
  });

  it("carrega profile e roles após login", async () => {
    supabaseMock.auth.getSession.mockResolvedValue({
      data: { session: mockSession },
    });

    mockFromChain({
      profiles: { data: mockProfile, error: null },
      user_roles: { data: [{ role: "admin" }], error: null },
      superadmins: { data: null, error: null },
    });

    const { result } = renderHook(() => useAuth());

    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.user?.id).toBe("user-123");
    expect(result.current.profile?.nome_completo).toBe("João Teste");
    expect(result.current.roles).toContain("admin");
    expect(result.current.tenantId).toBe("tenant-abc");
    expect(result.current.isAuthenticated).toBe(true);
  });

  it("isSuperAdmin quando role superadmin presente", async () => {
    supabaseMock.auth.getSession.mockResolvedValue({
      data: { session: mockSession },
    });

    mockFromChain({
      profiles: { data: mockProfile, error: null },
      user_roles: { data: [{ role: "superadmin" }], error: null },
      superadmins: { data: { id: "sa-1" }, error: null },
    });

    const { result } = renderHook(() => useAuth());
    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.isSuperAdmin).toBe(true);
  });

  it("signIn retorna erro traduzido quando falha", async () => {
    mockFromChain({});
    supabaseMock.auth.signInWithPassword.mockResolvedValue({
      error: { message: "Invalid login credentials" },
    });

    const { result } = renderHook(() => useAuth());
    await waitFor(() => expect(result.current.loading).toBe(false));

    let response: any;
    await act(async () => {
      response = await result.current.signIn("bad@email.com", "wrong");
    });

    expect(response.error).toBeTruthy();
    expect(response.error.message).toContain("Credenciais inválidas");
  });

  it("signIn retorna null error quando sucesso", async () => {
    mockFromChain({});
    supabaseMock.auth.signInWithPassword.mockResolvedValue({ error: null });

    const { result } = renderHook(() => useAuth());
    await waitFor(() => expect(result.current.loading).toBe(false));

    let response: any;
    await act(async () => {
      response = await result.current.signIn("user@test.com", "password");
    });

    expect(response.error).toBeNull();
  });

  it("signOut limpa todo o estado", async () => {
    supabaseMock.auth.getSession.mockResolvedValue({
      data: { session: mockSession },
    });

    mockFromChain({
      profiles: { data: mockProfile, error: null },
      user_roles: { data: [{ role: "admin" }], error: null },
      superadmins: { data: null, error: null },
    });

    const { result } = renderHook(() => useAuth());
    await waitFor(() => expect(result.current.isAuthenticated).toBe(true));

    await act(async () => {
      await result.current.signOut();
    });

    expect(result.current.user).toBeNull();
    expect(result.current.profile).toBeNull();
    expect(result.current.roles).toEqual([]);
    expect(result.current.isAuthenticated).toBe(false);
  });

  it("hasRole verifica role corretamente", async () => {
    supabaseMock.auth.getSession.mockResolvedValue({
      data: { session: mockSession },
    });

    mockFromChain({
      profiles: { data: mockProfile, error: null },
      user_roles: { data: [{ role: "manager" }], error: null },
      superadmins: { data: null, error: null },
    });

    const { result } = renderHook(() => useAuth());
    await waitFor(() => expect(result.current.loading).toBe(false));

    expect(result.current.hasRole("manager")).toBe(true);
    expect(result.current.hasRole("admin")).toBe(false);
  });

  it("hasMinimumRole respeita hierarquia", async () => {
    supabaseMock.auth.getSession.mockResolvedValue({
      data: { session: mockSession },
    });

    mockFromChain({
      profiles: { data: mockProfile, error: null },
      user_roles: { data: [{ role: "admin" }], error: null },
      superadmins: { data: null, error: null },
    });

    const { result } = renderHook(() => useAuth());
    await waitFor(() => expect(result.current.loading).toBe(false));

    expect(result.current.hasMinimumRole("user")).toBe(true);
    expect(result.current.hasMinimumRole("manager")).toBe(true);
    expect(result.current.hasMinimumRole("admin")).toBe(true);
    expect(result.current.hasMinimumRole("owner")).toBe(false);
  });

  it("superadmin tem acesso a tudo via hasMinimumRole", async () => {
    supabaseMock.auth.getSession.mockResolvedValue({
      data: { session: mockSession },
    });

    mockFromChain({
      profiles: { data: mockProfile, error: null },
      user_roles: { data: [{ role: "superadmin" }], error: null },
      superadmins: { data: { id: "sa-1" }, error: null },
    });

    const { result } = renderHook(() => useAuth());
    await waitFor(() => expect(result.current.loading).toBe(false));

    expect(result.current.hasMinimumRole("owner")).toBe(true);
    expect(result.current.hasMinimumRole("superadmin")).toBe(true);
  });

  it("trata erro no fetchUserData sem quebrar", async () => {
    supabaseMock.auth.getSession.mockResolvedValue({
      data: { session: mockSession },
    });

    mockFromChain({
      profiles: { data: null, error: { message: "Network error" } },
      user_roles: { data: [], error: null },
      superadmins: { data: null, error: null },
    });

    const { result } = renderHook(() => useAuth());
    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.error).toBeTruthy();
  });

  it("unsubscribe no cleanup", () => {
    mockFromChain({});
    const { unmount } = renderHook(() => useAuth());
    unmount();
    expect(unsubscribeMock).toHaveBeenCalled();
  });
});
