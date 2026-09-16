/**
 * Leitura de arquivo AFD para importação conferida (Portaria MTP 671/2021 e
 * Portaria 1510/2009).
 *
 * O que este módulo faz é PREPARAR o arquivo para a conferência que roda no
 * banco (`ponto_afd_validar_importacao`): quebra o arquivo em registros
 * tipados, preserva a LINHA CRUA de cada um (o banco recalcula o CRC-16 sobre
 * ela) e separa as marcações dos registros de equipamento. Quem dá o veredito
 * é o banco — aqui não se aprova nem se reprova nada.
 *
 * Dois leiautes convivem no mercado:
 *   · 1510/2009 — tipo do registro na 1ª posição, NSR nas seguintes;
 *   · 671/2021  — NSR nas 9 primeiras posições, tipo na 10ª.
 * A detecção é pelo cabeçalho e, na dúvida, pela forma das linhas.
 *
 * Sobre o registro tipo 7: na 671 ele é a marcação do REP-P, que carrega o
 * corpo mais um hash SHA-256. O validador do banco confere esse par
 * (`conteudo` + `sha256`) — por isso cada marcação REP-P é enviada duas vezes:
 * como marcação (para a sequência de NSR) e como registro '7' (para a
 * conferência da assinatura).
 */

export type AfdLeiaute = "671" | "1510";

export interface AfdRegistro {
  /** Tipo na convenção que o validador do banco espera. */
  tipo: string;
  /** Linha crua, sem quebra de linha — base do CRC-16. */
  linha: string;
  nsr?: string;
  crc?: string;
  /** Marcação (tipo 3). */
  data?: string;
  hora?: string;
  cpf?: string;
  /** Registros de equipamento (tipos 4 e 6) e assinatura (tipo 7). */
  equipamento?: string;
  data_hora?: string;
  ajuste_de?: string;
  ajuste_para?: string;
  evento?: string;
  evento_desc?: string;
  conteudo?: string;
  sha256?: string;
}

export interface AfdLeitura {
  leiaute: AfdLeiaute;
  registros: AfdRegistro[];
  /** Marcações prontas para gravação, quando o banco aprovar o arquivo. */
  marcacoes: Array<{
    data_marcacao: string;
    hora_marcacao: string;
    colaborador_cpf: string;
    nsr_origem: string;
  }>;
  /** Linhas que não deu para ler — não reprovam nada por si só. */
  avisos: string[];
  totalLinhas: number;
}

const soDigitos = (v: string) => (v || "").replace(/\D/g, "");

/** DDMMAAAA + HHMM → { data: AAAA-MM-DD, hora: HH:MM:00 } */
function dataHora1510(dataStr: string, horaStr: string) {
  if (dataStr.length < 8 || horaStr.length < 4) return null;
  const data = `${dataStr.slice(4, 8)}-${dataStr.slice(2, 4)}-${dataStr.slice(0, 2)}`;
  const hora = `${horaStr.slice(0, 2)}:${horaStr.slice(2, 4)}:00`;
  return { data, hora };
}

/** Carimbo ISO 8601 da 671 (AAAA-MM-DDThh:mm:ss-03:00) → data e hora. */
function dataHoraIso(iso: string) {
  const m = (iso || "").match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?/);
  if (!m) return null;
  return { data: `${m[1]}-${m[2]}-${m[3]}`, hora: `${m[4]}:${m[5]}:${m[6] || "00"}` };
}

export function detectarLeiaute(linhas: string[]): AfdLeiaute {
  const primeira = linhas[0] || "";
  // 671: o cabeçalho começa com NSR zerado (9 dígitos) e o tipo vem depois.
  if (/^0{9}1/.test(primeira)) return "671";
  // 1510: o cabeçalho é o tipo 1 na primeira posição.
  if (/^1/.test(primeira) && !/^0{9}/.test(primeira)) return "1510";
  return /^\d{9}[1-9]/.test(primeira) ? "671" : "1510";
}

