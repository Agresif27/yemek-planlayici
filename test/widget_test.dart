import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yemek_planlayici/app_state.dart';
import 'package:yemek_planlayici/data.dart';

void main() {
  setUpAll(() {
    expect(Catalog.apply(File('assets/catalog.json').readAsStringSync()), true);
  });

  test('her öğün için en az 100 tarif; her diyette de bol seçenek', () {
    final animal = {for (final i in allItems.where((i) => i.animal)) i.name};
    final meat = {for (final i in allItems.where((i) => i.meat)) i.name};
    for (var m = 0; m < 3; m++) {
      final rs = recipes.where((r) => r.meals.contains(m)).toList();
      expect(rs.length >= 100, true, reason: 'öğün $m: ${rs.length}');
      expect(rs.where((r) => r.ing.keys.every((k) => !meat.contains(k))).length >= 20, true);
      expect(rs.where((r) => r.ing.keys.every((k) => !animal.contains(k))).length >= 20, true);
    }
  });

  test('tarif malzemeleri katalogda var, id\'ler benzersiz', () {
    expect(recipes.map((r) => r.id).toSet().length, recipes.length);
    for (final r in recipes) {
      for (final n in r.ing.keys) {
        expect(items.containsKey(n), true, reason: '${r.id}: $n');
      }
    }
  });

  test('bozuk veya eski katalog reddedilir', () {
    final v = catalogVersion;
    expect(Catalog.apply('{bozuk'), false);
    expect(Catalog.apply('{"version":$v,"items":[],"recipes":[]}'), false);
    expect(catalogVersion, v);
  });

  test('her diyette 21 slot dolar, öğüne uygun ve filtreye uyar', () {
    for (final diet in [0, 1, 2]) {
      final s = AppState()..diet = diet;
      s.generatePlan();
      expect(s.plan.where((e) => e != null).length, 21, reason: 'diet $diet');
      expect(s.plan.toSet().length, 21, reason: 'tekrar yok (diet $diet)');
      for (var i = 0; i < 21; i++) {
        final r = s.recipe(s.plan[i]!);
        expect(s.allowed(r), true);
        expect(r.meals.contains(i % 3), true, reason: r.id);
      }
    }
  });

  test('evdeki malzeme listeden düşer, kaldırılan tarif plandan temizlenir', () {
    final s = AppState()..generatePlan();
    s.selectCommon();
    expect(s.shopping.every((e) => !s.owned.contains(e.key.name)), true);
    s.plan[0] = 'yok-boyle-tarif';
    s.reconcile();
    expect(s.plan[0], null);
  });
}
