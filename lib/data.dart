import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

class Item {
  final String name, emoji, cat, unit;
  final double price; // TL per unit (g / ml / adet)
  final bool meat, animal;
  const Item(this.name, this.emoji, this.cat, this.unit, this.price,
      {this.meat = false, this.animal = false});

  factory Item.fromJson(Map<String, dynamic> j) => Item(
        j['name'], j['emoji'], j['cat'], j['unit'], (j['price'] as num).toDouble(),
        meat: j['meat'] ?? false, animal: j['animal'] ?? false);

  Map<String, dynamic> toJson() => {
        'name': name, 'emoji': emoji, 'cat': cat, 'unit': unit, 'price': price,
        'meat': meat, 'animal': animal,
      };
}

class Recipe {
  final String id, name, emoji;
  final int minutes;
  final List<int> meals; // 0 kahvaltı, 1 öğle, 2 akşam
  final Map<String, double> ing; // item name -> amount per person
  final List<String> steps;
  const Recipe(this.id, this.name, this.emoji, this.minutes, this.meals, this.ing, this.steps);

  factory Recipe.fromJson(Map<String, dynamic> j) => Recipe(
        j['id'], j['name'], j['emoji'], j['minutes'], List<int>.from(j['meals']),
        {for (final e in (j['ing'] as Map<String, dynamic>).entries) e.key: (e.value as num).toDouble()},
        List<String>.from(j['steps']));

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'emoji': emoji, 'minutes': minutes, 'meals': meals,
        'ing': ing, 'steps': steps,
      };

  bool get isCustom => id.startsWith('ozel-');
}

const mealNames = ['Kahvaltı', 'Öğle', 'Akşam'];
const mealEmojis = ['🌅', '☀️', '🌙'];

const categories = ['Sebze', 'Meyve', 'Bakliyat & Tahıl', 'Süt & Yumurta', 'Et & Balık', 'Kiler'];

/// Marketten sık alınanlar: tek dokunuşla "evde var" seçilir.
const commonItems = [
  'Soğan', 'Sarımsak', 'Domates', 'Patates', 'Makarna', 'Pirinç', 'Bulgur',
  'Yumurta', 'Ekmek', 'Un', 'Salça', 'Zeytinyağı', 'Sıvı yağ',
];

/// Katalog güncellemeleri buradan indirilir (assets/catalog.json'ın yayınlandığı adres).
const catalogUrl =
    'https://raw.githubusercontent.com/Agresif27/yemek-planlayici/main/assets/catalog.json';

Map<String, Item> items = {};
List<Item> allItems = [];
List<Recipe> recipes = [];
int catalogVersion = 0;

/// Kullanıcının kendi eklediği ürün ve tarifler; katalog güncellense de korunur.
List<Item> customItems = [];
List<Recipe> customRecipes = [];
List<Item> _baseItems = [];
List<Recipe> _baseRecipes = [];

class _Parsed {
  final int version;
  final List<Item> items;
  final List<Recipe> recipes;
  _Parsed(this.version, this.items, this.recipes);
}

class Catalog {
  /// Geçersiz veride null döner; uygulama mevcut kataloğuyla devam eder.
  static _Parsed? _parse(String raw) {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final its = (m['items'] as List).map((e) => Item.fromJson(e)).toList();
      final rs = (m['recipes'] as List).map((e) => Recipe.fromJson(e)).toList();
      final names = its.map((i) => i.name).toSet();
      if (its.isEmpty || rs.isEmpty) return null;
      for (final r in rs) {
        if (r.ing.isEmpty || r.meals.isEmpty) return null;
        if (r.meals.any((x) => x < 0 || x > 2)) return null;
        if (r.ing.keys.any((k) => !names.contains(k))) return null;
      }
      return _Parsed(m['version'] as int, its, rs);
    } catch (_) {
      return null;
    }
  }

  /// Ham JSON'u doğrular ve uygular. Yalnızca daha yeni sürüm kabul edilir.
  static bool apply(String raw) {
    final p = _parse(raw);
    if (p == null || p.version <= catalogVersion) return false;
    catalogVersion = p.version;
    _baseItems = p.items;
    _baseRecipes = p.recipes;
    rebuild();
    return true;
  }

  /// Katalog + kullanıcı verisini birleştirir. Katalogdaki aynı adlı ürün önceliklidir.
  static void rebuild() {
    final baseNames = _baseItems.map((i) => i.name).toSet();
    allItems = [..._baseItems, ...customItems.where((i) => !baseNames.contains(i.name))];
    items = {for (final i in allItems) i.name: i};
    final baseIds = _baseRecipes.map((r) => r.id).toSet();
    recipes = [
      ..._baseRecipes,
      ...customRecipes.where((r) => !baseIds.contains(r.id) && r.ing.keys.every(items.containsKey)),
    ];
  }

  static void setCustom(List<Item> its, List<Recipe> rs) {
    customItems = its;
    customRecipes = rs;
    rebuild();
  }

  /// Paketteki katalog + (varsa) daha yeni indirilmiş katalog.
  static Future<void> load() async {
    apply(await rootBundle.loadString('assets/catalog.json'));
    try {
      final cached = (await SharedPreferences.getInstance()).getString('catalog');
      if (cached != null) apply(cached);
    } catch (_) {}
  }

  /// İnternetten yeni katalog arar. Güncellendiyse true döner; hata/internet yoksa sessizce false.
  static Future<bool> refresh() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(catalogUrl));
      final resp = await req.close().timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) return false;
      final body = await resp.transform(utf8.decoder).join().timeout(const Duration(seconds: 30));
      if (!apply(body)) return false;
      (await SharedPreferences.getInstance()).setString('catalog', body);
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }
}
