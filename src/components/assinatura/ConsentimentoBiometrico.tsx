import { useState } from "react";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { ShieldCheck, AlertCircle, Loader2, Camera } from "lucide-react";
import {
  registrarConsentimentoBiometrico,
  FINALIDADE_CONSENTIMENTO_BIOMETRICO,
  VERSAO_CONSENTIMENTO_BIOMETRICO,
  type ConsentimentoRegistrado,
} from "@/lib/assinaturaConsentimento";

/**
 * ASS-0001 — FASE 0: tela de CONSENTIMENTO LGPD biométrico, reutilizável.
 *
 * Aparece ANTES de ligar a câmera. Aviso específico (finalidade = confirmar a
 * identidade na assinatura DESTE documento), consentimento granular (o titular
 * marca o aceite) e link para a Política de Privacidade. Ao aceitar, registra a
 * versão aceita na trilha do servidor (quem/quando/versão) e só então libera a
 * verificação de presença. NÃO liga câmera aqui; chama onConsentimento.
 *
 * Dado biométrico é sensível (LGPD art. 11, I; art. 9º). NÃO toca módulo nenhum.
 */
export interface ConsentimentoBiometricoProps {
  tenantId: string;
  /** Módulo/fluxo (ex.: 'advertencia', 'epi'). */
  contexto: string;
  documentoRef?: string | null;
  signatarioNome?: string | null;
  signatarioCpf?: string | null;
  /** Finalidade mostrada ao titular; por padrão, a finalidade específica da assinatura. */
  finalidade?: string;
  /** Recebe o registro do consentimento (id + versão) para ligar à assinatura. */
  onConsentimento: (registro: ConsentimentoRegistrado) => void;
  /** Opcional: o titular recusou e não quer seguir. */
  onRecusar?: () => void;
}

export function ConsentimentoBiometrico({
  tenantId,
  contexto,
  documentoRef,
  signatarioNome,
  signatarioCpf,
  finalidade = FINALIDADE_CONSENTIMENTO_BIOMETRICO,
  onConsentimento,
  onRecusar,
}: ConsentimentoBiometricoProps) {
  const [aceito, setAceito] = useState(false);
  const [enviando, setEnviando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  const continuar = async () => {
    if (!aceito || enviando) return;
    setEnviando(true);
    setErro(null);
    const registro = await registrarConsentimentoBiometrico({
      tenantId,
      contexto,
      documentoRef,
      signatarioNome,
      signatarioCpf,
      finalidade,
      versaoTexto: VERSAO_CONSENTIMENTO_BIOMETRICO,
    });
    setEnviando(false);
    if (!registro) {
      setErro("Não foi possível registrar o seu consentimento agora. Tente novamente.");
      return;
    }
    onConsentimento(registro);
  };

  return (
    <Card className="mx-auto max-w-md p-6">
      <div className="flex flex-col gap-4">
        <div className="flex items-center gap-2">
          <ShieldCheck className="h-6 w-6 text-primary" />
          <h3 className="text-lg font-semibold">Uso da câmera para confirmar sua identidade</h3>
        </div>

        <p className="text-sm text-muted-foreground">
          Para assinar este documento, vamos pedir que você faça alguns gestos diante da
          câmera (piscar, virar o rosto). As imagens servem para uma única finalidade:{" "}
          <strong className="text-foreground">{finalidade}</strong>
        </p>

        <ul className="list-disc space-y-1 pl-5 text-sm text-muted-foreground">
          <li>As imagens ficam guardadas de forma privada e protegida, ligadas a esta assinatura.</li>
          <li>Não usamos o seu rosto para nenhuma outra finalidade.</li>
          <li>
            Dado biométrico é dado pessoal sensível. O tratamento segue a LGPD (Lei 13.709/2018),
            detalhado na{" "}
            <a
              href="/politica-de-privacidade"
              target="_blank"
              rel="noopener noreferrer"
              className="font-medium text-primary underline underline-offset-2"
            >
              Política de Privacidade
            </a>.
          </li>
        </ul>

        <label className="flex items-start gap-3 rounded-md border p-3 text-sm">
          <Checkbox
            checked={aceito}
            onCheckedChange={(v) => setAceito(v === true)}
            className="mt-0.5"
            aria-label="Aceito o uso da câmera para confirmar minha identidade"
          />
          <span>
            Li e <strong>concordo</strong> com o uso da câmera para confirmar a minha identidade
            no momento desta assinatura, conforme descrito acima.
          </span>
        </label>

        {erro && (
          <div className="flex items-center gap-2 rounded-md bg-destructive/10 p-3 text-sm text-destructive">
            <AlertCircle className="h-4 w-4 shrink-0" />
            <span>{erro}</span>
          </div>
        )}

        <div className="flex flex-col gap-2 sm:flex-row-reverse">
          <Button onClick={continuar} disabled={!aceito || enviando} className="w-full sm:w-auto">
            {enviando ? (
              <><Loader2 className="mr-2 h-4 w-4 animate-spin" /> Registrando...</>
            ) : (
              <><Camera className="mr-2 h-4 w-4" /> Concordar e abrir a câmera</>
            )}
          </Button>
          {onRecusar && (
            <Button variant="outline" onClick={onRecusar} disabled={enviando} className="w-full sm:w-auto">
              Agora não
            </Button>
          )}
        </div>

        <p className="text-center text-xs text-muted-foreground">
          Versão do consentimento: {VERSAO_CONSENTIMENTO_BIOMETRICO}
        </p>
      </div>
    </Card>
  );
}
