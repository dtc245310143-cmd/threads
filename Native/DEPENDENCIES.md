# Native desktop voice

- VieNeu-TTS v3 Turbo, Phạm Nguyễn Ngọc Bảo: https://github.com/pnnbao97/VieNeu-TTS
- Model and author-published GGUF: https://huggingface.co/pnnbao-ump/VieNeu-TTS-v3-Turbo/tree/61b85e3d937fbbacb387714180e8182823512523/gguf
- CPU native implementation, maintained upstream by the model author: https://github.com/0xShug0/audio.cpp/tree/6b0260ec8002e69a20c4ab2949fc312113c95bdf
- Text front end: https://github.com/pnnbao97/sea-g2p/tree/e825173f235d08ea19315b2b279fb11153b44cea

The bundled reference codes and 192-dimensional speaker embedding were generated with the installed Windows 2.9.3 voice runtime from its built-in IMG_8430 reference, using the same six-second mono 24 kHz preprocessing and denoising. `reference-info.json` records the reference hash and model revision. No separate reference upload is needed on iPhone.

The native model revision matches the installed Windows cache. The iPhone uses the author's Q8_0 package with the codec retained at f16 for a smaller package and practical CPU inference; Windows uses fp32 ONNX. The same speaker conditioning is used, but synthesis is stochastic and samples are not bit-identical across implementations. There is no silent fallback to an unrelated iOS voice.

Model/dictionary downloads are build-time only, pinned and SHA-256 checked. They are bundled in the installed application and do not require a TTS server or runtime model download. Dependency license texts are copied into `Library/voice/licenses` by the native build script. Pre-existing media source notices remain in `Library/SOURCES.txt`.
