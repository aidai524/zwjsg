import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/breeds.dart';
import '../../core/theme.dart';
import '../../widgets/avatar.dart';
import '../card/card_page.dart';

class DexPage extends StatefulWidget {
  const DexPage({super.key});

  @override
  State<DexPage> createState() => _DexPageState();
}

class _DexPageState extends State<DexPage> {
  Rarity? _filter;

  @override
  Widget build(BuildContext context) {
    final owned = AppScope.of(context).ownedBreeds;
    final shown = kBreeds.where((b) => _filter == null || b.rarity == _filter).toList();
    final ownedCount = kBreeds.where((b) => owned.contains(b.key)).length;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              sliver: SliverList.list(children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Expanded(child: Text('图鉴', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900))),
                    Text('已收集 $ownedCount / ${kBreeds.length}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  height: 16,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: Pop.ink, width: 2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: ownedCount / kBreeds.length,
                    child: Container(color: Pop.yellow),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    _chip('全部', null),
                    for (final r in Rarity.values) _chip(r.label, r),
                  ],
                ),
              ]),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              sliver: SliverGrid.count(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.62,
                children: [for (final b in shown) _BreedTile(breed: b, owned: owned.contains(b.key))],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Rarity? r) {
    final on = _filter == r;
    return ChoiceChip(
      label: Text(label),
      selected: on,
      showCheckmark: false,
      onSelected: (_) => setState(() => _filter = r),
      labelStyle: TextStyle(fontWeight: FontWeight.w900, color: on ? Pop.white : Pop.ink),
      selectedColor: Pop.ink,
      backgroundColor: Pop.white,
      side: const BorderSide(color: Pop.ink, width: 2),
      shape: const StadiumBorder(),
    );
  }
}

class _BreedTile extends StatelessWidget {
  const _BreedTile({required this.breed, required this.owned});

  final Breed breed;
  final bool owned;

  @override
  Widget build(BuildContext context) {
    final frame = CardPage.frameColor(breed.rarity);
    final tagFg = breed.rarity == Rarity.legend ? Pop.ink : Pop.white;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
      decoration: BoxDecoration(
        color: owned ? Pop.white : Pop.gray,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: frame, width: Pop.stroke),
      ),
      child: Column(
        children: [
          Align(
            alignment: Alignment.topRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(color: frame, borderRadius: BorderRadius.circular(8)),
              child: Text(breed.rarity.label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: tagFg)),
            ),
          ),
          if (owned) ...[
            DogAvatar(stage: breed.previewStage, size: 66),
            Text(breed.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(breed.quip,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Pop.muted, height: 1.4)),
          ] else ...[
            const SizedBox(height: 6),
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(color: Color(0xFF9AA0A6), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const Text('?', style: TextStyle(color: Pop.white, fontSize: 26, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(height: 6),
            const Text('未解锁', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Pop.muted)),
            Text(breed.rule,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Pop.muted, height: 1.4)),
          ],
        ],
      ),
    );
  }
}
