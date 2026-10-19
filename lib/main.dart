import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'data.dart';
import 'recipes_page.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Catalog.load();
  try {
    await state.load();
  } catch (_) {
    // Kayıtlı veri okunamazsa uygulama yine de açılır (boş durumla).
  }
  state.reconcile();
  runApp(const YemekApp());
  // Arka planda yeni tarif kataloğu var mı diye bak; internet yoksa sessizce geç.
  Catalog.refresh().then((updated) {
    if (!updated) return;
    state.reconcile();
    toast('Tarif kataloğu güncellendi: ${recipes.length} tarif');
  });
}

class YemekApp extends StatelessWidget {
  const YemekApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Yemek Planlayıcı',
        scaffoldMessengerKey: messengerKey,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.green,
          useMaterial3: true,
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.green,
          useMaterial3: true,
          brightness: Brightness.dark,
        ),
        home: const Home(),
      );
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  @override
  void initState() {
    super.initState();
    tabIndex.value = state.onboarded ? 0 : 4;
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: tabIndex,
        builder: (context, tab, _) => _scaffold(tab),
      );

  Widget _scaffold(int tab) {
    const pages = [PlanPage(), RecipesPage(), PantryPage(), ShoppingPage(), PrefsPage()];
    return Scaffold(
      body: SafeArea(child: pages[tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => tabIndex.value = i,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Plan'),
          NavigationDestination(icon: Icon(Icons.menu_book), label: 'Tarifler'),
          NavigationDestination(icon: Icon(Icons.kitchen), label: 'Evde Var'),
          NavigationDestination(icon: Icon(Icons.shopping_cart), label: 'Liste'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Tercihler'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Plan

class PlanPage extends StatelessWidget {
  const PlanPage({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final hasPlan = state.plan.any((e) => e != null);
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            pageTitle(context, 'Haftalık Plan', actions: [
              if (hasPlan)
                IconButton(
                  tooltip: 'Yeniden oluştur',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => _confirmRegen(context),
                ),
            ]),
            if (!hasPlan)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('🍽️', style: TextStyle(fontSize: 64)),
                      const SizedBox(height: 12),
                      const Text(
                        'Evdeki malzemelere, kişi sayına ve bütçene göre 7 günlük kahvaltı, öğle ve akşam planı oluşturalım.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Plan oluştur'),
                        onPressed: () {
                          state.generatePlan();
                          if (!state.plan.any((e) => e != null)) {
                            toast('Tercihlerine uygun tarif bulunamadı.');
                          }
                        },
                      ),
                    ]),
                  ),
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '${state.people} kişilik · tahmini alışveriş ${state.estimatedCost.round()} ₺ / bütçe ${state.budget.round()} ₺',
                  style: TextStyle(
                      color: state.estimatedCost > state.budget
                          ? Theme.of(context).colorScheme.error
                          : null),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: 7,
                  itemBuilder: (_, i) => _dayCard(context, i),
                ),
              ),
            ],
          ]);
        },
      );

  Widget _dayCard(BuildContext context, int day) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(days[day],
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
          for (var m = 0; m < 3; m++) _mealTile(context, day * 3 + m),
        ]),
      ),
    );
  }

  Widget _mealTile(BuildContext context, int slot) {
    final id = state.plan[slot];
    final meal = slot % 3;
    if (id == null) {
      return ListTile(
        dense: true,
        leading: Text(mealEmojis[meal], style: const TextStyle(fontSize: 22)),
        title: Text('${mealNames[meal]}: boş'),
        subtitle: const Text('Tarifler sekmesinden ekleyebilirsin'),
      );
    }
    final r = state.recipe(id);
    final done = state.done.contains(slot);
    final missing = state.missingCount(r);
    return ListTile(
      dense: true,
      leading: Text(r.emoji, style: const TextStyle(fontSize: 26)),
      title: Text(r.name,
          style: TextStyle(decoration: done ? TextDecoration.lineThrough : null)),
      subtitle: Text(
          '${mealNames[meal]} · ${r.minutes} dk · ${missing == 0 ? 'her şey evde' : '$missing malzeme eksik'}'),
      trailing: done
          ? const Icon(Icons.check_circle, color: Colors.green)
          : const Icon(Icons.chevron_right),
      onTap: () => showRecipeSheet(context, slot: slot),
    );
  }

  Future<void> _confirmRegen(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Plan yeniden oluşturulsun mu?'),
        content: const Text('Mevcut plan, yapıldı işaretleri ve alışveriş işaretleri sıfırlanır.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Oluştur')),
        ],
      ),
    );
    if (ok == true) state.generatePlan();
  }
}

// ---------------------------------------------------------------- Evde Var

class PantryPage extends StatefulWidget {
  const PantryPage({super.key});

  @override
  State<PantryPage> createState() => _PantryPageState();
}

