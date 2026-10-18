# Safety and glossary

## Safety baseline

Voice is identity-bearing data. Treat a reference recording, speaker embedding, transcript, and generated voice as sensitive assets.

- Obtain explicit permission before cloning a person's voice.
- Do not use a clone for impersonation, fraud, authentication bypass, or deceptive outreach.
- Tell users when they are hearing generated speech.
- Preserve or enable provenance watermarks where available.
- Give users a way to stop output immediately.
- Store raw audio only when necessary, with a retention limit.
- Separate transcript analytics from identity data.
- Avoid sending microphone audio to a provider without a clear user action and policy.
- Add tool authorization outside the model. A voice model should not silently approve irreversible actions.

## Glossary

**ASR / STT**: Automatic speech recognition, converting speech to text.

**TTS**: Text-to-speech, converting text into generated speech.

**VAD**: Voice activity detection, estimating whether speech is present.

**Endpointing**: Deciding when an utterance or turn has ended.

**Barge-in**: The user interrupting the assistant while it is speaking.

**Streaming**: Producing or consuming partial audio/text before the complete result exists.

**Native audio**: A model directly consuming and/or producing audio rather than exposing only text boundaries.

**Speech-to-speech**: Audio input to audio output, usually with an internal reasoning or dialogue process.

**Full duplex**: Simultaneous listening and speaking with overlap and interruption support.

**CSM**: Conversational Speech Model. In this wiki, it refers to models that generate dialogue-conditioned speech, not a single standardized architecture.

**Voice cloning**: Conditioning synthesis on a reference speaker recording or learned speaker representation.

**Zero-shot cloning**: Cloning from a short reference without per-speaker fine-tuning.

**TTFA**: Time to first audio, from the relevant user event to the first audible assistant sample.

**RTF**: Real-time factor. Values below 1 mean the system processes faster than the duration of the input under the stated conditions.

**WER**: Word error rate, a standard ASR transcription metric.

**Diarization**: Assigning speech segments to speakers.

**RVQ**: Residual vector quantization, commonly used to represent audio with multiple codebooks.

**Speech token**: A discrete representation of audio used by an audio-language model.
