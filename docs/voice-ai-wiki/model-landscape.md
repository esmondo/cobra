# Model landscape

## Frontier and hosted systems

| System | Main capability | Best fit | Important limitation |
|---|---|---|---|
| [GPT-4o Realtime](https://developers.openai.com/api/docs/models/gpt-4o-realtime-preview) | Realtime audio input/output | General voice agents and tool use | Proprietary; audio-token cost and vendor coupling |
| Gemini native audio / Live | Native audio reasoning and multimodality | Long-context, multimodal assistants | Proprietary; availability and API behavior change |
| ElevenLabs | TTS, cloning, realtime voice | Highest-quality voice layer | Proprietary and usage-based |
| Cartesia Sonic | Low-latency streaming TTS | Fast agents | Primarily a voice layer, not the reasoning model |
| Hume EVI | Emotion-aware voice interaction | Coaching, support, expressive UX | Validate emotion claims on the target task |
| Amazon Nova Sonic | Native speech-to-speech | AWS enterprise deployments | AWS coupling |

## Open TTS

| Model | Scale | Strength | Notes |
|---|---:|---|---|
| [Chatterbox](https://github.com/resemble-ai/chatterbox) | small | Expressive cloning and emotion control | Vendor states MIT licensing, multilingual variants, and watermarking; validate each checkpoint |
| [CosyVoice 2/3](https://github.com/QwenAudio/CosyVoice) | 0.5B class | Multilingual, cross-lingual, dialects, streaming | Particularly strong Chinese ecosystem |
| F5-TTS | small/medium | Natural zero-shot cloning | Strong research and local community adoption |
| Fish Speech | medium | Expressive and multilingual synthesis | Check model-specific license and runtime |
| [VibeVoice-Realtime](https://github.com/microsoft/VibeVoice) | 0.5B | Streaming text input, long-form output | Original VibeVoice-TTS code was removed after misuse concerns |
| [Kyutai Pocket TTS](https://github.com/kyutai-labs/pocket-tts) | 100M | CPU realtime TTS, streaming, short-reference cloning | MIT; official figures report about 200 ms to first chunk on supported hardware |
| XTTS-v2 | medium | Mature cloning workflow | Older quality and expressiveness |
| Kokoro / Piper | tiny/small | Efficient local inference | Less flexible cloning and control |

## Open STT / ASR

| Model | Best fit |
|---|---|
| Whisper large-v3 / turbo | General multilingual transcription and mature tooling |
| NVIDIA Parakeet | Fast English ASR, local deployment |
| NVIDIA Canary | Multilingual ASR and speech translation |
| FunASR / Paraformer | Chinese and streaming industrial workloads |
| SenseVoice | Small multilingual speech understanding model |
| VibeVoice-ASR-7B | Long-form structured transcription with speaker/timing/content |
| VibeASR.cpp | CPU-oriented multilingual ASR; its repository reports a 1.58 GB compressed runtime |
| Qwen3-ASR-1.7B / 0.6B | 52 languages and dialects, including 22 Chinese dialects; Apache-2.0 |

VibeVoice-ASR documents up to 60-minute single-pass audio, speaker attribution, timestamps, and hotwords. Its BitNet runtime reports real-time factor below one on several CPU configurations. Treat these as project-reported results and reproduce them on the target hardware.

## CSM and conversational speech

### Sesame CSM

[CSM](https://github.com/SesameAILabs/csm) generates RVQ audio codes from text and audio context. It is a speech-generation model, not a complete multimodal assistant, and its README recommends a separate LLM for text generation. The repository has attracted more than 14k stars, making it one of the strongest signals of developer interest in conversational speech generation.

### Other important systems

| Model | What it contributes |
|---|---|
| [Moshi](https://github.com/kyutai-labs/moshi) | Open speech-text foundation model and full-duplex dialogue framework |
| [NemotronLabs VoiceChat 11B](https://huggingface.co/nvidia/NVIDIA-NemotronLabs-VoiceChat-11B) | Open full-duplex speech-to-speech with tool calling during conversation |
| [GLM-4-Voice](https://github.com/THUDM/GLM-4-Voice) | Chinese-English end-to-end spoken chatbot with controllable emotion, intonation, speed, and dialect |
| [Step-Audio](https://github.com/stepfun-ai/Step-Audio) | Chinese speech-language family covering recognition, dialogue, cloning, and synthesis |
| Qwen2.5-Omni | Multimodal audio-in/audio-out model |
| Mini-Omni2 | Open research attempt at GPT-4o-style speech and duplex behavior |
| Dia | Dialogue-oriented multi-speaker speech generation |

GLM-4-Voice uses a 12.5 Hz speech tokenizer, a 9B speech-language model, and a streaming decoder. Its repository is Apache-2.0. Step-Audio's project materials describe a much larger unified speech model family and a task-specific StepEval-Audio benchmark.

## Chinese ecosystem

The Chinese open ecosystem is unusually strong in speech. Prioritize these for Mandarin, dialects, and cross-lingual testing:

- Alibaba / Qwen Audio and CosyVoice
- FunASR and Paraformer
- SenseVoice
- GLM-4-Voice from Zhipu
- Step-Audio from StepFun
- Qwen2.5-Omni
- MiniCPM-o and Mini-Omni research lines

The practical advantage is not only model quality. These projects often expose training code, tokenizers, streaming examples, dialect coverage, and ModelScope/Hugging Face artifacts.

## Lightweight shortlist

For a laptop or modest GPU, start with:

```text
STT: Parakeet, faster-whisper, SenseVoice, or VibeASR.cpp
LLM: a local 4B-8B model or hosted reasoning model
TTS: Kokoro, Chatterbox Turbo, CosyVoice 0.5B, or VibeVoice-Realtime 0.5B
```

Stars, demos, and X/Threads posts are discovery signals, not benchmark evidence. Compare identical prompts, reference audio, hardware, quantization, and decoding settings.
