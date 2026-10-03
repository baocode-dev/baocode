import 'model_provider.dart';
import 'model_runtime.dart';
import 'upstream.dart';

Future<List<RemoteModel>> listUpstreamModels(
  ModelProvider provider,
  String? key,
) async => throw const UpstreamException('Not available on the web.');

Future<Map<String, String>> providerLaunchEnvironment(
  ModelProvider provider,
  String model,
) async => throw const UpstreamException('Not available on the web.');

Future<void> stopModelProxy() async {}