class _PantryPageState extends State<PantryPage> {
  String q = '';

  Future<void> _add({String name = ''}) async {
    final it = await showAddItemDialog(context, initialName: name);
    if (it != null) state.toggleOwned(it.name); // eklenen ürün evde var sayılır
  }

  Future<void> _confirmRemove(Item it) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Ürün silinsin mi?'),
        content: Text('"${it.name}" senin eklediğin bir ürün. Listeden kaldırılacak.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok == true && !state.removeCustomItem(it.name)) {
      toast('"${it.name}" kendi tariflerinden birinde kullanılıyor, önce o tarifi sil.');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final shown = allItems.where((i) => q.trim().isEmpty || matches(i.name, q)).toList();
          return ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              pageTitle(context, 'Evde Neler Var?', actions: [
                IconButton(
                  tooltip: 'Ürün ekle',
                  icon: const Icon(Icons.add),
                  onPressed: _add,
                ),
              ]),
              SearchBox(hint: 'Ürün ara', onChanged: (v) => setState(() => q = v)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Expanded(child: Text('${state.owned.length} malzeme seçili')),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.bolt),
                    label: const Text('Sık kullanılanları seç'),
                    onPressed: state.selectCommon,
                  ),
                ]),
              ),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(children: [
                    const Text('Eşleşen ürün yok'),
                    TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: Text('Yeni ürün ekle: "${q.trim()}"'),
                      onPressed: () => _add(name: q.trim()),
                    ),
                  ]),
                ),
              for (final cat in categories)
                if (shown.any((i) => i.cat == cat)) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(cat, style: Theme.of(context).textTheme.titleMedium),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Wrap(spacing: 8, children: [
                      for (final it in shown.where((i) => i.cat == cat))
                        GestureDetector(
                          onLongPress: customItems.any((c) => c.name == it.name)
                              ? () => _confirmRemove(it)
                              : null,
                          child: FilterChip(
                            label: Text('${it.emoji} ${it.name}'),
                            selected: state.owned.contains(it.name),
                            onSelected: (_) => state.toggleOwned(it.name),
                          ),
                        ),
                    ]),
                  ),
                ],
              if (customItems.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text('İpucu: kendi eklediğin ürünü silmek için üzerine uzun bas.'),
                ),
            ],
          );
        },
      );
}

// ---------------------------------------------------------------- Liste

class ShoppingPage extends StatefulWidget {
  const ShoppingPage({super.key});

  @override
  State<ShoppingPage> createState() => _ShoppingPageState();
}

class _ShoppingPageState extends State<ShoppingPage> {
  String q = '';

  Future<void> _addExtra() async {
    final c = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setS) => AlertDialog(
          title: const Text('Listeye ürün ekle'),
          content: TextField(
            controller: c,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: 'Ürün', hintText: 'ör. 2 kg elma', errorText: error),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Vazgeç')),
            FilledButton(
              onPressed: () {
                if (c.text.trim().isEmpty) {
                  setS(() => error = 'Bir şey yazın');
                } else if (!state.addExtra(c.text)) {
                  setS(() => error = 'Bu zaten listede');
                } else {
                  Navigator.pop(d);
                }
              },
              child: const Text('Ekle'),
            ),
          ],
        ),
      ),
    );
  }

  void _copy(List<MapEntry<Item, double>> list) {
    final lines = [
      for (final t in state.extras) '${state.bought.contains('x:$t') ? '✓' : '•'} $t',
      for (final e in list)
        '${state.bought.contains(e.key.name) ? '✓' : '•'} ${e.key.name}: ${fmtQty(e.key, e.value)}',
    ];
    Clipboard.setData(ClipboardData(text: 'Alışveriş listesi\n${lines.join('\n')}'));
    toast('Liste kopyalandı, istediğin uygulamada paylaşabilirsin.');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final all = state.shopping;
          final list = all.where((e) => q.trim().isEmpty || matches(e.key.name, q)).toList();
          final extras = state.extras.where((t) => q.trim().isEmpty || matches(t, q)).toList();
          final total = all.length + state.extras.length;
          final got = all.where((e) => state.bought.contains(e.key.name)).length +
              state.extras.where((t) => state.bought.contains('x:$t')).length;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            pageTitle(context, 'Alışveriş Listesi', actions: [
              IconButton(tooltip: 'Ürün ekle', icon: const Icon(Icons.add), onPressed: _addExtra),
              if (total > 0)
                IconButton(
                  tooltip: 'Listeyi kopyala',
                  icon: const Icon(Icons.copy),
                  onPressed: () => _copy(all),
                ),
            ]),
            if (total == 0)
              const Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                        'Liste boş. Plan oluşturunca eksik malzemeler burada görünür; + ile kendi ürünlerini de ekleyebilirsin.',
                        textAlign: TextAlign.center),
                  ),
                ),
              )
            else ...[
              SearchBox(hint: 'Listede ara', onChanged: (v) => setState(() => q = v)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('$got/$total alındı · tahmini ${state.estimatedCost.round()} ₺'),
              ),
              Expanded(
                child: list.isEmpty && extras.isEmpty
                    ? const Center(child: Text('Eşleşen ürün yok'))
                    : ListView(children: [
                        if (extras.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: Text('Eklediğim ürünler', style: Theme.of(context).textTheme.titleSmall),
                          ),
                          for (final t in extras)
                            CheckboxListTile(
                              value: state.bought.contains('x:$t'),
                              onChanged: (_) => state.toggleBought('x:$t'),
                              title: Text(t,
                                  style: TextStyle(
                                      decoration: state.bought.contains('x:$t')
                                          ? TextDecoration.lineThrough
                                          : null)),
                              secondary: IconButton(
                                tooltip: 'Sil',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => state.removeExtra(t),
                              ),
                            ),
                        ],
                        for (final cat in categories)
                          if (list.any((e) => e.key.cat == cat)) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: Text(cat, style: Theme.of(context).textTheme.titleSmall),
                            ),
                            for (final e in list.where((e) => e.key.cat == cat))
                              CheckboxListTile(
                                value: state.bought.contains(e.key.name),
                                onChanged: (_) => state.toggleBought(e.key.name),
                                title: Text('${e.key.emoji} ${e.key.name}',
                                    style: TextStyle(
                                        decoration: state.bought.contains(e.key.name)
                                            ? TextDecoration.lineThrough
                                            : null)),
                                secondary: Text(fmtQty(e.key, e.value)),
                              ),
                          ],
                      ]),
              ),
            ],
          ]);
        },
      );
}

