import 'dart:io';

import 'package:baocode/icons/brand_logos.dart';
import 'package:baocode/models/model_brand.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a model is its maker\'s, as its name says', () {
    const cases = {
      'claude-sonnet-4-5': 'claude',
      'anthropic/claude-opus-4.1': 'claude',
      'claude-fable-5-2-reversed': 'claude',
      'gpt-5': 'openai',
      'gpt-6-luna': 'openai',
      'openai/gpt-oss-120b': 'openai',
      'o3': 'openai',
      'o4-mini': 'openai',
      'gemini-2.5-pro': 'gemini',
      'google/gemma-3-27b': 'google',
      'deepseek-ai/DeepSeek-V3.1': 'deepseek',
      'Qwen/Qwen3-Coder-480B': 'qwen',
      'qwq-32b': 'qwen',
      'glm-4.6': 'zhipu',
      'kimi-k2-0905': 'kimi',
      'MiniMax-M2': 'minimax',
      'doubao-seed-1-6': 'doubao',
      'grok-4': 'xai',
      'meta-llama/Llama-3.3-70B': 'meta',
      'mistral-large-latest': 'mistral',
      'devstral-medium': 'mistral',
      'step-2-16k': 'stepfun',
      'ernie-4.5': 'wenxin',
      'hunyuan-t1': 'hunyuan',
      'sonar-pro': 'perplexity',
    };
    for (final MapEntry(key: id, value: brand) in cases.entries) {
      expect(ModelBrand.ofModel(id), brand, reason: id);
    }
    // No maker's name in it; a word inside another is none.
    expect(ModelBrand.ofModel('my-model'), isNull);
    expect(ModelBrand.ofModel('photo3-large'), isNull);
    expect(ModelBrand.ofModel('foo-o1x'), isNull);
  });

  test('an upstream is its maker\'s, as its base URL says', () {
    String? of(String url, [ProviderProtocol? protocol]) =>
        ModelBrand.ofProvider(
          ModelProvider(
            id: 'p',
            name: 'P',
            baseUrl: url,
            protocol: protocol ?? ProviderProtocol.anthropic,
          ),
        );
    expect(of('https://api.anthropic.com'), 'anthropic');
    expect(of('https://api.deepseek.com/anthropic'), 'deepseek');
    expect(of('https://open.bigmodel.cn/api/anthropic'), 'zhipu');
    expect(of('https://openrouter.ai/api/v1'), 'openrouter');
    expect(of('https://dashscope.aliyuncs.com/apps/anthropic'), 'qwen');
    expect(of('http://localhost:11434/v1'), 'ollama');
    expect(of('', ProviderProtocol.codex), 'openai');
    // A relay's own name is none of theirs.
    expect(of('https://agentrouter.org'), isNull);
    expect(of('https://notanthropic.com'), isNull);
    expect(of('http://localhost:8080'), isNull);
  });

  test('every logo is a file, drawn in one color', () {
    for (final name in BrandLogos.names.keys) {
      final file = File(BrandLogos.asset(name));
      expect(file.existsSync(), isTrue, reason: name);
      final svg = file.readAsStringSync();
      expect(svg, contains('currentColor'), reason: name);
      expect(svg, isNot(matches(RegExp(r'(fill|stroke|stop-color)="#'))));
    }
  });
}
