import 'agy_quota.dart';

/// No agy here (the web): no limits to read.
AgyQuotaApi localAgyQuotaApi() => const _NoQuota();

class _NoQuota implements AgyQuotaApi {
  const _NoQuota();

  @override
  Future<List<({Object? summary, DateTime askedAt})>> summaries() async =>
      const [];
}
