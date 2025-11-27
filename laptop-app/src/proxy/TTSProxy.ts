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

  // Voice is always from server configuration (TTS_VOICE env var)
  // Client-provided voice parameter is ignored
  const finalVoice = defaultVoice;
  
  // Validate and clamp speed based on provider requirements
  let finalSpeed = speed ?? 1.0;
  if (providerType === 'elevenlabs') {
    // ElevenLabs requires speed between 0.7 and 1.2
    finalSpeed = Math.max(0.7, Math.min(1.2, finalSpeed));
    // Round to 1 decimal place to avoid floating point precision issues
    finalSpeed = Math.round(finalSpeed * 10) / 10;
  } else if (providerType === 'openai') {
    // OpenAI accepts speed between 0.25 and 4.0, but we'll keep reasonable limits
    finalSpeed = Math.max(0.25, Math.min(4.0, finalSpeed));
    // Round to 1 decimal place
    finalSpeed = Math.round(finalSpeed * 10) / 10;
  }

  console.log(`🔊 TTS Proxy: Synthesizing speech via ${providerType}`);
  console.log(`   Model: ${model}`);
  console.log(`   Voice: ${finalVoice} (client: ${voice || 'not specified'}, default: ${defaultVoice})`);
  console.log(`   Speed: ${finalSpeed} (original: ${speed ?? 'not specified'}, validated for ${providerType})`);
  console.log(`   Text length: ${text.length} characters`);

  if (providerType === 'openai') {
    console.log(`   Endpoint: ${endpoint}`);
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
    // Endpoint includes voice in URL path: /text-to-speech/{voice_id}
    // Voice is always from server configuration (TTS_VOICE env var)
    const baseUrl = ttsProvider.getBaseUrl() || 'https://api.elevenlabs.io/v1';
    const elevenLabsEndpoint = `${baseUrl}/text-to-speech/${finalVoice}`;
    
    console.log(`   Endpoint: ${elevenLabsEndpoint}`);
    
    const response = await fetch(elevenLabsEndpoint, {
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

