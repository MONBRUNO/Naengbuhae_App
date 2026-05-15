import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/api_client.dart';

const _accentGreen = Color(0xFFCDFF00);

const _activityLevels = ['거의 움직임 없음', '가벼운 활동', '보통 활동', '많은 활동', '매우 많은 활동'];
const _dietGoals = ['체중 감량', '체중 유지', '근육량 증가', '건강 관리'];

// 웹의 SignUp.tsx에 대응. POST /user/signup.
// 백엔드 응답이 success/message 기반(HTTP 200이어도 success=false 가능).
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _passwordConfirm = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _allergies = TextEditingController();
  String _gender = '남';
  DateTime _birthDate = DateTime(1995, 1, 1);
  String _activityLevel = _activityLevels[2];
  String _dietGoal = _dietGoals[1];
  bool _showPassword = false;
  bool _submitting = false;
  // 이메일 인증 흐름: 발송된 이메일/검증 완료된 이메일을 따로 기억해
  // "이메일을 바꾸면 다시 인증 필요" 규칙을 강제한다.
  String? _codeSentTo;
  String? _verifiedEmail;
  bool _sendingCode = false;
  bool _verifyingCode = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    _name.dispose();
    _email.dispose();
    _code.dispose();
    _height.dispose();
    _weight.dispose();
    _allergies.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _email.text.trim();
    if (email.isEmpty || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _snack('올바른 이메일을 입력해주세요');
      return;
    }
    setState(() => _sendingCode = true);
    try {
      final res = await ApiClient.post('/user/email/send-code', body: {'email': email});
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        setState(() {
          _codeSentTo = email;
          _verifiedEmail = null;
          _code.clear();
        });
      } else {
        _snack(data['message']?.toString() ?? '발송에 실패했습니다');
      }
    } catch (_) {
      _snack('서버 연결에 실패했습니다');
    } finally {
      if (mounted) setState(() => _sendingCode = false);
    }
  }

  Future<void> _verifyCode() async {
    final sentTo = _codeSentTo;
    if (sentTo == null) return;
    if (_code.text.trim().length != 6) {
      _snack('6자리 인증번호를 입력해주세요');
      return;
    }
    setState(() => _verifyingCode = true);
    try {
      final res = await ApiClient.post('/user/email/verify-code', body: {
        'email': sentTo,
        'code': _code.text.trim(),
      });
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        setState(() => _verifiedEmail = sentTo);
        _snack('이메일 인증이 완료되었어요');
      } else {
        _snack(data['message']?.toString() ?? '인증에 실패했습니다');
      }
    } catch (_) {
      _snack('서버 연결에 실패했습니다');
    } finally {
      if (mounted) setState(() => _verifyingCode = false);
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_password.text != _passwordConfirm.text) {
      _snack('비밀번호가 일치하지 않습니다');
      return;
    }
    if (_verifiedEmail == null || _verifiedEmail != _email.text.trim()) {
      _snack('이메일 인증을 먼저 완료해주세요');
      return;
    }
    setState(() => _submitting = true);
    try {
      final res = await ApiClient.post('/user/signup', body: {
        'username': _username.text.trim(),
        'password': _password.text,
        'name': _name.text.trim(),
        'gender': _gender,
        'birthDate': _formatDate(_birthDate),
        'height': double.parse(_height.text),
        'weight': double.parse(_weight.text),
        'email': _email.text.trim(),
        'activityLevel': _activityLevel,
        'dietGoal': _dietGoal,
        'allergies': _allergies.text.trim(),
      });

      String? message;
      bool success = false;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map) {
          success = data['success'] == true;
          message = data['message']?.toString();
        }
      } else {
        message = _extractError(res.body) ?? '회원가입 실패 (${res.statusCode})';
      }

      if (success) {
        _snack(message ?? '회원가입 성공! 로그인해주세요.');
        if (!mounted) return;
        Navigator.of(context).pop();
      } else {
        _snack(message ?? '회원가입에 실패했습니다.');
      }
    } catch (_) {
      _snack('서버 연결 실패');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _extractError(String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map) {
        return data['message']?.toString() ?? data['error']?.toString();
      }
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
      appBar: AppBar(title: const Text('회원가입')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _sectionTitle('계정 정보'),
            _label('아이디'),
            TextFormField(
              controller: _username,
              autocorrect: false,
              decoration: _inputDecoration('영문 + 숫자 6자 이상'),
              validator: (v) {
                final s = (v ?? '').trim();
                if (s.isEmpty) return '아이디를 입력해주세요';
                if (!RegExp(r'^(?=.*[a-zA-Z])(?=.*\d)[a-zA-Z0-9]{6,}$').hasMatch(s)) {
                  return '영문, 숫자 조합 6자 이상';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            _label('비밀번호'),
            TextFormField(
              controller: _password,
              obscureText: !_showPassword,
              decoration: _inputDecoration('비밀번호').copyWith(
                suffixIcon: IconButton(
                  icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
              validator: (v) => (v == null || v.isEmpty) ? '비밀번호를 입력해주세요' : null,
            ),
            const SizedBox(height: 12),
            _label('비밀번호 확인'),
            TextFormField(
              controller: _passwordConfirm,
              obscureText: !_showPassword,
              decoration: _inputDecoration('다시 입력'),
              validator: (v) => (v == null || v.isEmpty) ? '비밀번호를 다시 입력해주세요' : null,
            ),
            const SizedBox(height: 24),
            _sectionTitle('기본 정보'),
            _label('이름'),
            TextFormField(
              controller: _name,
              decoration: _inputDecoration('이름'),
              validator: (v) => (v == null || v.trim().isEmpty) ? '이름을 입력해주세요' : null,
            ),
            const SizedBox(height: 12),
            _label('이메일'),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    enabled: _verifiedEmail != _email.text.trim() || _verifiedEmail == null,
                    decoration: _inputDecoration('email@example.com'),
                    onChanged: (v) {
                      // 이메일을 바꾸면 기존 인증 상태 무효화
                      if (_verifiedEmail != null && _verifiedEmail != v.trim()) {
                        setState(() {
                          _verifiedEmail = null;
                          _codeSentTo = null;
                          _code.clear();
                        });
                      }
                    },
                    validator: (v) {
                      final s = (v ?? '').trim();
                      if (s.isEmpty) return '이메일을 입력해주세요';
                      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) return '이메일 형식이 올바르지 않습니다';
                      if (_verifiedEmail != s) return '이메일 인증을 완료해주세요';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                if (_verifiedEmail != null && _verifiedEmail == _email.text.trim())
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.check, size: 16, color: Color(0xFF16A34A)),
                        SizedBox(width: 4),
                        Text('인증완료',
                            style: TextStyle(fontSize: 13, color: Color(0xFF16A34A), fontWeight: FontWeight.w700)),
                      ],
                    ),
                  )
                else
                  ElevatedButton(
                    onPressed: _sendingCode ? null : _sendCode,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(_sendingCode ? '전송 중...' : _codeSentTo != null ? '재발송' : '인증번호'),
                  ),
              ],
            ),
            // 코드 발송된 상태고 아직 검증 안 됐을 때만 입력 행 노출
            if (_codeSentTo != null && _verifiedEmail != _codeSentTo) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: _inputDecoration('6자리 인증번호').copyWith(counterText: ''),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _verifyingCode ? null : _verifyCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFCDFF00),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(_verifyingCode ? '확인 중...' : '확인'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  '${_codeSentTo!}로 보낸 코드를 입력해주세요 (10분 유효)',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                ),
              ),
            ],
            const SizedBox(height: 12),
            _label('성별'),
            Row(
              children: ['남', '여'].asMap().entries.map((entry) {
                final i = entry.key;
                final g = entry.value;
                final selected = g == _gender;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i == 0 ? 8 : 0),
                    child: GestureDetector(
                      onTap: () => setState(() => _gender = g),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: selected ? Colors.black : const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            g,
                            style: TextStyle(
                              color: selected ? Colors.white : const Color(0xFF6B7280),
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            _label('생년월일'),
            InkWell(
              onTap: _pickBirthDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    Expanded(child: Text(_formatDate(_birthDate))),
                    const Icon(Icons.calendar_today_outlined, size: 18, color: Colors.grey),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('키 (cm)'),
                      TextFormField(
                        controller: _height,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _inputDecoration('170'),
                        validator: _numberValidator,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('몸무게 (kg)'),
                      TextFormField(
                        controller: _weight,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _inputDecoration('65'),
                        validator: _numberValidator,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _sectionTitle('건강 정보'),
            _label('활동량'),
            DropdownButtonFormField<String>(
              value: _activityLevel,
              decoration: _inputDecoration(null),
              items: _activityLevels.map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
              onChanged: (v) => setState(() => _activityLevel = v ?? _activityLevels[2]),
            ),
            const SizedBox(height: 12),
            _label('식단 목표'),
            DropdownButtonFormField<String>(
              value: _dietGoal,
              decoration: _inputDecoration(null),
              items: _dietGoals.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
              onChanged: (v) => setState(() => _dietGoal = v ?? _dietGoals[1]),
            ),
            const SizedBox(height: 12),
            _label('알레르기 정보 (선택)'),
            TextFormField(
              controller: _allergies,
              decoration: _inputDecoration('예) 우유, 땅콩, 새우'),
              maxLines: 2,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentGreen,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  _submitting ? '가입 중...' : '가입하기',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _numberValidator(String? v) {
    if (v == null || v.isEmpty) return '필수';
    final d = double.tryParse(v);
    if (d == null || d <= 0) return '0보다 큰 수';
    return null;
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      );

  InputDecoration _inputDecoration(String? hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _accentGreen, width: 2),
        ),
      );
}
