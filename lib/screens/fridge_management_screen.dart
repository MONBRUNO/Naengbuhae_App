import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/api_client.dart';
import '../state/fridge_context.dart';

const _accentGreen = Color(0xFFCDFF00);

class FridgeManagementScreen extends StatefulWidget {
  const FridgeManagementScreen({super.key});

  @override
  State<FridgeManagementScreen> createState() => _FridgeManagementScreenState();
}

class _FridgeManagementScreenState extends State<FridgeManagementScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _fridges = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.get('/api/fridges');
      if (res.statusCode == 200) {
        final list = (jsonDecode(utf8.decode(res.bodyBytes)) as List).cast<Map<String, dynamic>>();
        setState(() => _fridges = list);
        FridgeContext.fridges.value = list;
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createFridge() async {
    final name = await _promptName(title: '새 냉장고', hint: '예: 김치냉장고');
    if (name == null) return;
    final res = await ApiClient.post('/api/fridges', body: {'name': name});
    if (res.statusCode == 200) {
      _snack('냉장고가 생성되었습니다');
      await FridgeContext.refresh();
      _fetch();
    } else {
      _snack(_err(res.body) ?? '생성 실패');
    }
  }

  Future<void> _rename(Map<String, dynamic> f) async {
    final name = await _promptName(
      title: '이름 변경',
      hint: f['name']?.toString(),
      initial: f['name']?.toString(),
    );
    if (name == null) return;
    final res = await ApiClient.put('/api/fridges/${f['id']}', body: {'name': name});
    if (res.statusCode == 200) {
      _snack('이름이 변경되었습니다');
      await FridgeContext.refresh();
      _fetch();
    } else {
      _snack(_err(res.body) ?? '변경 실패');
    }
  }

  Future<void> _delete(Map<String, dynamic> f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${f['name']} 삭제'),
        content: const Text('이 냉장고와 안의 모든 식재료가 삭제됩니다. 되돌릴 수 없습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await ApiClient.delete('/api/fridges/${f['id']}');
    if (res.statusCode == 200) {
      _snack('삭제되었습니다');
      await FridgeContext.refresh();
      _fetch();
    } else {
      _snack(_err(res.body) ?? '삭제 실패');
    }
  }

  Future<void> _leave(Map<String, dynamic> f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${f['name']}에서 나가기'),
        content: const Text('나가면 이 냉장고의 식재료를 더 이상 볼 수 없습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('나가기', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await ApiClient.post('/api/fridges/${f['id']}/leave');
    if (res.statusCode == 200) {
      _snack('나갔습니다');
      await FridgeContext.refresh();
      _fetch();
    } else {
      _snack(_err(res.body) ?? '실패');
    }
  }

  Future<void> _showInviteCode(Map<String, dynamic> f) async {
    final res = await ApiClient.post('/api/fridges/${f['id']}/invites');
    if (res.statusCode != 200) {
      _snack(_err(res.body) ?? '코드 발급 실패');
      return;
    }
    final code = (jsonDecode(res.body) as Map<String, dynamic>)['code']?.toString();
    if (code == null) return;
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('초대 코드'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${f['name']}', style: const TextStyle(color: Color(0xFF6B7280))),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _accentGreen,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(code,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: 4)),
            ),
            const SizedBox(height: 12),
            const Text('24시간 동안 유효. 가족에게 코드를 알려주세요.',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                textAlign: TextAlign.center),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              _snack('복사되었습니다');
            },
            child: const Text('복사'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기')),
        ],
      ),
    );
  }

  Future<void> _joinByCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('초대 코드로 가입'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            hintText: '6자리 코드',
            counterText: '',
          ),
          maxLength: 6,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 3),
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('가입'),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    final res = await ApiClient.post('/api/fridges/join', body: {'code': code});
    if (res.statusCode == 200) {
      _snack('가입되었습니다');
      await FridgeContext.refresh();
      _fetch();
    } else {
      _snack(_err(res.body) ?? '가입 실패');
    }
  }

  Future<void> _removeMember(Map<String, dynamic> fridge, Map<String, dynamic> member) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${member['name'] ?? member['username']} 제거'),
        content: const Text('이 멤버를 냉장고에서 제거합니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('제거', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await ApiClient.delete('/api/fridges/${fridge['id']}/members/${member['username']}');
    if (res.statusCode == 200) {
      _snack('멤버를 제거했습니다');
      _fetch();
    } else {
      _snack(_err(res.body) ?? '실패');
    }
  }

  Future<String?> _promptName({required String title, String? hint, String? initial}) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          maxLength: 50,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          TextButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isEmpty) return;
              Navigator.pop(context, v);
            },
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  String? _err(String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map) return data['message']?.toString() ?? data['error']?.toString();
    } catch (_) {}
    return null;
  }

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('냉장고 관리', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetch,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  // 액션 버튼 2개
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _createFridge,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('냉장고 만들기'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accentGreen,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            textStyle: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _joinByCode,
                          icon: const Icon(Icons.vpn_key_outlined, size: 18),
                          label: const Text('코드로 가입'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            side: const BorderSide(color: Color(0xFFE5E7EB)),
                            textStyle: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ..._fridges.map(_fridgeCard),
                ],
              ),
            ),
    );
  }

  // 냉장고 카드 — 단순. 이름 + 멤버 수 + chevron. 탭하면 상세 바텀시트.
  Widget _fridgeCard(Map<String, dynamic> f) {
    final members = (f['members'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _showFridgeDetail(f),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                child: const Icon(LucideIcons.refrigerator, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f['name']?.toString() ?? '',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.group_outlined, size: 12, color: Color(0xFF9CA3AF)),
                        const SizedBox(width: 4),
                        Text('멤버 ${members.length}명',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
            ],
          ),
        ),
      ),
    );
  }

  // 상세 바텀시트. 멤버 목록 + 초대 코드 + 관리 액션.
  // 시트 내부 상태는 StatefulBuilder로 — 액션 후 _fetch + 시트 다시 그리기.
  void _showFridgeDetail(Map<String, dynamic> initial) {
    Map<String, dynamic> current = initial;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            // 시트 내부에서 액션 후 호출 — 부모 데이터 새로고침하고 시트의 current를 최신으로.
            Future<void> refreshLocal() async {
              await _fetch();
              final id = current['id'];
              final updated = _fridges.cast<Map<String, dynamic>?>().firstWhere(
                    (f) => f?['id'] == id,
                    orElse: () => null,
                  );
              if (updated == null) {
                if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
              } else {
                setSheetState(() => current = updated);
              }
            }

            final members = (current['members'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.92,
              expand: false,
              builder: (_, scrollController) {
                return Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1D5DB),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // 헤더
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(LucideIcons.refrigerator, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(current['name']?.toString() ?? '',
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text('멤버 ${members.length}명과 함께 사용',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Color(0xFF9CA3AF)),
                            onPressed: () => Navigator.of(sheetCtx).pop(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // 본문 스크롤
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        children: [
                          // 초대 코드 발급
                          const Text('가족 초대',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _showInviteCode(current),
                              icon: const Icon(LucideIcons.share2, size: 16),
                              label: const Text('초대 코드 발급'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _accentGreen,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                textStyle: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '6자리 코드를 발급해서 가족에게 알려주면 같은 냉장고를 함께 관리할 수 있어요.',
                            style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                          ),
                          const SizedBox(height: 24),

                          // 멤버 목록
                          Row(
                            children: [
                              const Icon(Icons.group_outlined, size: 16),
                              const SizedBox(width: 6),
                              Text('멤버 (${members.length})',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...members.map((m) => _memberRow(m, refreshLocal, current)),
                          const SizedBox(height: 24),

                          // 관리 액션
                          const Text('관리',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          _actionRow('이름 변경', Icons.edit_outlined, () async {
                            await _rename(current);
                            await refreshLocal();
                          }),
                          const SizedBox(height: 8),
                          _actionRow('냉장고에서 나가기', Icons.logout, () async {
                            await _leave(current);
                            if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                          }),
                          const SizedBox(height: 8),
                          _actionRow('냉장고 삭제 (모두에게서 사라짐)', Icons.delete_outline, () async {
                            await _delete(current);
                            if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                          }, destructive: true),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _memberRow(
      Map<String, dynamic> m, Future<void> Function() refreshLocal, Map<String, dynamic> fridge) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.person_outline, size: 16, color: Color(0xFF6B7280)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(m['name']?.toString() ?? m['username']?.toString() ?? '',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text(m['username']?.toString() ?? '',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
            onPressed: () async {
              await _removeMember(fridge, m);
              await refreshLocal();
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _actionRow(String label, IconData icon, VoidCallback onTap, {bool destructive = false}) {
    final color = destructive ? const Color(0xFFEF4444) : Colors.black;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
            ),
          ],
        ),
      ),
    );
  }
}
