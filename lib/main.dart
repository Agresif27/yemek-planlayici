import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'data.dart';

const _days = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];

final state = AppState();
final tabIndex = ValueNotifier<int>(0);
final messengerKey = GlobalKey<ScaffoldMessengerState>();

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
    messengerKey.currentState?.showSnackBar(SnackBar(
        content: Text('Tarif kataloğu güncellendi: ${recipes.length} tarif')));
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

String fmtQty(Item it, double q) {
  if (it.unit == 'adet') {
    final r = (q * 2).ceil() / 2;
    return '${r == r.roundToDouble() ? r.toInt() : r} adet';
  }
  if (q >= 1000) {
    final s = (q / 1000).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
    return '$s ${it.unit == 'g' ? 'kg' : 'L'}';
  }
  final step = q >= 50 ? 10 : 1;
  return '${(q / step).round() * step} ${it.unit}';
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
    tabIndex.value = state.onboarded ? 0 : 3;
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: tabIndex,
        builder: (context, tab, _) => _scaffold(tab),
      );

  Widget _scaffold(int tab) {
    const pages = [PlanPage(), PantryPage(), ShoppingPage(), PrefsPage()];
    return Scaffold(
      body: SafeArea(child: pages[tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => tabIndex.value = i,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Plan'),
          NavigationDestination(icon: Icon(Icons.kitchen), label: 'Evde Var'),
          NavigationDestination(icon: Icon(Icons.shopping_cart), label: 'Liste'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Tercihler'),
        ],
      ),
    );
  }
}

Widget _title(BuildContext c, String t, {List<Widget> actions = const []}) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(children: [
        Expanded(child: Text(t, style: Theme.of(c).textTheme.headlineSmall)),
        ...actions,
      ]),
    );

// ---------------------------------------------------------------- Plan

class PlanPage extends StatelessWidget {
  const PlanPage({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final hasPlan = state.plan.any((e) => e != null);
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _title(context, 'Haftalık Plan', actions: [
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
                          if (!state.plan.any((e) => e != null) && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                content: Text('Tercihlerine uygun tarif bulunamadı.')));
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
            child: Text(_days[day],
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
        title: Text('${mealNames[meal]}: uygun tarif yok'),
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
      onTap: () => _showRecipe(context, slot),
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

  void _showRecipe(BuildContext context, int slot) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => ListenableBuilder(
        listenable: state,
        builder: (c, _) {
          final r = state.recipe(state.plan[slot]!);
          final done = state.done.contains(slot);
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.8,
            maxChildSize: 0.95,
            builder: (c, ctrl) => ListView(
              controller: ctrl,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Text('${r.emoji} ${r.name}', style: Theme.of(c).textTheme.headlineSmall),
                Text('${_days[slot ~/ 3]} ${mealNames[slot % 3].toLowerCase()} · ${r.minutes} dk · ${state.people} kişilik'),
                const SizedBox(height: 16),
                Text('Malzemeler', style: Theme.of(c).textTheme.titleMedium),
                for (final e in r.ing.entries)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Text(items[e.key]!.emoji),
                    title: Text(e.key),
                    trailing: Text(fmtQty(items[e.key]!, e.value * state.people)),
                    subtitle: state.owned.contains(e.key) ? const Text('evde var') : null,
                  ),
                const SizedBox(height: 12),
                Text('Yapılışı', style: Theme.of(c).textTheme.titleMedium),
                for (var i = 0; i < r.steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text('${i + 1}. ${r.steps[i]}'),
                  ),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Değiştir'),
                      onPressed: () => _swap(c, slot),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      icon: Icon(done ? Icons.undo : Icons.check),
                      label: Text(done ? 'Geri al' : 'Yaptım'),
                      onPressed: () async {
                        if (done) {
                          state.unmarkDone(slot);
                          return;
                        }
                        final rating = await _askRating(c);
                        if (rating == null) return;
                        state.markDone(slot, rating);
                        if (c.mounted) Navigator.pop(c);
                      },
                    ),
                  ),
                ]),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<int?> _askRating(BuildContext context) => showDialog<int>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Nasıldı?'),
          content: const Text('Cevabın sonraki önerileri iyileştirir.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, 0), child: const Text('Atla')),
            TextButton(onPressed: () => Navigator.pop(c, -1), child: const Text('👎 Beğenmedim')),
            FilledButton(onPressed: () => Navigator.pop(c, 1), child: const Text('👍 Beğendim')),
          ],
        ),
      );

  void _swap(BuildContext context, int slot) {
    final alts = state.alternatives(slot % 3);
    showDialog(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Başka yemek seç'),
        children: [
          SizedBox(
            width: double.maxFinite,
            height: 380,
            child: ListView(children: [
              for (final r in alts)
                ListTile(
                  leading: Text(r.emoji, style: const TextStyle(fontSize: 24)),
                  title: Text(r.name),
                  subtitle: Text(state.missingCount(r) == 0
                      ? 'her şey evde'
                      : '${state.missingCount(r)} malzeme eksik'),
                  selected: state.plan[slot] == r.id,
                  onTap: () {
                    state.setRecipe(slot, r.id);
                    Navigator.pop(c);
                  },
                ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Evde Var

class PantryPage extends StatelessWidget {
  const PantryPage({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: state,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            _title(context, 'Evde Neler Var?'),
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
            for (final cat in categories) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(cat, style: Theme.of(context).textTheme.titleMedium),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(spacing: 8, children: [
                  for (final it in allItems.where((i) => i.cat == cat))
                    FilterChip(
                      label: Text('${it.emoji} ${it.name}'),
                      selected: state.owned.contains(it.name),
                      onSelected: (_) => state.toggleOwned(it.name),
                    ),
                ]),
              ),
            ],
          ],
        ),
      );
}

// ---------------------------------------------------------------- Liste

class ShoppingPage extends StatelessWidget {
  const ShoppingPage({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final list = state.shopping;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _title(context, 'Alışveriş Listesi', actions: [
              if (list.isNotEmpty)
                IconButton(
                  tooltip: 'Listeyi kopyala',
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    final text = list
                        .map((e) => '${state.bought.contains(e.key.name) ? '✓' : '•'} ${e.key.name}: ${fmtQty(e.key, e.value)}')
                        .join('\n');
                    Clipboard.setData(ClipboardData(text: 'Alışveriş listesi\n$text'));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Liste kopyalandı, istediğin uygulamada paylaşabilirsin.')));
                  },
                ),
            ]),
            if (list.isEmpty)
              const Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Liste boş. Plan oluşturunca eksik malzemeler burada görünür.',
                        textAlign: TextAlign.center),
                  ),
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                    '${state.bought.where((n) => list.any((e) => e.key.name == n)).length}/${list.length} alındı · tahmini ${state.estimatedCost.round()} ₺'),
              ),
              Expanded(
                child: ListView(children: [
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

class PrefsPage extends StatelessWidget {
  const PrefsPage({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: state,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            _title(context, 'Tercihler'),
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
            Text('Sevmediğim yiyecekler', style: Theme.of(context).textTheme.titleMedium),
            const Text('Seçtiklerin hiçbir tarifte kullanılmaz.'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final it in allItems)
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
                  tabIndex.value = 1;
                },
                child: const Text('Devam: evdeki malzemeleri seç'),
              ),
            ],
          ],
        ),
      );
}
