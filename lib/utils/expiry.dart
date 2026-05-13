import 'package:flutter/material.dart';

// 웹의 utils/date.ts와 같은 역할.
// D-day 계산 + 상태별 색상.

enum ExpiryStatus { danger, warning, safe }

int calculateDDay(String? expirationDate) {
  if (expirationDate == null || expirationDate.isEmpty) return 9999;
  final exp = DateTime.tryParse(expirationDate);
  if (exp == null) return 9999;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(exp.year, exp.month, exp.day);
  return target.difference(today).inDays;
}

String formatDDay(int days) {
  if (days < 0) return 'D+${-days}';
  if (days == 0) return 'D-Day';
  return 'D-$days';
}

ExpiryStatus getExpiryStatus(int days) {
  if (days <= 0) return ExpiryStatus.danger;
  if (days <= 3) return ExpiryStatus.warning;
  return ExpiryStatus.safe;
}

Color statusColor(ExpiryStatus s) {
  switch (s) {
    case ExpiryStatus.danger:
      return const Color(0xFFFF3B30);
    case ExpiryStatus.warning:
      return const Color(0xFFFFD60A);
    case ExpiryStatus.safe:
      return const Color(0xFF34C759);
  }
}

String statusLabel(ExpiryStatus s) {
  switch (s) {
    case ExpiryStatus.danger:
      return '위험';
    case ExpiryStatus.warning:
      return '주의';
    case ExpiryStatus.safe:
      return '안전';
  }
}
