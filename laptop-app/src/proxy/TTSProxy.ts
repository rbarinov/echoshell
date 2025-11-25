import type { TTSProvider } from '../keys/TTSProvider.js';

export async function synthesizeSpeech(
  ttsProvider: TTSProvider,
  text: string,
  voice?: string,
  speed?: number
): Promise<Buffer> {
  const endpoint = ttsProvider.getEndpoint();
  const apiKey = ttsProvider.getApiKey();
  const model = ttsProvider.getModel();
  const defaultVoice = ttsProvider.getVoice();
  const providerType = ttsProvider.getProviderType();

  const finalVoice = voice || defaultVoice;
  const finalSpeed = speed ?? 1.0;

  console.log(`🔊 TTS Proxy: Synthesizing speech via ${providerType}`);
  console.log(`   Endpoint: ${endpoint}`);
  console.log(`   Model: ${model}`);
  console.log(`   Voice: ${finalVoice}`);
  console.log(`   Speed: ${finalSpeed}`);
  console.log(`   Text length: ${text.length} characters`);

  if (providerType === 'openai') {
    // OpenAI TTS API format
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        model: model,
        input: text,
        voice: finalVoice,
        speed: finalSpeed
      })
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`OpenAI TTS API error: ${response.status} - ${errorText}`);
    }

    const audioBuffer = await response.arrayBuffer();
    return Buffer.from(audioBuffer);
  } else if (providerType === 'elevenlabs') {
    // ElevenLabs TTS API format
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        'xi-api-key': apiKey,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        text: text,
        model_id: model,
        voice_settings: {
          stability: 0.5,
          similarity_boost: 0.75,
          speed: finalSpeed
        }
      })
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`ElevenLabs TTS API error: ${response.status} - ${errorText}`);
    }

    const audioBuffer = await response.arrayBuffer();
    return Buffer.from(audioBuffer);
  } else {
    throw new Error(`Unsupported TTS provider: ${providerType}`);
  }
}

