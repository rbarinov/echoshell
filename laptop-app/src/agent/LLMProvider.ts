import { ChatOpenAI } from '@langchain/openai';
import type { BaseLanguageModel } from '@langchain/core/language_models/base';

export interface LLMProvider {
  getLLM(): BaseLanguageModel;
  getModelName(): string;
  getProviderType(): string;
}

export interface LLMProviderConfig {
  provider: string;
  apiKey: string;
  modelName?: string;
  baseUrl?: string;
  temperature?: number;
}

class OpenAIProvider implements LLMProvider {
  private llm: ChatOpenAI;
  private modelName: string;

  constructor(config: LLMProviderConfig) {
    this.modelName = config.modelName || 'gpt-4o-mini';
    this.llm = new ChatOpenAI({
      openAIApiKey: config.apiKey,
      modelName: this.modelName,
      temperature: config.temperature ?? 0,
      configuration: config.baseUrl ? {
        baseURL: config.baseUrl
      } : undefined
    });
  }

  getLLM(): BaseLanguageModel {
    return this.llm as unknown as BaseLanguageModel;
  }

  getModelName(): string {
    return this.modelName;
  }

  getProviderType(): string {
    return 'openai';
  }
}

class CerebrasProvider implements LLMProvider {
  private llm: ChatOpenAI;
  private modelName: string;

  constructor(config: LLMProviderConfig) {
    if (!config.baseUrl) {
      throw new Error(
        'Cerebras provider requires AGENT_BASE_URL to be set. ' +
        'Please set AGENT_BASE_URL=https://api.cerebras.ai/v1 in your .env file'
      );
    }
    
    this.modelName = config.modelName || 'gpt-oss-120b';
    this.llm = new ChatOpenAI({
      openAIApiKey: config.apiKey,
      modelName: this.modelName,
      temperature: config.temperature ?? 0,
      configuration: {
        baseURL: config.baseUrl
      }
    });
  }

  getLLM(): BaseLanguageModel {
    return this.llm as unknown as BaseLanguageModel;
  }

  getModelName(): string {
    return this.modelName;
  }

  getProviderType(): string {
    return 'cerebras';
  }
}

export function createLLMProvider(): LLMProvider {
  const provider = (process.env.AGENT_PROVIDER || 'openai').toLowerCase();
  const apiKey = process.env.AGENT_API_KEY;
  const modelName = process.env.AGENT_MODEL_NAME;
  const baseUrl = process.env.AGENT_BASE_URL;
  const temperature = process.env.AGENT_TEMPERATURE 
    ? parseFloat(process.env.AGENT_TEMPERATURE) 
    : undefined;

  if (!apiKey) {
    console.error('❌ AGENT_API_KEY is not set in environment variables');
    console.log('💡 Please set AGENT_API_KEY in laptop-app/.env or root .env');
    process.exit(1);
  }

  const config: LLMProviderConfig = {
    provider,
    apiKey,
    modelName,
    baseUrl,
    temperature
  };

  switch (provider) {
    case 'openai':
      return new OpenAIProvider(config);
    
    case 'cerebras':
      return new CerebrasProvider(config);
    
    default:
      console.error(`❌ Unknown AGENT_PROVIDER: ${provider}`);
      console.log('💡 Supported providers: openai, cerebras');
      process.exit(1);
  }
}

