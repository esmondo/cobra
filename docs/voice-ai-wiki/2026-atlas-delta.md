# 2026 atlas delta

The supplied Claude artifact, **Voice Model Atlas**, is valuable as a discovery map. It adds newer classes and candidates that were not in the first version of this wiki. It should not be imported as an unquestioned leaderboard: several scores, prices, dates, and model names are aggregator or vendor claims, and a few entries require primary-source confirmation.

## Additions worth keeping

### Native speech-to-speech evaluation

Artificial Analysis now publishes a Speech-to-Speech Index combining Big Bench Audio, Full-Duplex-Bench, and τ-Voice. This is a useful shift because it separates speech reasoning, conversational dynamics, and agentic task completion instead of collapsing everything into voice naturalness. The index's own announcement should be used for current rankings and pricing, not a static screenshot. [Artificial Analysis Speech-to-Speech Index](https://artificialanalysis.ai/articles/announcing-the-artificial-analysis-speech-to-speech-index)

### NVIDIA NemotronLabs VoiceChat

This is a meaningful addition to the open-weight duplex section. NVIDIA describes it as an 11B end-to-end realtime full-duplex model that jointly performs streaming speech understanding and speech generation, with tool calling while conversation continues. NVIDIA reports approximately 450 ms turn-taking latency. The model is governed by the OpenMDW License Agreement and is labelled for research use, so it is not equivalent to Apache-2.0 or MIT. [NVIDIA model card](https://catalog.ngc.nvidia.com/orgs/nim/nvidia/models/nemotron-labs-voicechat), [Hugging Face](https://huggingface.co/nvidia/NVIDIA-NemotronLabs-VoiceChat-11B)

### Kyutai Pocket TTS

Pocket TTS is one of the strongest small-model additions. Kyutai documents a 100M-parameter CPU model with streaming, voice cloning, approximately 200 ms first-chunk latency, and faster-than-real-time operation on a MacBook Air M4. The repository is MIT licensed. These figures remain hardware- and prompt-dependent, but the model is directly relevant to offline Mac voice products. [Pocket TTS repository](https://github.com/kyutai-labs/pocket-tts), [Kyutai overview](https://kyutai.org/tts/)

### Qwen3-ASR

Qwen3-ASR-1.7B and 0.6B are useful additions to the Chinese and multilingual ASR sections. The official model card states support for 52 languages and dialects, including 22 Chinese dialects, and Apache-2.0 licensing. [Qwen3-ASR model card](https://huggingface.co/Qwen/Qwen3-ASR-1.7B), [technical report](https://arxiv.org/abs/2601.21337)

### Plumbing and turn-taking

The artifact is also right to treat the orchestration layer as a first-class category. Pipecat, LiveKit Agents, WebRTC/WebSocket transports, semantic VAD, endpointing, interruption, and tool-call state are often more important to product quality than swapping one good TTS model for another. A model benchmark cannot substitute for testing the complete session controller.

## Additions to track, but not yet use as confirmed facts

The artifact mentions Qwen-Audio-3.0-Realtime, GPT-Realtime-2.1, SeedRealtime, Seeduplex, Step-Audio-R1.1 Realtime, VoiceChat variants, PersonaPlex, MOSS-Audio, ARK-ASR, Audio8, VoxCPM2, IndexTTS-2.5, Voxtral TTS, and several newer benchmark suites.

These are useful search targets. Before adding them to a production recommendation, verify all of the following from a primary source:

- official model page or repository;
- weights and code availability;
- exact license for both code and weights;
- reproducible benchmark definition;
- hardware and concurrency behind latency claims;
- API or checkpoint availability in the target region;
- commercial-use and voice-cloning terms.

The screenshot's precise leaderboard positions, prices, and claims such as “the only open model in the top three” are therefore retained as unverified snapshot claims, not as facts in the core recommendations.

## Updated practical picks

For Cobra or a similar local Mac product, the artifact changes the shortlist in two concrete ways:

1. Add **Pocket TTS** as the smallest credible local cloning TTS candidate.
2. Add **Qwen3-ASR** as a multilingual benchmark candidate alongside Parakeet and Whisper, especially if Indonesian, Mandarin, or Chinese dialects matter.

For a self-hosted full-duplex experiment, add **NemotronLabs VoiceChat 11B**, but keep Moshi and PersonaPlex-style systems as research baselines until deployment, license, and tool-call behavior are verified for the intended product.

## Why the core wiki remains conservative

The most consequential product risk is not missing a model that ranked first this month. It is choosing a model based on a score that measures the wrong thing, ignoring the license, or shipping a voice agent that sounds natural but mishandles interruption, entities, tools, or consent. The atlas improves discovery; the evaluation and deployment pages remain the decision gate.
