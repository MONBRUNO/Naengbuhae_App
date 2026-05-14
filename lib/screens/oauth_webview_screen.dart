import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../api/api_client.dart';

// OAuth 흐름:
// 1. 앱이 <baseUrl>/oauth2/authorization/{provider} 로드
// 2. Spring이 카카오/구글/네이버 로그인 페이지로 302
// 3. 사용자 로그인 → 제공자가 <baseUrl>/login/oauth2/code/{provider} 로 콜백
// 4. OAuth2SuccessHandler가 frontend-redirect URL(기본 http://localhost:5173/oauth/callback)로
//    token / refreshToken / needsAdditionalInfo 쿼리 붙여 302
// 5. WebView가 그 URL을 로드하기 직전 NavigationDelegate에서 가로채서 토큰 추출 → pop
//
// 백엔드를 건드리지 않아도 동작하도록 frontend-redirect URL 자체는 의미 없고
// "oauth/callback" 패턴만 인식하면 됨 — 실제로 localhost:5173에 페이지가 없어도 무관.
class OAuthWebViewScreen extends StatefulWidget {
  final String provider; // 'kakao' | 'google' | 'naver'

  const OAuthWebViewScreen({super.key, required this.provider});

  @override
  State<OAuthWebViewScreen> createState() => _OAuthWebViewScreenState();
}

class _OAuthWebViewScreenState extends State<OAuthWebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onNavigationRequest: (request) {
          final result = _tryExtractTokens(request.url);
          if (result != null) {
            // 콜백 URL을 실제로 로드하진 않음 (localhost:5173은 모바일에서 도달 불가)
            Navigator.of(context).pop(result);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onWebResourceError: (_) {
          // 콜백 URL 로드 실패는 정상 — 위 onNavigationRequest에서 이미 처리됨
        },
      ))
      ..loadRequest(Uri.parse('${ApiClient.baseUrl}/oauth2/authorization/${widget.provider}'));
  }

  // URL에 oauth/callback이 포함되고 token이 있으면 OAuth 성공으로 간주.
  // 백엔드 frontend-redirect URL이 변경돼도(예: 운영 도메인) 동작하도록 패턴 매칭.
  OAuthResult? _tryExtractTokens(String url) {
    if (!url.contains('/oauth/callback')) return null;
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final token = uri.queryParameters['token'];
    final refreshToken = uri.queryParameters['refreshToken'];
    if (token == null || refreshToken == null) return null;
    final needsAdditionalInfo = uri.queryParameters['needsAdditionalInfo'] == 'true';
    return OAuthResult(
      accessToken: token,
      refreshToken: refreshToken,
      needsAdditionalInfo: needsAdditionalInfo,
    );
  }

  String get _title => switch (widget.provider) {
        'kakao' => '카카오 로그인',
        'google' => '구글 로그인',
        'naver' => '네이버 로그인',
        _ => '소셜 로그인',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }
}

// 성공 시 login_screen으로 돌아갈 때 전달하는 결과.
class OAuthResult {
  final String accessToken;
  final String refreshToken;
  final bool needsAdditionalInfo;

  OAuthResult({
    required this.accessToken,
    required this.refreshToken,
    required this.needsAdditionalInfo,
  });
}
