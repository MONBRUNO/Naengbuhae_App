import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/auth_storage.dart';
import '../services/fcm_service.dart';
import '../state/fridge_context.dart';
import '../utils/format.dart';
import '../widgets/notification_settings_section.dart';
import 'family_activity_screen.dart';
import 'fridge_management_screen.dart';
import 'login_screen.dart';
import 'meal_plan_screen.dart';
import 'notification_center_screen.dart';
import 'nutrition_screen.dart';
import 'priority_screen.dart';
import 'profile_edit_screen.dart';
import 'recipes_screen.dart';

const _accentGreen = Color(0xFFCDFF00);
const _accentGreenDeep = Color(0xFFB8E600);

// 웹의 MyCustom.tsx에 대응.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _profile;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _fetch();
    _fetchUnreadCount();
  }

  Future<void> _fetchUnreadCount() async {
    try {
      final res = await ApiClient.get('/api/notifications/unread-count');
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final count = data['count'];
      if (mounted) setState(() => _unreadCount = count is num ? count.toInt() : 0);
    } catch (_) {
      // 무시 — 다음 진입 시 다시 시도
    }
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.get('/user/me');
      if (res.statusCode != 200) {
        setState(() => _error = '조회 실패 (${res.statusCode})');
        return;
      }
      setState(() => _profile = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
    } catch (e) {
      setState(() => _error = '서버 연결 실패: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('로그아웃 하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('로그아웃')),
        ],
      ),
    );
    if (ok != true) return;
    // FCM 토큰 폐기는 access 토큰이 살아있을 때 먼저 — clear() 뒤엔 인증 실패함
    await FcmService.unregisterCurrentToken();
    await ApiClient.logoutOnServer();
    await AuthStorage.clear();
    await FridgeContext.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> _deleteAccount() async {
    final step1 = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('회원 탈퇴'),
        content: const Text('정말 회원 탈퇴 하시겠습니까?\n\n탈퇴 시 계정과 모든 데이터(식재료, 레시피 기록 등)가 영구 삭제되며 복구할 수 없습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('다음', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (step1 != true) return;
    final step2 = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('마지막 확인'),
        content: const Text('탈퇴를 진행하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('탈퇴', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (step2 != true) return;
    final res = await ApiClient.delete('/user/me');
    if (res.statusCode == 200) {
      await AuthStorage.clear();
      await FridgeContext.clear();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('탈퇴 실패 (${res.statusCode})')));
    }
  }

  ({double bmi, String label, Color color})? _calculateBmi() {
    final h = _profile?['height'];
    final w = _profile?['weight'];
    if (h == null || w == null) return null;
    final hM = (h is num ? h.toDouble() : double.tryParse(h.toString()) ?? 0) / 100;
    final wKg = w is num ? w.toDouble() : double.tryParse(w.toString()) ?? 0;
    if (hM <= 0 || wKg <= 0) return null;
    final bmi = wKg / (hM * hM);
    if (bmi < 18.5) return (bmi: bmi, label: '저체중', color: const Color(0xFF2563EB));
    if (bmi < 23) return (bmi: bmi, label: '정상', color: const Color(0xFF16A34A));
    if (bmi < 25) return (bmi: bmi, label: '과체중', color: const Color(0xFFCA8A04));
    return (bmi: bmi, label: '비만', color: const Color(0xFFDC2626));
  }

  int? _age() {
    final b = _profile?['birthDate']?.toString();
    if (b == null) return null;
    final d = DateTime.tryParse(b);
    if (d == null) return null;
    final now = DateTime.now();
    var age = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) age--;
    return age;
  }

  bool get _isProfileIncomplete {
    final p = _profile;
    if (p == null) return false;
    return p['height'] == null || p['weight'] == null || p['gender'] == null || p['birthDate'] == null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(bottom: false, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 4)),
            SizedBox(height: 16),
            Text('프로필 정보를 불러오는 중...', style: TextStyle(color: Color(0xFF6B7280))),
          ],
        ),
      ));
    }
    if (_error != null) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(_error!),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: _fetch, child: const Text('다시 시도')),
        ],
      ));
    }
    final p = _profile;
    if (p == null) {
      return const Center(child: Text('프로필 정보가 없습니다'));
    }

    final bmi = _calculateBmi();
    final age = _age();
    final allergies = p['allergies']?.toString();
    final dietGoal = p['dietGoal']?.toString();
    final activityLevel = p['activityLevel']?.toString();

    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
        children: [
          // 헤더
          Container(
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('나의 맞춤', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('${p['name'] ?? ''}님을 위한 건강 관리',
                          style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.logout, color: Color(0xFF6B7280)),
                  tooltip: '로그아웃',
                  onPressed: _logout,
                ),
              ],
            ),
          ),

          // 이메일 미인증 배너
          if (p['emailVerified'] == false)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: _EmailVerificationBanner(email: p['email']?.toString() ?? ''),
            ),

          // 프로필 미완성 CTA
          if (_isProfileIncomplete)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: InkWell(
                onTap: () async {
                  final updated = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(builder: (_) => ProfileEditScreen(profile: p)),
                  );
                  if (updated == true) _fetch();
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_accentGreen, _accentGreenDeep],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                        child: const Icon(Icons.auto_awesome, color: _accentGreen, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('정보 입력 마저하기',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                            SizedBox(height: 4),
                            Text('키, 몸무게, 활동량 등을 입력하면\n맞춤 칼로리와 식단 추천을 받을 수 있어요',
                                style: TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF1F2937))),
                            SizedBox(height: 8),
                            Text('지금 입력하기 →',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 기본 정보 카드
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFF9FAFB), Colors.white],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                children: [
                  InkWell(
                    onTap: () async {
                      final updated = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(builder: (_) => ProfileEditScreen(profile: p)),
                      );
                      if (updated == true) _fetch();
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: const BoxDecoration(color: _accentGreen, shape: BoxShape.circle),
                            child: const Icon(Icons.person, size: 24, color: Colors.black),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p['name']?.toString() ?? '',
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                  age != null && p['gender'] != null
                                      ? '${age}세 · ${p['gender'] == '남' ? '남성' : p['gender'] == '여' ? '여성' : p['gender']}'
                                      : '프로필 정보를 완성해주세요',
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
                        ],
                      ),
                    ),
                  ),
                  if (p['height'] != null || p['weight'] != null) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        if (p['height'] != null) Expanded(child: _infoTile('키', '${p['height']} cm')),
                        if (p['height'] != null && p['weight'] != null) const SizedBox(width: 12),
                        if (p['weight'] != null) Expanded(child: _infoTile('몸무게', '${p['weight']} kg')),
                      ],
                    ),
                    if (bmi != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _infoTile('BMI', bmi.bmi.toStringAsFixed(1))),
                          const SizedBox(width: 12),
                          Expanded(child: _infoTile('상태', bmi.label, valueColor: bmi.color)),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),

          // 일일 권장 칼로리
          if (p['recommendedCalories'] != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.local_fire_department, color: _accentGreen, size: 20),
                        SizedBox(width: 8),
                        Text('일일 권장 칼로리',
                            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('${formatThousands(p['recommendedCalories'] as num)} kcal',
                        style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('${dietGoal ?? ''} 목표 기준',
                        style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 13)),
                  ],
                ),
              ),
            ),

          // 건강 목표
          if (dietGoal != null || activityLevel != null) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Text('건강 목표', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            if (dietGoal != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: _healthGoalTile(Icons.flag, const Color(0xFF2563EB), '식단 목표', dietGoal),
              ),
            if (activityLevel != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: _healthGoalTile(Icons.directions_run, const Color(0xFF16A34A), '활동량', activityLevel),
              ),
          ],

          // 알림 센터 진입
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: InkWell(
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationCenterScreen()),
                );
                // 알림 센터에서 read-all 호출하므로 돌아오면 unread는 0
                if (mounted) setState(() => _unreadCount = 0);
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.notifications_none, color: Colors.black, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('알림',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          SizedBox(height: 2),
                          Text('받은 알림 내역 (가족 활동 / 멤버 변경)',
                              style: TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                        ],
                      ),
                    ),
                    if (_unreadCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _unreadCount > 99 ? '99+' : '$_unreadCount',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
                  ],
                ),
              ),
            ),
          ),

          // 냉장고 관리 진입
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FridgeManagementScreen()),
              ),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.kitchen_outlined, color: Colors.black, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('냉장고 관리',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          SizedBox(height: 2),
                          Text('가족 공유, 초대 코드, 김치냉장고 추가 등',
                              style: TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
                  ],
                ),
              ),
            ),
          ),

          // 가족 활동 통계 진입
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FamilyActivityScreen()),
              ),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.insights, color: Colors.black, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('가족 활동',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          SizedBox(height: 2),
                          Text('멤버별 추가/소비 + 자주 사는 식재료 TOP',
                              style: TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
                  ],
                ),
              ),
            ),
          ),

          // 알림 설정
          const NotificationSettingsSection(),

          // 알레르기 정보
          if (allergies != null && allergies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFECACA), width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.warning_amber, color: Color(0xFFDC2626), size: 20),
                        SizedBox(width: 8),
                        Text('알레르기 주의',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF7F1D1D))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(allergies, style: const TextStyle(fontSize: 14, color: Color(0xFF991B1B), height: 1.5)),
                    const SizedBox(height: 12),
                    const Text('⚠️ 레시피 추천 시 해당 식재료는 제외됩니다',
                        style: TextStyle(fontSize: 11, color: Color(0xFFDC2626))),
                  ],
                ),
              ),
            ),

          // 맞춤 기능 바로가기
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Text('맞춤 기능', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.6,
              children: [
                _featureCard(
                  '맞춤 레시피',
                  Icons.restaurant_menu,
                  Colors.black,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_accentGreen, _accentGreenDeep],
                  ),
                  textColor: Colors.black,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecipesScreen())),
                ),
                _featureCard(
                  '식단 계획',
                  Icons.calendar_month,
                  const Color(0xFF2563EB),
                  bgColor: const Color(0xFFEFF6FF),
                  borderColor: const Color(0xFFBFDBFE),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MealPlanScreen()),
                  ),
                ),
                _featureCard(
                  '소비 우선순위',
                  Icons.trending_up,
                  const Color(0xFFEA580C),
                  bgColor: const Color(0xFFFFF7ED),
                  borderColor: const Color(0xFFFED7AA),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PriorityScreen())),
                ),
                _featureCard(
                  '영양 분석',
                  Icons.favorite,
                  const Color(0xFF16A34A),
                  bgColor: const Color(0xFFF0FDF4),
                  borderColor: const Color(0xFFBBF7D0),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NutritionScreen())),
                ),
              ],
            ),
          ),

          // 권장 영양소 비율
          if (dietGoal != null) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Text('권장 영양소 비율', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    _ratioRow('탄수화물', '50-60%', 0.55, const Color(0xFF3B82F6)),
                    const SizedBox(height: 16),
                    _ratioRow(
                      '단백질',
                      dietGoal == '근육량 증가' ? '25-30%' : '15-20%',
                      dietGoal == '근육량 증가' ? 0.27 : 0.17,
                      const Color(0xFFEF4444),
                    ),
                    const SizedBox(height: 16),
                    _ratioRow('지방', '20-25%', 0.22, const Color(0xFFEAB308)),
                    const SizedBox(height: 16),
                    Text('* $dietGoal 목표에 최적화된 비율입니다',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                  ],
                ),
              ),
            ),
          ],

          // 회원 탈퇴
          Container(
            margin: const EdgeInsets.only(top: 24),
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFF3F4F6))),
            ),
            child: Center(
              child: TextButton(
                onPressed: _deleteAccount,
                child: const Text(
                  '회원 탈퇴',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoTile(String label, String value, {Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF3F4F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: valueColor ?? Colors.black,
          )),
        ],
      ),
    );
  }

  Widget _healthGoalTile(IconData icon, Color iconColor, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _featureCard(
    String title,
    IconData icon,
    Color iconColor, {
    LinearGradient? gradient,
    Color? bgColor,
    Color? borderColor,
    Color textColor = Colors.black,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: gradient,
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: borderColor != null ? Border.all(color: borderColor) : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ratioRow(String label, String pct, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            const Spacer(),
            Text(pct, style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 8,
            backgroundColor: const Color(0xFFE5E7EB),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

// 이메일 미인증 배너 — 재발송 버튼 포함. 자체 상태 관리.
class _EmailVerificationBanner extends StatefulWidget {
  final String email;
  const _EmailVerificationBanner({required this.email});

  @override
  State<_EmailVerificationBanner> createState() => _EmailVerificationBannerState();
}

class _EmailVerificationBannerState extends State<_EmailVerificationBanner> {
  bool _sending = false;
  bool _sent = false;

  Future<void> _resend() async {
    setState(() => _sending = true);
    try {
      final res = await ApiClient.post('/user/resend-verification');
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        setState(() => _sent = true);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(data['message']?.toString() ?? '재발송 실패'),
        ));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('서버 연결 실패')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEFCE8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFEF08A), width: 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Color(0xFFFACC15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.warning_amber, color: Color(0xFF713F12), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('이메일 인증을 완료해주세요',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF713F12))),
                const SizedBox(height: 4),
                Text(
                  '${widget.email}로 보낸 인증 메일을 확인해주세요.',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF713F12), height: 1.4),
                ),
                const SizedBox(height: 8),
                if (_sent)
                  const Text('✓ 인증 메일을 다시 보냈어요. 메일함을 확인해주세요.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF15803D), fontWeight: FontWeight.w600))
                else
                  GestureDetector(
                    onTap: _sending ? null : _resend,
                    child: Text(
                      _sending ? '전송 중...' : '메일 다시 받기',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF713F12),
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
