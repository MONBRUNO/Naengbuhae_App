import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../services/notification_router.dart';
import '../utils/theme_colors.dart';

// 인앱 알림 센터 — 받은 알림 히스토리.
// 진입 시 자동으로 read-all 호출 (사용자가 봤다고 간주).
// 알림 탭하면 NotificationRouter로 화면 분기.
class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() => _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.get('/api/notifications');
      if (res.statusCode != 200) {
        setState(() => _error = '조회 실패 (${res.statusCode})');
        return;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as List;
      setState(() => _items = data.cast<Map<String, dynamic>>());
      // 본 시점에 모두 읽음 처리 (badge 카운트 0으로)
      // ignore: unawaited_futures
      ApiClient.post('/api/notifications/read-all');
    } catch (e) {
      setState(() => _error = '서버 연결 실패: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onTap(Map<String, dynamic> item) {
    final route = item['route']?.toString();
    if (route != null && route.isNotEmpty) {
      Navigator.of(context).pop();
      NotificationRouter.route(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('알림', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
      ),
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return ListView(children: [
        const SizedBox(height: 120),
        Center(child: Text(_error!)),
        const SizedBox(height: 16),
        Center(child: OutlinedButton(onPressed: _fetch, child: const Text('다시 시도'))),
      ]);
    }
    if (_items.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 160),
        Center(child: Icon(Icons.notifications_none, size: 48, color: Color(0xFFD1D5DB))),
        SizedBox(height: 12),
        Center(child: Text('받은 알림이 없어요',
            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14))),
      ]);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _row(_items[i]),
    );
  }

  Widget _row(Map<String, dynamic> item) {
    final isRead = item['read'] == true;
    return InkWell(
      onTap: () => _onTap(item),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isRead
              ? context.boxBg
              : (context.isDark ? const Color(0xFF365314) : const Color(0xFFF7FEE7)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isRead ? const Color(0xFFE5E7EB) : const Color(0xFFD9F99D),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 안읽음 dot
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 10),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isRead ? Colors.transparent : const Color(0xFF65A30D),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item['title']?.toString() ?? '',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(item['body']?.toString() ?? '',
                      style: TextStyle(fontSize: 13, color: context.subTextColor, height: 1.4)),
                  const SizedBox(height: 6),
                  Text(_formatTime(item['createdAt']?.toString()),
                      style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                ],
              ),
            ),
            if (item['route'] != null)
              const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
