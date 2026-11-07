import 'model_provider.dart';

/// Which logo of [BrandLogos] a model and an upstream are shown with.
abstract final class ModelBrand {
  /// The maker of model [id], as its name says (`claude-sonnet-4-5`,
  /// `deepseek-ai/DeepSeek-V3`, `openai/gpt-5`); null when it does not.
  /// The family before the vendor: a relay's `meta-llama/…` is Meta's.
  static String? ofModel(String id) {
    final name = id.toLowerCase();
    for (final (pattern, brand) in _models) {
      if (pattern.hasMatch(name)) return brand;
    }
    return null;
  }

  /// [provider]'s maker, by where it is: Anthropic's API, OpenAI's,
  /// OpenRouter…; null for a relay of no maker's.
  static String? ofProvider(ModelProvider provider) {
    if (provider.protocol == ProviderProtocol.codex) return 'openai';
    if (provider.followsMagpie) return 'magpie';
    final uri = Uri.tryParse(provider.baseUrl.trim());
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (host == 'localhost' || host == '127.0.0.1') {
      return switch (uri.port) {
        11434 => 'ollama',
        1234 => 'lmstudio',
        3425 => 'magpie',
        _ => null,
      };
    }
    for (final (domains, brand) in _hosts) {
      if (domains.any(
        (domain) => host == domain || host.endsWith('.$domain'),
      )) {
        return brand;
      }
    }
    return null;
  }

  /// A word of a model's name, after its start or a separator.
  static RegExp _word(String pattern) =>
      RegExp('(^|[/_.: -])(?:$pattern)', caseSensitive: false);

  static final _models = [
    (_word('claude|anthropic'), 'claude'),
    (_word(r'gemini'), 'gemini'),
    (_word(r'gemma'), 'google'),
    (_word(r'deepseek'), 'deepseek'),
    (_word(r'qwen|qwq|qvq'), 'qwen'),
    (_word(r'glm|chatglm|codegeex|cogview|zhipu'), 'zhipu'),
    (_word(r'kimi|moonshot'), 'kimi'),
    (_word(r'minimax|abab'), 'minimax'),
    (_word(r'doubao'), 'doubao'),
    (_word(r'seed'), 'bytedance'),
    (_word(r'hunyuan'), 'hunyuan'),
    (_word(r'ernie|wenxin'), 'wenxin'),
    (_word(r'step-'), 'stepfun'),
    (_word(r'baichuan'), 'baichuan'),
    (_word(r'yi-'), 'yi'),
    (_word(r'grok|xai'), 'xai'),
    (
      _word(r'mistral|mixtral|codestral|devstral|magistral|ministral|pixtral'),
      'mistral',
    ),
    (_word(r'llama'), 'meta'),
    (_word(r'phi-'), 'microsoft'),
    (_word(r'nemotron|nvidia'), 'nvidia'),
    (_word(r'sonar|perplexity'), 'perplexity'),
    // Last, as the most general: `o3` alone, or `o3-mini`.
    (_word(r'gpt|chatgpt|codex|openai|o\d+(?:$|[-_.: ])'), 'openai'),
  ];

  static const _hosts = [
    (['anthropic.com', 'claude.ai'], 'anthropic'),
    (['openai.com', 'chatgpt.com'], 'openai'),
    (['generativelanguage.googleapis.com'], 'gemini'),
    (['aiplatform.googleapis.com'], 'vertexai'),
    (['deepseek.com'], 'deepseek'),
    (['dashscope.aliyuncs.com', 'dashscope-intl.aliyuncs.com'], 'qwen'),
    (['bigmodel.cn', 'z.ai'], 'zhipu'),
    (['moonshot.cn', 'moonshot.ai', 'kimi.com'], 'moonshot'),
    (['minimax.io', 'minimaxi.com', 'minimax.chat'], 'minimax'),
    (['volces.com', 'volcengine.com'], 'volcengine'),
    (['hunyuan.cloud.tencent.com', 'hunyuan.tencentcloudapi.com'], 'hunyuan'),
    (['qianfan.baidubce.com'], 'wenxin'),
    (['stepfun.com'], 'stepfun'),
    (['baichuan-ai.com'], 'baichuan'),
    (['lingyiwanwu.com', '01.ai'], 'yi'),
    (['x.ai'], 'xai'),
    (['mistral.ai'], 'mistral'),
    (['perplexity.ai'], 'perplexity'),
    (['nvidia.com'], 'nvidia'),
    (['githubcopilot.com'], 'githubcopilot'),
    (['openrouter.ai'], 'openrouter'),
    (['siliconflow.cn', 'siliconflow.com'], 'siliconflow'),
    (['together.xyz', 'together.ai'], 'together'),
    (['fireworks.ai'], 'fireworks'),
    (['huggingface.co'], 'huggingface'),
    (['ollama.com'], 'ollama'),
    (['azure.com'], 'azure'),
    (['amazonaws.com'], 'bedrock'),
    (['cloudflare.com'], 'cloudflare'),
    (['vercel.sh'], 'vercel'),
  ];
}