export function lerArquivoAfd(conteudo: string, equipamento?: string | null): AfdLeitura {
  const linhas = conteudo.split(/\r?\n/).filter((l) => l.trim().length > 0);
  const leiaute = detectarLeiaute(linhas);
  const registros: AfdRegistro[] = [];
  const marcacoes: AfdLeitura["marcacoes"] = [];
  const avisos: string[] = [];
  const eq = equipamento || null;

  linhas.forEach((linha, idx) => {
    const numLinha = idx + 1;
    try {
      const tipo = leiaute === "671" ? linha.charAt(9) : linha.charAt(0);
      const nsr = leiaute === "671" ? linha.slice(0, 9) : linha.slice(1, 11);
      const corpo = leiaute === "671" ? linha.slice(10) : linha.slice(11);

      if (tipo === "3" || (leiaute === "671" && tipo === "7")) {
        let dh: { data: string; hora: string } | null = null;
        let cpf = "";
        if (leiaute === "671") {
          // O carimbo ISO ocupa 24 ou 25 posições conforme o equipamento
          // escreva o fuso ("-03:00" ou "-0300"), e a marcação do REP-P ainda
          // traz 64 caracteres de hash no fim. Ler por posição fixa erra por
          // um caractere e desloca tudo — então o hash sai pelo fim e o CPF
          // são os 11 dígitos imediatamente antes dele.
          const hashFim = corpo.match(/([0-9a-fA-F]{64})\s*$/);
          const semHash = hashFim ? corpo.slice(0, corpo.length - hashFim[0].length) : corpo;
          const cpfFim = semHash.match(/(\d{11})\s*$/);
          cpf = cpfFim ? cpfFim[1] : soDigitos(semHash.slice(24, 35));
          const carimbo = cpfFim ? semHash.slice(0, semHash.length - cpfFim[0].length) : semHash.slice(0, 24);
          dh = dataHoraIso(carimbo.trim());
        } else {
          // 1510: tipo(1) NSR(10) tipo_id(1) data(8) hora(4) cpf(11)
          dh = dataHora1510(linha.slice(12, 20), linha.slice(20, 24));
          cpf = soDigitos(linha.slice(24, 35));
        }
        if (!dh || cpf.length !== 11) {
          avisos.push(`Linha ${numLinha}: marcação ilegível (data/hora ou CPF).`);
          return;
        }
        registros.push({ tipo: "3", linha, nsr, data: dh.data, hora: dh.hora, cpf, equipamento: eq || undefined });
        marcacoes.push({
          data_marcacao: dh.data,
          hora_marcacao: dh.hora,
          colaborador_cpf: cpf.replace(/^0+/, ""),
          nsr_origem: String(Number(nsr) || 0),
        });

        // 671 tipo 7: a marcação vem assinada — separa corpo e hash para o
        // banco conferir a assinatura.
        if (leiaute === "671" && tipo === "7") {
          const hash = (corpo.match(/([0-9a-fA-F]{64})\s*$/) || [])[1] || "";
          if (hash) {
            registros.push({
              tipo: "7",
              linha,
              nsr,
              conteudo: linha.slice(0, linha.length - hash.length),
              sha256: hash.toLowerCase(),
              equipamento: eq || undefined,
            });
          }
        }
        return;
      }

      if (tipo === "4") {
        // Ajuste do relógio: dois carimbos (de → para).
        const iso = leiaute === "671" ? corpo.slice(0, 24).trim() : linha.slice(11, 35).trim();
        const iso2 = leiaute === "671" ? corpo.slice(24, 48).trim() : linha.slice(35, 59).trim();
        const de = dataHoraIso(iso);
        const para = dataHoraIso(iso2);
        registros.push({
          tipo: "4",
          linha,
          nsr,
          equipamento: eq || undefined,
          data_hora: de ? `${de.data}T${de.hora}` : undefined,
          ajuste_de: de ? `${de.data}T${de.hora}` : undefined,
          ajuste_para: para ? `${para.data}T${para.hora}` : undefined,
        });
        return;
      }

      if (tipo === "6") {
        const iso = leiaute === "671" ? corpo.slice(0, 24).trim() : linha.slice(11, 35).trim();
        const dh = dataHoraIso(iso);
        registros.push({
          tipo: "6",
          linha,
          nsr,
          equipamento: eq || undefined,
          data_hora: dh ? `${dh.data}T${dh.hora}` : undefined,
          evento: (leiaute === "671" ? corpo.slice(24, 26) : linha.slice(35, 37)).trim() || undefined,
          evento_desc: (leiaute === "671" ? corpo.slice(26, 126) : linha.slice(37, 137)).trim() || undefined,
        });
        return;
      }

      // Demais registros (cabeçalho, empregador, empregados, trailer) entram
      // apenas para a conferência de CRC, quando o arquivo declarar.
      registros.push({ tipo, linha, nsr });
    } catch {
      avisos.push(`Linha ${numLinha}: não foi possível ler.`);
    }
  });

  return { leiaute, registros, marcacoes, avisos, totalLinhas: linhas.length };
}

/** SHA-256 do conteúdo do arquivo — identidade da remessa (trava de reimportação). */
export async function hashDoArquivo(conteudo: string): Promise<string> {
  const bytes = new TextEncoder().encode(conteudo);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
