// 천 단위 콤마. 1800 → "1,800".
String formatThousands(num n) {
  final s = n.toInt().toString();
  return s.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
}
