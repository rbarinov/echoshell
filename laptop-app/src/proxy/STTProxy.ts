import type { STTProvider } from '../keys/STTProvider.js';
import FormData from 'form-data';

export async function transcribeAudio(
  sttProvider: STTProvider,
  audioData: Buffer,
  language?: string
): Promise<string> {
  const endpoint = sttProvider.getEndpoint();
  const apiKey = sttProvider.getApiKey();
  const model = sttProvider.getModel();
  const baseUrl = sttProvider.getBaseUrl();

  console.log(`🎤 STT Proxy: Transcribing audio via ${sttProvider.getProviderType()}`);
  console.log(`   Endpoint: ${endpoint}`);
  console.log(`   Model: ${model}`);
  console.log(`   Language: ${language || 'auto'}`);

  const providerType = sttProvider.getProviderType();

  if (providerType === 'openai') {
    // OpenAI Whisper API format
    const formData = new FormData();
    formData.append('file', audioData, {
      filename: 'audio.m4a',
      contentType: 'audio/m4a'
    });
    formData.append('model', model);

    if (language && language !== 'auto') {
      formData.append('language', language);
    }

    const response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        ...formData.getHeaders()
      },
      body: formData as unknown as BodyInit
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`OpenAI STT API error: ${response.status} - ${errorText}`);
    }

    const result = await response.json() as { text: string };
    return result.text;
  } else if (providerType === 'elevenlabs') {
    // ElevenLabs STT API format (adjust based on actual API)
    const formData = new FormData();
    formData.append('audio', audioData, {
      filename: 'audio.m4a',
      contentType: 'audio/m4a'
    });

    if (language && language !== 'auto') {
      formData.append('language', language);
    }

    const response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        'xi-api-key': apiKey,
        ...formData.getHeaders()
      },
      body: formData as unknown as BodyInit
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`ElevenLabs STT API error: ${response.status} - ${errorText}`);
    }

    const result = await response.json() as { text: string };
    return result.text;
  } else {
    throw new Error(`Unsupported STT provider: ${providerType}`);
  }
}

