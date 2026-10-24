# Modelo da verificação de presença (EPI)

`face_landmarker.task` é o modelo **Face Landmarker** do Google MediaPipe (variante float16, versão 1),
usado no navegador para detectar o piscar e a virada de cabeça na entrega de EPI. O processamento é
**local**: as imagens da câmera não saem do aparelho nesta etapa.

- Origem: https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task
- Licença: Apache 2.0 (MediaPipe)
- Tamanho: ~3,7 MB

Os arquivos WASM (`wasm/`) NÃO ficam no repositório: o `vite.config.ts` os copia de
`node_modules/@mediapipe/tasks-vision/wasm` para o build (`mediapipe/wasm/`) e os serve no desenvolvimento.
Para trocar a versão do modelo ou da biblioteca, atualize aqui a origem e confira de novo a calibração
dos limiares em `src/lib/liveness/analise.ts` com um rosto real.
