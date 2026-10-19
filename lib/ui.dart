import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';

const days = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];

final tabIndex = ValueNotifier<int>(0);
final messengerKey = GlobalKey<ScaffoldMessengerState>();

void toast(String msg) =>
    messengerKey.currentState?.showSnackBar(SnackBar(content: Text(msg)));

/// Türkçe harfleri sadeleştirip küçültür: "Pırasa" ile "pirasa" eşleşir.
String fold(String s) {
  const from = 'İIıÇçĞğÖöŞşÜü';
  const to = 'iiiccggoossuu';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch.toLowerCase());
  }
  return b.toString();
}

bool matches(String text, String query) => fold(text).contains(fold(query.trim()));

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

Widget pageTitle(BuildContext c, String t, {List<Widget> actions = const []}) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(children: [
        Expanded(child: Text(t, style: Theme.of(c).textTheme.headlineSmall)),
        ...actions,
      ]),
    );

class SearchBox extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final EdgeInsets padding;
  const SearchBox({
    super.key,
    required this.hint,
    required this.onChanged,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 4),
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: TextField(
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: hint,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
          ),
        ),
      );
}

// ------------------------------------------------------------ Ürün ekle

/// Yeni ürün oluşturur ve kaydeder. İptal edilirse null döner.
Future<Item?> showAddItemDialog(BuildContext context, {String initialName = ''}) {
  final nameC = TextEditingController(text: initialName);
  final emojiC = TextEditingController();
  final priceC = TextEditingController();
  var cat = categories.first;
  var unit = 'adet';
  var kind = 0; // 0 bitkisel, 1 süt/yumurta, 2 et
  String? error;
  return showDialog<Item>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => AlertDialog(
        title: const Text('Yeni ürün ekle'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: nameC,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: 'Ürün adı', errorText: error),
            ),
            TextField(
              controller: emojiC,
              decoration: const InputDecoration(labelText: 'Emoji (isteğe bağlı)', hintText: '🛒'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: cat,
              decoration: const InputDecoration(labelText: 'Kategori'),
              items: [for (final k in categories) DropdownMenuItem(value: k, child: Text(k))],
              onChanged: (v) => cat = v ?? cat,
            ),
            const SizedBox(height: 12),
            const Text('Birim'),
            const SizedBox(height: 4),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'adet', label: Text('Adet')),
                ButtonSegment(value: 'g', label: Text('Gram')),
                ButtonSegment(value: 'ml', label: Text('ml')),
              ],
              selected: {unit},
              onSelectionChanged: (s) => setS(() => unit = s.first),
            ),
            const SizedBox(height: 12),
            const Text('Tür (vejetaryen/vegan filtresi için)'),
            const SizedBox(height: 4),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Bitkisel')),
                ButtonSegment(value: 1, label: Text('Süt/yumurta')),
                ButtonSegment(value: 2, label: Text('Et/balık')),
              ],
              selected: {kind},
              onSelectionChanged: (s) => setS(() => kind = s.first),
            ),
            TextField(
              controller: priceC,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Yaklaşık fiyat, ₺ / ${unit == 'adet' ? 'adet' : unit == 'g' ? 'kg' : 'litre'} (isteğe bağlı)',
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () {
              final name = nameC.text.trim();
              if (name.isEmpty) {
                setS(() => error = 'Ürün adı yazın');
                return;
              }
              final typed = double.tryParse(priceC.text.trim().replaceAll(',', '.')) ?? 0;
              final it = Item(name, emojiC.text.trim().isEmpty ? '🛒' : emojiC.text.trim(), cat, unit,
                  unit == 'adet' ? typed : typed / 1000,
                  meat: kind == 2, animal: kind >= 1);
              if (!state.addCustomItem(it)) {
                setS(() => error = 'Bu ürün zaten listede var');
                return;
              }
              Navigator.pop(c, it);
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    ),
  );
}

// ------------------------------------------------------------ Tarif sayfası

Future<int?> askRating(BuildContext context) => showDialog<int>(
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

/// Hangi gün ve öğüne ekleneceğini sorar; slot numarası (gün * 3 + öğün) döner.
Future<int?> _pickSlot(BuildContext context, Recipe r) {
  var day = 0;
  var meal = r.meals.first;
  return showDialog<int>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => AlertDialog(
        title: const Text('Plana ekle'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          DropdownButtonFormField<int>(
            initialValue: day,
            decoration: const InputDecoration(labelText: 'Gün'),
            items: [for (var i = 0; i < 7; i++) DropdownMenuItem(value: i, child: Text(days[i]))],
            onChanged: (v) => day = v ?? day,
          ),
          const SizedBox(height: 16),
          SegmentedButton<int>(
            segments: [for (var m = 0; m < 3; m++) ButtonSegment(value: m, label: Text(mealNames[m]))],
            selected: {meal},
            onSelectionChanged: (s) => setS(() => meal = s.first),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, day * 3 + meal), child: const Text('Ekle')),
        ],
      ),
    ),
  );
}

/// Plandaki bir öğünün (slot) ya da katalogdaki bir tarifin (recipe) ayrıntısı.
void showRecipeSheet(BuildContext context, {Recipe? recipe, int? slot}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => ListenableBuilder(
      listenable: state,
      builder: (c, _) {
        final id = slot != null ? state.plan[slot] : recipe!.id;
        if (id == null || !recipes.any((r) => r.id == id)) {
          return const SizedBox(height: 140, child: Center(child: Text('Tarif bulunamadı')));
        }
        final r = state.recipe(id);
        final done = slot != null && state.done.contains(slot);
        final sub = slot != null
            ? '${days[slot ~/ 3]} ${mealNames[slot % 3].toLowerCase()}'
            : r.meals.map((m) => mealNames[m]).join(' · ');
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          maxChildSize: 0.95,
          builder: (c, ctrl) => ListView(
            controller: ctrl,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text('${r.emoji} ${r.name}', style: Theme.of(c).textTheme.headlineSmall),
              Text('$sub · ${r.minutes} dk · ${state.people} kişilik'),
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
              if (slot != null)
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
                        final rating = await askRating(c);
                        if (rating == null) return;
                        state.markDone(slot, rating);
                        if (c.mounted) Navigator.pop(c);
                      },
                    ),
                  ),
                ])
              else ...[
                FilledButton.icon(
                  icon: const Icon(Icons.event_available),
                  label: const Text('Plana ekle'),
                  onPressed: () async {
                    final s = await _pickSlot(c, r);
                    if (s == null) return;
                    state.setRecipe(s, r.id);
                    toast('Plana eklendi: ${days[s ~/ 3]} ${mealNames[s % 3].toLowerCase()}');
                    if (c.mounted) Navigator.pop(c);
                  },
                ),
                if (r.isCustom)
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Tarifi sil'),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: c,
                        builder: (d) => AlertDialog(
                          title: const Text('Tarif silinsin mi?'),
                          content: Text('"${r.name}" tarifi ve plandaki yeri kaldırılır.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
                            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Sil')),
                          ],
                        ),
                      );
                      if (ok != true) return;
                      state.removeCustomRecipe(r.id);
                      if (c.mounted) Navigator.pop(c);
                    },
                  ),
              ],
            ],
          ),
        );
      },
    ),
  );
}
