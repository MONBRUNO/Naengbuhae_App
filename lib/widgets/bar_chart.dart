import 'package:flutter/material.dart';

// 웹의 recharts BarChart 단순화 버전. 막대 위에 값, 아래에 라벨.
class SimpleBarChart extends StatelessWidget {
  final List<BarItem> items;
  final double height;

  const SimpleBarChart({super.key, required this.items, this.height = 150});

  @override
  Widget build(BuildContext context) {
    final maxValue = items.fold<int>(0, (m, e) => e.value > m ? e.value : m);
    final scale = maxValue == 0 ? 1.0 : maxValue.toDouble();

    // 막대 외 고정 영역: 값 텍스트(~14) + spacing(2) + spacing(6) + 라벨(~14) = ~36
    // 여유 두고 50px 차감해서 오버플로우 방지.
    final maxBarHeight = (height - 50).clamp(20.0, height);

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: items.map((item) {
          final h = maxBarHeight * (item.value / scale);
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${item.value}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 2),
                  Container(
                    height: item.value == 0 ? 4 : h.clamp(8, maxBarHeight),
                    decoration: BoxDecoration(
                      color: item.value == 0 ? const Color(0xFFE5E7EB) : item.color,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        topRight: Radius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(item.label, style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class BarItem {
  final String label;
  final int value;
  final Color color;
  const BarItem(this.label, this.value, this.color);
}
