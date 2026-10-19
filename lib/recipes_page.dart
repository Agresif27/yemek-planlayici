import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';
import 'ui.dart';

class RecipesPage extends StatefulWidget {
  const RecipesPage({super.key});

  @override
  State<RecipesPage> createState() => _RecipesPageState();
}

class _RecipesPageState extends State<RecipesPage> {
  String q = '';
  int meal = -1; // -1 hepsi
  bool onlyMine = false;
  bool onlyAllowed = true;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final list = recipes.where((r) {
            if (meal >= 0 && !r.meals.contains(meal)) return false;
            if (onlyMine && !r.isCustom) return false;
            if (onlyAllowed && !state.allowed(r)) return false;
            return q.trim().isEmpty ||
                matches(r.name, q) ||
                r.ing.keys.any((n) => matches(n, q));
          }).toList()
            ..sort((a, b) => fold(a.name).compareTo(fold(b.name)));
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            pageTitle(context, 'Tarifler', actions: [
              IconButton(
                tooltip: 'Kendi tarifini ekle',
                icon: const Icon(Icons.add),
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const RecipeEditPage())),
              ),
            ]),
            SearchBox(hint: 'Tarif veya malzeme ara', onChanged: (v) => setState(() => q = v)),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                for (final (m, label) in [(-1, 'Hepsi'), (0, 'Kahvaltı'), (1, 'Öğle'), (2, 'Akşam')])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: meal == m,
                      onSelected: (_) => setState(() => meal = m),
                    ),
                  ),
                FilterChip(
                  label: const Text('Benim tariflerim'),
                  selected: onlyMine,
                  onSelected: (v) => setState(() => onlyMine = v),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Tercihlerime uygun'),
                  selected: onlyAllowed,
                  onSelected: (v) => setState(() => onlyAllowed = v),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('${list.length} tarif'),
            ),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('Eşleşen tarif yok'))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final r = list[i];
                        final missing = state.missingCount(r);
                        return ListTile(
                          leading: Text(r.emoji, style: const TextStyle(fontSize: 28)),
                          title: Text(r.name),
                          subtitle: Text(
                              '${r.meals.map((m) => mealNames[m]).join(' · ')} · ${r.minutes} dk · ${missing == 0 ? 'her şey evde' : '$missing malzeme eksik'}'),
                          trailing: r.isCustom ? const Icon(Icons.person, size: 18) : null,
                          onTap: () => showRecipeSheet(context, recipe: r),
                        );
                      },
                    ),
            ),
          ]);
        },
      );
}

// ------------------------------------------------------------ Tarif ekle

class RecipeEditPage extends StatefulWidget {
  const RecipeEditPage({super.key});

  @override
  State<RecipeEditPage> createState() => _RecipeEditPageState();
}

class _RecipeEditPageState extends State<RecipeEditPage> {
  final nameC = TextEditingController();
  final emojiC = TextEditingController();
  final minC = TextEditingController(text: '30');
  final stepsC = TextEditingController();
  final meals = <int>{2};
  final qty = <String, TextEditingController>{}; // malzeme -> kişi başı miktar
  String? error;

  @override
  void dispose() {
    for (final c in [nameC, emojiC, minC, stepsC, ...qty.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addIngredient() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => _ItemPicker(exclude: qty.keys.toSet()),
    );
    if (picked == null) return;
    setState(() => qty[picked] = TextEditingController());
  }

  void _save() {
    final name = nameC.text.trim();
    if (name.isEmpty) return setState(() => error = 'Tarif adını yazın');
    if (meals.isEmpty) return setState(() => error = 'En az bir öğün seçin');
    if (qty.isEmpty) return setState(() => error = 'En az bir malzeme ekleyin');
    final ing = <String, double>{};
    for (final e in qty.entries) {
      final v = double.tryParse(e.value.text.trim().replaceAll(',', '.'));
      if (v == null || v <= 0) {
        return setState(() => error = '"${e.key}" için kişi başı miktar yazın');
      }
      ing[e.key] = v;
    }
    final steps = stepsC.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final r = Recipe(
      'ozel-${DateTime.now().millisecondsSinceEpoch}',
      name,
      emojiC.text.trim().isEmpty ? '🍽️' : emojiC.text.trim(),
      int.tryParse(minC.text.trim()) ?? 30,
      meals.toList()..sort(),
      ing,
      steps.isEmpty ? ['Tarif adımı eklenmedi.'] : steps,
    );
    state.addCustomRecipe(r);
    toast('Tarif eklendi: $name');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Yeni tarif'),
          actions: [TextButton(onPressed: _save, child: const Text('Kaydet'))],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            TextField(
              controller: nameC,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Tarif adı'),
            ),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: emojiC,
                  decoration: const InputDecoration(labelText: 'Emoji', hintText: '🍽️'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: minC,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Süre (dk)'),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Text('Hangi öğünde yenir?', style: Theme.of(context).textTheme.titleMedium),
            Wrap(spacing: 8, children: [
              for (var m = 0; m < 3; m++)
                FilterChip(
                  label: Text(mealNames[m]),
                  selected: meals.contains(m),
                  onSelected: (v) => setState(() => v ? meals.add(m) : meals.remove(m)),
                ),
            ]),
            const SizedBox(height: 16),
            Text('Malzemeler (kişi başı miktar)', style: Theme.of(context).textTheme.titleMedium),
            for (final e in qty.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Text(items[e.key]!.emoji, style: const TextStyle(fontSize: 22)),
                title: Text(e.key),
                trailing: SizedBox(
                  width: 150,
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: e.value,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(isDense: true, suffixText: items[e.key]!.unit),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kaldır',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => qty.remove(e.key)?.dispose()),
                    ),
                  ]),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Malzeme ekle'),
                onPressed: _addIngredient,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: stepsC,
              minLines: 4,
              maxLines: 12,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Yapılışı',
                hintText: 'Her satıra bir adım yazın',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _save, child: const Text('Tarifi kaydet')),
          ],
        ),
      );
}

/// Aranabilir ürün seçici; listede yoksa yeni ürün eklenebilir.
class _ItemPicker extends StatefulWidget {
  final Set<String> exclude;
  const _ItemPicker({required this.exclude});

  @override
  State<_ItemPicker> createState() => _ItemPickerState();
}

class _ItemPickerState extends State<_ItemPicker> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final list = allItems
        .where((i) => !widget.exclude.contains(i.name) && (q.trim().isEmpty || matches(i.name, q)))
        .toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(children: [
        SearchBox(hint: 'Ürün ara', onChanged: (v) => setState(() => q = v)),
        ListTile(
          leading: const Icon(Icons.add_circle_outline),
          title: Text(q.trim().isEmpty ? 'Yeni ürün ekle' : 'Yeni ürün ekle: "${q.trim()}"'),
          onTap: () async {
            final it = await showAddItemDialog(context, initialName: q.trim());
            if (it != null && context.mounted) Navigator.pop(context, it.name);
          },
        ),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) => ListTile(
              leading: Text(list[i].emoji, style: const TextStyle(fontSize: 22)),
              title: Text(list[i].name),
              subtitle: Text(list[i].cat),
              onTap: () => Navigator.pop(context, list[i].name),
            ),
          ),
        ),
      ]),
    );
  }
}