// ---------------------------------------------------------------- Tercihler

class PrefsPage extends StatefulWidget {
  const PrefsPage({super.key});

  @override
  State<PrefsPage> createState() => _PrefsPageState();
}

class _PrefsPageState extends State<PrefsPage> {
  String q = '';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final shown = allItems.where((i) => q.trim().isEmpty || matches(i.name, q)).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              pageTitle(context, 'Tercihler'),
              const SizedBox(height: 8),
              Text('Kaç kişilik yemek yapıyorsun?', style: Theme.of(context).textTheme.titleMedium),
              Row(children: [
                IconButton.filledTonal(
                  icon: const Icon(Icons.remove),
                  onPressed: state.people > 1 ? () => state.setPrefs(people: state.people - 1) : null,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('${state.people}', style: Theme.of(context).textTheme.headlineSmall),
                ),
                IconButton.filledTonal(
                  icon: const Icon(Icons.add),
                  onPressed: state.people < 12 ? () => state.setPrefs(people: state.people + 1) : null,
                ),
              ]),
              const SizedBox(height: 16),
              Text('Haftalık alışveriş bütçesi: ${state.budget.round()} ₺',
                  style: Theme.of(context).textTheme.titleMedium),
              Slider(
                min: 500,
                max: 8000,
                divisions: 75,
                value: state.budget.clamp(500, 8000),
                label: '${state.budget.round()} ₺',
                onChanged: (v) => state.setPrefs(budget: (v / 100).round() * 100.0),
              ),
              const SizedBox(height: 8),
              Text('Beslenme tercihi', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Hepsi')),
                  ButtonSegment(value: 1, label: Text('Vejetaryen')),
                  ButtonSegment(value: 2, label: Text('Vegan')),
                ],
                selected: {state.diet},
                onSelectionChanged: (s) => state.setPrefs(diet: s.first),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: Text('Sevmediğim yiyecekler', style: Theme.of(context).textTheme.titleMedium),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Ürün ekle'),
                  onPressed: () => showAddItemDialog(context),
                ),
              ]),
              const Text('Seçtiklerin hiçbir tarifte kullanılmaz.'),
              SearchBox(
                hint: 'Ürün ara',
                padding: const EdgeInsets.symmetric(vertical: 8),
                onChanged: (v) => setState(() => q = v),
              ),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(children: [
                    const Text('Eşleşen ürün yok'),
                    TextButton(
                      onPressed: () => showAddItemDialog(context, initialName: q.trim()),
                      child: Text('Ekle: "${q.trim()}"'),
                    ),
                  ]),
                ),
              Wrap(spacing: 8, children: [
                for (final it in shown)
                  FilterChip(
                    label: Text('${it.emoji} ${it.name}'),
                    selected: state.disliked.contains(it.name),
                    onSelected: (_) => state.toggleDisliked(it.name),
                  ),
              ]),
              if (!state.onboarded) ...[
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () {
                    state.finishOnboarding();
                    tabIndex.value = 2;
                  },
                  child: const Text('Devam: evdeki malzemeleri seç'),
                ),
              ],
            ],
          );
        },
      );
}
