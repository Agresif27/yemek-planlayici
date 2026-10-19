import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yemek_planlayici/main.dart';
import 'package:yemek_planlayici/app_state.dart';
import 'package:yemek_planlayici/data.dart';
import 'package:yemek_planlayici/ui.dart' as ui;

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

  test('Türkçe arama harf farklarını tolere eder', () {
    expect(ui.matches('Pırasa', 'pirasa'), true);
    expect(ui.matches('Şehriye', 'SEHR'), true);
    expect(ui.matches('İrmik', 'irm'), true);
    expect(ui.matches('Domates', 'patates'), false);
  });

  test('özel ürün ve tarif eklenir, katalog güncellense de korunur', () {
    final s = AppState();
    const kuzu = Item('Test hindisi', '🦃', 'Et & Balık', 'g', 0.5, meat: true, animal: true);
    expect(s.addCustomItem(kuzu), true);
    expect(s.addCustomItem(const Item('TEST hindisi', '🦃', 'Kiler', 'g', 0)), false,
        reason: 'aynı ad (büyük/küçük harf farkıyla) eklenemez');
    expect(s.addCustomItem(const Item('domates', '🍅', 'Sebze', 'g', 0)), false,
        reason: 'katalogdaki ürünle aynı ad');
    expect(items.containsKey('Test hindisi'), true);

    final r = Recipe('ozel-1', 'Benim hindim', '🦃', 20, [2], {'Test hindisi': 150, 'Pirinç': 60}, ['Pişir.']);
    s.addCustomRecipe(r);
    expect(recipes.any((x) => x.id == 'ozel-1'), true);
    expect(r.isCustom, true);

    s.diet = 1; // vejetaryen: et içeren özel tarif elenir
    expect(s.allowed(s.recipe('ozel-1')), false);
    s.diet = 0;
    expect(s.allowed(s.recipe('ozel-1')), true);

    final j = jsonDecode(File('assets/catalog.json').readAsStringSync()) as Map<String, dynamic>;
    j['version'] = catalogVersion + 1;
    expect(Catalog.apply(jsonEncode(j)), true);
    expect(items.containsKey('Test hindisi'), true);
    expect(recipes.any((x) => x.id == 'ozel-1'), true);

    expect(s.removeCustomItem('Test hindisi'), false, reason: 'tarifte kullanılıyor');
    s.removeCustomRecipe('ozel-1');
    expect(s.removeCustomItem('Test hindisi'), true);
    expect(items.containsKey('Test hindisi'), false);
  });

  test('alışveriş listesine elle eklenenler', () {
    final s = AppState();
    expect(s.addExtra('2 kg elma'), true);
    expect(s.addExtra('2 kg elma'), false);
    expect(s.addExtra('   '), false);
    s.toggleBought('x:2 kg elma');
    expect(s.bought.contains('x:2 kg elma'), true);
    s.removeExtra('2 kg elma');
    expect(s.extras, isEmpty);
    expect(s.bought.contains('x:2 kg elma'), false);
  });

  testWidgets('sekmeler açılır; arama, ürün ekleme ve tarif ekleme ekranı çalışır', (t) async {
    await t.pumpWidget(const YemekApp());
    Future<void> goTab(String label) async {
      await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
      await t.pumpAndSettle();
    }

    // Plan oluştur
    await goTab('Plan');
    await t.tap(find.text('Plan oluştur'));
    await t.pumpAndSettle();
    expect(find.text('Pazartesi'), findsOneWidget);

    // Evde Var: arama (Türkçe harfsiz) ve yeni ürün ekleme
    await goTab('Evde Var');
    await t.enterText(find.byType(TextField).first, 'pirasa');
    await t.pumpAndSettle();
    expect(find.text('🥬 Pırasa'), findsOneWidget);
    expect(find.text('🍅 Domates'), findsNothing);
    await t.tap(find.byIcon(Icons.add).first);
    await t.pumpAndSettle();
    expect(find.text('Yeni ürün ekle'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'Ürün adı'), 'Test enginar');
    await t.tap(find.widgetWithText(FilledButton, 'Ekle'));
    await t.pumpAndSettle();
    expect(items.containsKey('Test enginar'), true);
    expect(state.owned.contains('Test enginar'), true);

    // Liste: elle ürün ekleme ve arama
    await goTab('Liste');
    await t.tap(find.byIcon(Icons.add).first);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, '2 kg elma');
    await t.tap(find.widgetWithText(FilledButton, 'Ekle'));
    await t.pumpAndSettle();
    expect(find.text('2 kg elma'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, 'elma');
    await t.pumpAndSettle();
    expect(find.text('2 kg elma'), findsOneWidget);

    // Tercihler: sevmediğim yiyeceklerde arama
    await goTab('Tercihler');
    await t.enterText(find.byType(TextField).first, 'enginar');
    await t.pumpAndSettle();
    expect(find.text('🛒 Test enginar'), findsOneWidget);

    // Tarifler: liste, arama, tarif ekleme sayfası ve doğrulama
    await goTab('Tarifler');
    expect(find.textContaining(' tarif'), findsWidgets);
    await t.enterText(find.byType(TextField).first, 'menemen');
    await t.pumpAndSettle();
    expect(find.text('Menemen'), findsOneWidget);
    await t.tap(find.byIcon(Icons.add).first);
    await t.pumpAndSettle();
    expect(find.text('Yeni tarif'), findsOneWidget);
    await t.tap(find.widgetWithText(TextButton, 'Kaydet'));
    await t.pumpAndSettle();
    expect(find.text('Tarif adını yazın'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'Tarif adı'), 'Test yemeği');
    await t.tap(find.widgetWithText(TextButton, 'Kaydet'));
    await t.pumpAndSettle();
    expect(find.text('En az bir malzeme ekleyin'), findsOneWidget);
    await t.tap(find.text('Malzeme ekle'));
    await t.pumpAndSettle();
    await t.tap(find.text('Domates').first);
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'g'), '100');
    await t.tap(find.widgetWithText(TextButton, 'Kaydet'));
    await t.pumpAndSettle();
    expect(recipes.any((r) => r.name == 'Test yemeği' && r.isCustom), true);
  });
}
