import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../state/notification_settings.dart';

// 프로필 화면에 들어가는 알림 설정 섹션.
// 마스터/유통기한/식단 토글 + 식사 시간 3개. 변경 시 NotificationService에 재스케줄 요청.
class NotificationSettingsSection extends StatelessWidget {
  const NotificationSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.notifications_outlined, size: 18),
                SizedBox(width: 8),
                Text('알림 설정', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<bool>(
              valueListenable: NotificationSettings.masterEnabled,
              builder: (_, master, __) => Column(
                children: [
                  _toggleRow(
                    title: '전체 알림',
                    subtitle: '모든 알림을 한 번에 켜고 끌 수 있어요',
                    value: master,
                    onChanged: (v) async {
                      await NotificationSettings.setMasterEnabled(v);
                      if (v) {
                        await NotificationService.rescheduleFromCache();
                      } else {
                        await NotificationService.cancelAll();
                      }
                    },
                  ),
                  const Divider(height: 24),
                  // 유통기한
                  ValueListenableBuilder<bool>(
                    valueListenable: NotificationSettings.expiryEnabled,
                    builder: (_, expiry, __) => _toggleRow(
                      title: '유통기한 임박 알림',
                      subtitle: '매일 오전 9시 · 임박 식재료 안내',
                      value: expiry,
                      enabled: master,
                      onChanged: (v) async {
                        await NotificationSettings.setExpiryEnabled(v);
                        await NotificationService.rescheduleFromCache();
                      },
                    ),
                  ),
                  const Divider(height: 24),
                  // 식단
                  ValueListenableBuilder<bool>(
                    valueListenable: NotificationSettings.mealEnabled,
                    builder: (_, meal, __) => Column(
                      children: [
                        _toggleRow(
                          title: '식단 추천 알림',
                          subtitle: '각 식사 10분 전에 추천 식단 안내',
                          value: meal,
                          enabled: master,
                          onChanged: (v) async {
                            await NotificationSettings.setMealEnabled(v);
                            await NotificationService.rescheduleFromCache();
                          },
                        ),
                        if (master && meal) ...[
                          const SizedBox(height: 8),
                          _mealTimeRow(
                            context,
                            '아침',
                            NotificationSettings.breakfastTime,
                            NotificationSettings.setBreakfastTime,
                          ),
                          _mealTimeRow(
                            context,
                            '점심',
                            NotificationSettings.lunchTime,
                            NotificationSettings.setLunchTime,
                          ),
                          _mealTimeRow(
                            context,
                            '저녁',
                            NotificationSettings.dinnerTime,
                            NotificationSettings.setDinnerTime,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggleRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeThumbColor: Colors.black,
            activeTrackColor: const Color(0xFFCDFF00),
          ),
        ],
      ),
    );
  }

  Widget _mealTimeRow(
    BuildContext context,
    String label,
    ValueNotifier<TimeOfDay> notifier,
    Future<void> Function(TimeOfDay) setter,
  ) {
    return ValueListenableBuilder<TimeOfDay>(
      valueListenable: notifier,
      builder: (_, time, __) => InkWell(
        onTap: () async {
          final picked = await showTimePicker(
            context: context,
            initialTime: time,
            initialEntryMode: TimePickerEntryMode.dial,
          );
          if (picked != null) {
            await setter(picked);
            await NotificationService.rescheduleFromCache();
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(label,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
              ),
              Expanded(
                child: Text(
                  time.format(context),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.access_time, size: 16, color: Color(0xFF9CA3AF)),
            ],
          ),
        ),
      ),
    );
  }
}
