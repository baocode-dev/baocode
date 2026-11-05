import 'model_provider.dart';
import 'upstream_quota.dart';

/// The web has no service to ask: no quota is known.
class UpstreamQuotaStub extends UpstreamQuotaService {
  @override
  bool supports(ModelProvider provider) => false;

  @override
  Future<void> refresh(ModelProvider provider, {bool force = false}) async {}

  @override
  UpstreamQuota? quota(String providerId) => null;

  @override
  String? error(String providerId) => null;
}

/// The upstreams' plan quotas: none, on the web.
UpstreamQuotaService upstreamQuotaService() => UpstreamQuotaStub();
