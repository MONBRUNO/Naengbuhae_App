// 식재료별 기본값 (카테고리/보관/유통기한 일수).
// 사용자가 이름을 입력하면 카테고리와 보관 상태가 자동으로 채워지고,
// 유통기한 자동 설정 모드에서는 expiryDays로 만료일이 계산된다.

class IngredientDefault {
  final String? category;
  final String? storage;
  final int expiryDays;
  const IngredientDefault({this.category, this.storage, required this.expiryDays});
}

const Map<String, IngredientDefault> ingredientDefaults = {
  // 채소
  '상추': IngredientDefault(category: '채소', storage: '냉장', expiryDays: 7),
  '양상추': IngredientDefault(category: '채소', storage: '냉장', expiryDays: 7),
  '양배추': IngredientDefault(category: '채소', storage: '냉장', expiryDays: 14),
  '당근': IngredientDefault(category: '채소', storage: '냉장', expiryDays: 21),
  '오이': IngredientDefault(category: '채소', storage: '냉장', expiryDays: 7),
  '토마토': IngredientDefault(category: '채소', storage: '냉장', expiryDays: 7),
  '감자': IngredientDefault(category: '채소', storage: '실온', expiryDays: 30),
  '고구마': IngredientDefault(category: '채소', storage: '실온', expiryDays: 30),
  '브로콜리': IngredientDefault(category: '채소', storage: '냉장', expiryDays: 7),
  '시금치': IngredientDefault(category: '채소', storage: '냉장', expiryDays: 5),
  '대파': IngredientDefault(category: '채소', storage: '냉장', expiryDays: 14),
  '양파': IngredientDefault(category: '채소', storage: '실온', expiryDays: 30),
  '마늘': IngredientDefault(category: '채소', storage: '실온', expiryDays: 30),

  // 육류 / 가공육
  '소고기': IngredientDefault(category: '육류', storage: '냉장', expiryDays: 3),
  '돼지고기': IngredientDefault(category: '육류', storage: '냉장', expiryDays: 3),
  '닭고기': IngredientDefault(category: '육류', storage: '냉장', expiryDays: 2),
  '닭가슴살': IngredientDefault(category: '육류', storage: '냉장', expiryDays: 2),
  '햄': IngredientDefault(category: '육류', storage: '냉장', expiryDays: 14),
  '베이컨': IngredientDefault(category: '육류', storage: '냉장', expiryDays: 14),
  '소시지': IngredientDefault(category: '육류', storage: '냉장', expiryDays: 14),

  // 유제품
  '우유': IngredientDefault(category: '유제품', storage: '냉장', expiryDays: 7),
  '요거트': IngredientDefault(category: '유제품', storage: '냉장', expiryDays: 14),
  '치즈': IngredientDefault(category: '유제품', storage: '냉장', expiryDays: 30),
  '버터': IngredientDefault(category: '유제품', storage: '냉장', expiryDays: 30),

  // 해산물
  '생선': IngredientDefault(category: '해산물', storage: '냉장', expiryDays: 2),
  '새우': IngredientDefault(category: '해산물', storage: '냉동', expiryDays: 30),
  '오징어': IngredientDefault(category: '해산물', storage: '냉동', expiryDays: 30),
  '연어': IngredientDefault(category: '해산물', storage: '냉장', expiryDays: 2),

  // 과일
  '사과': IngredientDefault(category: '과일', storage: '냉장', expiryDays: 14),
  '배': IngredientDefault(category: '과일', storage: '냉장', expiryDays: 14),
  '바나나': IngredientDefault(category: '과일', storage: '실온', expiryDays: 7),
  '딸기': IngredientDefault(category: '과일', storage: '냉장', expiryDays: 5),
  '포도': IngredientDefault(category: '과일', storage: '냉장', expiryDays: 7),
  '귤': IngredientDefault(category: '과일', storage: '냉장', expiryDays: 14),

  // 곡물
  '쌀': IngredientDefault(category: '곡물', storage: '실온', expiryDays: 180),
  '식빵': IngredientDefault(category: '곡물', storage: '실온', expiryDays: 7),
  '라면': IngredientDefault(category: '곡물', storage: '실온', expiryDays: 180),

  // 기타
  '계란': IngredientDefault(category: '기타', storage: '냉장', expiryDays: 21),
  '두부': IngredientDefault(category: '기타', storage: '냉장', expiryDays: 7),
  '만두': IngredientDefault(category: '기타', storage: '냉동', expiryDays: 60),
  '아이스크림': IngredientDefault(category: '기타', storage: '냉동', expiryDays: 90),
};

const int _fallbackExpiryDays = 7;

DateTime defaultExpirationDate(String ingredientName, DateTime purchaseDate) {
  final d = ingredientDefaults[ingredientName.trim()];
  return purchaseDate.add(Duration(days: d?.expiryDays ?? _fallbackExpiryDays));
}

// 이름으로 카테고리/보관 등 lookup. 일치하는 게 없으면 null.
IngredientDefault? lookupIngredient(String name) {
  return ingredientDefaults[name.trim()];
}
