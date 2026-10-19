import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data.dart';

class AppState extends ChangeNotifier {
  int people = 2;
  double budget = 2500; // haftalık, TL
  int diet = 0; // 0 hepsi, 1 vejetaryen, 2 vegan
  bool onboarded = false;
  Set<String> disliked = {}, owned = {}, bought = {};
  Set<int> done = {}; // slot = gün * 3 + öğün
  List<String?> plan = List.filled(21, null);
  Map<String, int> ratings = {};

  final _rnd = Random();
  SharedPreferences? _prefs;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString('state');
    if (raw == null) return;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    people = m['people'] ?? 2;
    budget = (m['budget'] ?? 2500).toDouble();
    diet = m['diet'] ?? 0;
    onboarded = m['onboarded'] ?? false;
    disliked = Set<String>.from(m['disliked'] ?? []);
    owned = Set<String>.from(m['owned'] ?? []);
    bought = Set<String>.from(m['bought'] ?? []);
    final p = List<String?>.from(m['plan'] ?? []);
    if (p.length == 21) {
      plan = p;
      done = Set<int>.from(m['done'] ?? []);
    }
    ratings = Map<String, int>.from(m['ratings'] ?? {});
  }

  void _commit() {
    _prefs?.setString(
        'state',
        jsonEncode({
          'people': people,
          'budget': budget,
          'diet': diet,
          'onboarded': onboarded,
          'disliked': disliked.toList(),
          'owned': owned.toList(),
          'bought': bought.toList(),
          'done': done.toList(),
          'plan': plan,
          'ratings': ratings,
        }));
    notifyListeners();
  }

  Recipe recipe(String id) => recipes.firstWhere((r) => r.id == id);

  /// Katalog güncellenince kaldırılmış tarifleri plandan temizler.
  void reconcile() {
    final ids = recipes.map((r) => r.id).toSet();
    plan = [for (final id in plan) id != null && ids.contains(id) ? id : null];
    notifyListeners();
  }

  bool allowed(Recipe r) {
    for (final n in r.ing.keys) {
      final it = items[n]!;
      if (disliked.contains(n)) return false;
      if (diet >= 1 && it.meat) return false;
      if (diet == 2 && it.animal) return false;
    }
    return true;
  }

  double ownedFraction(Recipe r) =>
      r.ing.keys.where(owned.contains).length / r.ing.length;

  int missingCount(Recipe r) => r.ing.keys.where((n) => !owned.contains(n)).length;

  List<Recipe> forMeal(int meal) =>
      recipes.where((r) => r.meals.contains(meal) && allowed(r)).toList();

  double score(Recipe r) =>
      ownedFraction(r) * 3 + (ratings[r.id] ?? 0) * 1.5 + _rnd.nextDouble() * 1.2;

  /// Önerilen alternatifler: iyi eşleşenler başta.
  List<Recipe> alternatives(int meal) {
    final l = forMeal(meal);
    l.sort((a, b) => (ownedFraction(b) + (ratings[b.id] ?? 0) * 0.5)
        .compareTo(ownedFraction(a) + (ratings[a.id] ?? 0) * 0.5));
    return l;
  }

  /// Plandaki tarifler için toplam ihtiyaç (kişi sayısıyla çarpılmış).
  Map<String, double> needs(Iterable<String?> ids) {
    final m = <String, double>{};
    for (final id in ids) {
      if (id == null) continue;
      recipe(id).ing.forEach((n, q) => m[n] = (m[n] ?? 0) + q * people);
    }
    return m;
  }

  double _cost(Iterable<String?> ids) {
    var c = 0.0;
    needs(ids).forEach((n, q) {
      if (!owned.contains(n)) c += q * items[n]!.price;
    });
    return c;
  }

  double get estimatedCost => _cost(plan);

  List<MapEntry<Item, double>> get shopping {
    final l = needs(plan)
        .entries
        .where((e) => !owned.contains(e.key))
        .map((e) => MapEntry(items[e.key]!, e.value))
        .toList();
    l.sort((a, b) => a.key.name.compareTo(b.key.name));
    return l;
  }

  void generatePlan() {
    final next = List<String?>.filled(21, null);
    final used = <String>{};
    // Akşam, öğle, kahvaltı sırasıyla: ortak tarifler öğünler arasında tekrarlanmasın.
    for (final meal in [2, 1, 0]) {
      final c = forMeal(meal);
      if (c.isEmpty) continue;
      final sc = {for (final r in c) r.id: score(r)};
      final days = List.generate(7, (d) => d)..shuffle(_rnd);
      for (final d in days) {
        final fresh = c.where((r) => !used.contains(r.id)).toList();
        final pool = fresh.isEmpty ? c : fresh;
        final best = pool.reduce((a, b) => sc[a.id]! >= sc[b.id]! ? a : b);
        next[d * 3 + meal] = best.id;
        used.add(best.id);
        sc[best.id] = sc[best.id]! - 5; // yeniden seçilmeyi zorlaştır
      }
    }
    // Bütçeyi aşıyorsa en pahalı slotu aynı öğünden daha ucuz bir tarifle değiştir.
    for (var k = 0; k < 40 && _cost(next) > budget; k++) {
      var worst = -1;
      var worstCost = -1.0;
      for (var i = 0; i < 21; i++) {
        if (next[i] == null) continue;
        final cost = _cost([next[i]]);
        if (cost > worstCost) {
          worstCost = cost;
          worst = i;
        }
      }
      if (worst < 0) break;
      final cheaper = forMeal(worst % 3)
          .where((r) => !next.contains(r.id) && _cost([r.id]) < worstCost);
      if (cheaper.isEmpty) break;
      next[worst] =
          cheaper.reduce((a, b) => _cost([a.id]) <= _cost([b.id]) ? a : b).id;
    }
    plan = next;
    done = {};
    bought = {};
    _commit();
  }

  void setRecipe(int day, String id) {
    plan[day] = id;
    done.remove(day);
    _commit();
  }

  void markDone(int day, int rating) {
    done.add(day);
    final id = plan[day];
    if (id != null && rating != 0) {
      ratings[id] = ((ratings[id] ?? 0) + rating).clamp(-2, 2);
    }
    _commit();
  }

  void unmarkDone(int day) {
    done.remove(day);
    _commit();
  }

  void toggleOwned(String n) {
    owned.contains(n) ? owned.remove(n) : owned.add(n);
    if (owned.contains(n)) disliked.remove(n);
    _commit();
  }

  void selectCommon() {
    owned.addAll(commonItems);
    _commit();
  }

  void toggleDisliked(String n) {
    disliked.contains(n) ? disliked.remove(n) : disliked.add(n);
    if (disliked.contains(n)) owned.remove(n);
    _commit();
  }

  void toggleBought(String n) {
    bought.contains(n) ? bought.remove(n) : bought.add(n);
    _commit();
  }

  void setPrefs({int? people, double? budget, int? diet}) {
    this.people = people ?? this.people;
    this.budget = budget ?? this.budget;
    this.diet = diet ?? this.diet;
    _commit();
  }

  void finishOnboarding() {
    onboarded = true;
    _commit();
  }
}
