import { describe, it, expect } from "vitest";
import { lerArquivoAfd, detectarLeiaute } from "@/lib/ponto/afdImportacao";

// Leiaute 1510: tipo(1) NSR(10) tipo_id(1) data(8) hora(4) cpf(11)
const linha1510 = (nsr: number, ddmmaaaa: string, hhmm: string, cpf: string) =>
  "3" + String(nsr).padStart(10, "0") + "1" + ddmmaaaa + hhmm + cpf.padStart(11, "0");

// Leiaute 671: NSR(9) tipo(1) carimbo ISO(24) cpf(11)
const linha671 = (nsr: number, iso: string, cpf: string, tipo = "3") =>
  String(nsr).padStart(9, "0") + tipo + iso.padEnd(24, " ") + cpf.padStart(11, "0");

describe("leitura de AFD para a conferência do banco", () => {
  it("lê o leiaute 1510 e monta marcações", () => {
    const conteudo = [
      linha1510(1, "03082026", "0800", "90000000153"),
      linha1510(2, "03082026", "1700", "90000000153"),
    ].join("\r\n");

    const r = lerArquivoAfd(conteudo, "Henry Orion 6");
    expect(r.leiaute).toBe("1510");
    expect(r.marcacoes).toHaveLength(2);
    expect(r.marcacoes[0]).toMatchObject({
      data_marcacao: "2026-08-03",
      hora_marcacao: "08:00:00",
      colaborador_cpf: "90000000153",
      nsr_origem: "1",
    });
    // Todo registro vai com a linha crua — é sobre ela que o banco recalcula o CRC.
    expect(r.registros[0].linha).toBe(conteudo.split("\r\n")[0]);
  });

  it("lê o leiaute 671 e separa a marcação assinada para conferência", () => {
    const hash = "a".repeat(64);
    const conteudo = [
      "0".repeat(9) + "1" + "CABECALHO",
      linha671(1, "2026-08-03T08:00:00-03:00", "90000000153", "7") + hash,
    ].join("\r\n");

    const r = lerArquivoAfd(conteudo, "REP-P");
    expect(r.leiaute).toBe("671");
    expect(r.marcacoes).toHaveLength(1);
    expect(r.marcacoes[0].hora_marcacao).toBe("08:00:00");
    // A mesma marcação vai como '3' (sequência de NSR) e como '7' (assinatura).
    const assinatura = r.registros.find((x) => x.tipo === "7");
    expect(assinatura?.sha256).toBe(hash);
    expect(assinatura?.conteudo).not.toContain(hash);
  });

  it("preserva a lacuna de NSR em vez de escondê-la", () => {
    // NSR 1 e 3: falta o 2. Quem reprova é o banco — a leitura só não pode
    // renumerar nem completar o buraco.
    const conteudo = [
      linha1510(1, "03082026", "0800", "90000000153"),
      linha1510(3, "03082026", "1700", "90000000153"),
    ].join("\r\n");

    const r = lerArquivoAfd(conteudo);
    expect(r.marcacoes.map((m) => m.nsr_origem)).toEqual(["1", "3"]);
  });

  it("avisa sobre linha ilegível sem derrubar a leitura", () => {
    const conteudo = [linha1510(1, "03082026", "0800", "90000000153"), "3lixo"].join("\n");
    const r = lerArquivoAfd(conteudo);
    expect(r.marcacoes).toHaveLength(1);
    expect(r.avisos).toHaveLength(1);
  });

  it("detecta o leiaute pelo cabeçalho", () => {
    expect(detectarLeiaute(["0".repeat(9) + "1ABC"])).toBe("671");
    expect(detectarLeiaute(["1" + "0".repeat(9) + "ABC"])).toBe("1510");
  });
});

describe("carimbo com fuso de tamanhos diferentes", () => {
  it("lê o mesmo instante com fuso '-03:00' e '-0300'", () => {
    const hash = "b".repeat(64);
    const monta = (iso: string) =>
      "000000001" + "7" + iso + "90000000153" + hash;
    const a = lerArquivoAfd(monta("2026-08-03T08:00:00-03:00"));
    const b = lerArquivoAfd(monta("2026-08-03T08:00:00-0300"));
    expect(a.marcacoes[0]).toMatchObject({ data_marcacao: "2026-08-03", hora_marcacao: "08:00:00" });
    expect(b.marcacoes[0]).toEqual(a.marcacoes[0]);
    expect(a.registros.find((r) => r.tipo === "7")?.sha256).toBe(hash);
  });
});
