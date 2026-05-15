import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../screens/fridge_management_screen.dart';
import '../state/fridge_context.dart';
import '../utils/theme_colors.dart';

// 현재 선택된 냉장고를 표시하고, 탭하면 다른 냉장고로 전환할 수 있는 버튼.
// 메인 탭 화면들 헤더에 배치.
class FridgeSelectorButton extends StatelessWidget {
  const FridgeSelectorButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: FridgeContext.selected,
      builder: (context, current, _) {
        final name = current?['name']?.toString() ?? '냉장고 없음';
        return InkWell(
          onTap: () => _openSheet(context),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.refrigerator, size: 14),
                const SizedBox(width: 6),
                Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(width: 4),
                const Icon(Icons.expand_more, size: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => const _FridgeSwitcherSheet(),
    );
  }
}

class _FridgeSwitcherSheet extends StatelessWidget {
  const _FridgeSwitcherSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ValueListenableBuilder<List<Map<String, dynamic>>>(
        valueListenable: FridgeContext.fridges,
        builder: (context, list, _) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('냉장고 전환',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 8),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32, horizontal: 20),
                  child: Text('냉장고가 없습니다', style: TextStyle(color: Color(0xFF9CA3AF))),
                )
              else
                ...list.map((f) {
                  final isSelected = f['id'] == FridgeContext.selectedId;
                  return ListTile(
                    leading: Icon(
                      isSelected ? LucideIcons.refrigerator : LucideIcons.refrigerator,
                      color: isSelected ? context.textColor : const Color(0xFF9CA3AF),
                    ),
                    title: Text(f['name']?.toString() ?? '',
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        )),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: Color(0xFF22C55E))
                        : null,
                    onTap: () async {
                      await FridgeContext.select(f);
                      if (context.mounted) Navigator.pop(context);
                    },
                  );
                }),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.settings_outlined, color: Color(0xFF6B7280)),
                title: const Text('냉장고 관리',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FridgeManagementScreen()),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }
}
