import 'package:flutter/material.dart';

import '../pages/bangumi_mirror_verification_page.dart';
import '../services/bangumi_endpoint_service.dart';

class BangumiMirrorChallengeBanner extends StatelessWidget {
  const BangumiMirrorChallengeBanner({super.key, required this.endpoints});

  final BangumiEndpointService endpoints;

  @override
  Widget build(BuildContext context) {
    final challenge = endpoints.lastChallenge;
    if (challenge == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.errorContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.verified_user_outlined),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${challenge.kind.label}镜像需要人机验证。验证后请刷新页面；写操作需自行重新提交。',
                ),
              ),
              if (supportsBangumiMirrorVerification)
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BangumiMirrorVerificationPage(
                        endpoints: endpoints,
                        kind: challenge.kind,
                      ),
                    ),
                  ),
                  child: const Text('手动验证'),
                ),
              IconButton(
                tooltip: '关闭验证提示',
                onPressed: endpoints.dismissChallenge,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
