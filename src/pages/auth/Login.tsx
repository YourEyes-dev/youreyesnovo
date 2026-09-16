import { useState } from "react";
import { useNavigate, useLocation, Link } from "react-router-dom";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { Eye, EyeOff, Loader2 } from "lucide-react";
import { translateError } from "@/lib/translateError";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Form,
  FormControl,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from "@/components/ui/form";
import { useAuthContext } from "@/contexts/AuthContext";
import { toast } from "sonner";
import { Logo } from "@/components/ui/Logo";
import { useCadastroLivre } from "@/hooks/useCadastroLivre";

const loginSchema = z.object({
  email: z.string().email("E-mail inválido"),
  password: z.string().min(6, "Senha deve ter pelo menos 6 caracteres"),
});

type LoginFormData = z.infer<typeof loginSchema>;

// `destino`/`variante`: a Área do Parceiro reaproveita este formulário em
// /parceiros/entrar, só trocando texto e para onde ir depois de entrar.
export default function Login({ destino, variante }: { destino?: string; variante?: "parceiro" | "especialista" } = {}) {
  const navigate = useNavigate();
  const location = useLocation();
  const { signIn, loading } = useAuthContext();
  const [showPassword, setShowPassword] = useState(false);

  const from = destino || location.state?.from?.pathname || "/";
  const { livre: cadastroLivre } = useCadastroLivre();

  const form = useForm<LoginFormData>({
    resolver: zodResolver(loginSchema),
    defaultValues: {
      email: "",
      password: "",
    },
  });

  const onSubmit = async (data: LoginFormData) => {
    const { error } = await signIn(data.email, data.password);
    
    if (error) {
      toast.error("Não foi possível entrar", {
        description: translateError(error.message),
        duration: 6000,
      });
      return;
    }

    toast.success("Login realizado com sucesso!");
    navigate(from, { replace: true });
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-center mb-2">
        <Logo size="lg" showText={false} />
      </div>

      <div className="text-center space-y-1">
        <h1 className="text-2xl font-bold tracking-tight">{variante === "parceiro" ? "Área do Parceiro" : variante === "especialista" ? "MarketYE · Portal do especialista" : "Login"}</h1>
        <p className="text-sm text-muted-foreground">
          {variante === "parceiro" ? "Entre com a conta do seu cadastro de parceiro" : variante === "especialista" ? "Entre com a conta do seu cadastro de especialista" : "Entre com suas credenciais para acessar"}
        </p>
      </div>

      <Form {...form}>
        <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
          <FormField
            control={form.control}
            name="email"
            render={({ field }) => (
              <FormItem>
                <FormLabel>E-mail</FormLabel>
                <FormControl>
                  <Input
                    type="email"
                    placeholder="seu@email.com"
                    autoComplete="email"
                    {...field}
                  />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="password"
            render={({ field }) => (
              <FormItem>
                <FormLabel>Senha</FormLabel>
                <FormControl>
                  <div className="relative">
                    <Input
                      type={showPassword ? "text" : "password"}
                      placeholder="••••••••"
                      autoComplete="current-password"
                      {...field}
                    />
                    <Button
                      type="button"
                      variant="ghost"
                      size="icon"
                      className="absolute right-0 top-0 h-full px-3 hover:bg-transparent"
                      onClick={() => setShowPassword(!showPassword)}
                    >
                      {showPassword ? (
                        <EyeOff className="w-4 h-4 text-muted-foreground" />
                      ) : (
                        <Eye className="w-4 h-4 text-muted-foreground" />
                      )}
                    </Button>
                  </div>
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <div className="flex justify-end">
            <Link
              to="/forgot-password"
              className="text-sm text-primary hover:underline"
            >
              Esqueceu a senha?
            </Link>
          </div>

          <Button
            type="submit"
            className="w-full bg-gradient-to-r from-primary to-secondary text-white hover:from-primary/90 hover:to-secondary/90"
            disabled={loading}
          >
            {loading ? (
              <>
                <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                Entrando...
              </>
            ) : (
              "Entrar"
            )}
          </Button>
        </form>
      </Form>

      <div className="relative">
        <div className="absolute inset-0 flex items-center">
          <span className="w-full border-t" />
        </div>
        <div className="relative flex justify-center text-xs uppercase">
          <span className="bg-background px-2 text-muted-foreground">
            Ou
          </span>
        </div>
      </div>

      <div className="text-center">
        <p className="text-sm text-muted-foreground">
          Ainda não tem uma conta?{" "}
          {cadastroLivre ? (
            <Link to="/register" className="text-primary font-medium hover:underline">
              Cadastre sua empresa
            </Link>
          ) : (
            <a href={`${import.meta.env.BASE_URL.replace(/\/$/, "")}/#planos`} className="text-primary font-medium hover:underline">
              Conheça os planos e contrate
            </a>
          )}
        </p>
      </div>
    </div>
  );
}
