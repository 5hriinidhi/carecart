import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/foods_api.dart';
import '../../core/text.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../facts/food_screen.dart';

/// Search-only food lookup — `state.screen == 'search'` ("Look it up, no barcode
/// needed"). Types a name → `GET /foods/search` over the everyday-food dataset →
/// tap a hit → its facts ([FoodScreen]). No camera, no OCR.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.onBack, this.showEmpty = false});
  final VoidCallback? onBack;

  /// Debug-gallery preview of the "nothing matched" state.
  final bool showEmpty;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  List<FoodHit> _hits = const [];
  bool _searching = false;
  String? _error;
  bool _ran = false; // a search has completed at least once

  @override
  void initState() {
    super.initState();
    if (widget.showEmpty) {
      _ran = true;
      _controller.text = 'zzzzz';
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(v));
  }

  Future<void> _run(String v) async {
    final q = v.trim();
    if (q.replaceAll(RegExp(r'\s'), '').length < 2) {
      setState(() {
        _hits = const [];
        _error = null;
        _searching = false;
        _ran = false;
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    final res = await ref.read(foodsApiProvider).search(q);
    if (!mounted || _controller.text.trim() != q) return;
    setState(() {
      _searching = false;
      _ran = true;
      switch (res) {
        case FoodSearchHits(:final hits):
          _hits = hits;
        case FoodSearchError(:final message):
          _hits = const [];
          _error = message;
      }
    });
  }

  void _open(FoodHit hit) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FoodScreen(
        food: hit,
        onClose: () => Navigator.of(context).maybePop(),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return CcScreen(
      background: Cc.paper,
      safeBottom: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
        children: [
          const SizedBox(height: 6),
          Row(
            children: [
              CcRoundButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onTap: widget.onBack,
                  size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  decoration: BoxDecoration(
                    color: Cc.paperRaised,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0x1F151510)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded,
                          size: 16, color: Cc.muted),
                      const SizedBox(width: 9),
                      Expanded(
                        child: TextField(
                          key: const Key('food-search-field'),
                          controller: _controller,
                          autofocus: !widget.showEmpty,
                          textInputAction: TextInputAction.search,
                          onChanged: _onChanged,
                          decoration: const InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                            hintText: 'Dish, product or brand',
                          ),
                          style: CcText.bodySm.copyWith(fontSize: 13.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ..._body(),
        ],
      ),
    );
  }

  List<Widget> _body() {
    if (_searching) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 30),
          child: Center(
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
      ];
    }
    if (_error != null) {
      return [
        Text(_error!,
            key: const Key('food-search-error'),
            style: CcText.body.copyWith(color: Cc.muted)),
      ];
    }
    if (_hits.isNotEmpty) {
      return [
        for (final h in _hits) ...[
          _FoodRow(hit: h, onTap: () => _open(h)),
          const SizedBox(height: 9),
        ],
      ];
    }
    if (_ran) {
      return const [
        Padding(
          padding: EdgeInsets.fromLTRB(6, 30, 6, 0),
          child: Column(
            children: [
              Text('No food matched that',
                  style: TextStyle(
                      fontFamily: 'Bricolage',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Cc.ink)),
              SizedBox(height: 6),
              Text(
                "Try fewer words, or scan the pack's barcode / ingredients list "
                'instead.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ];
    }
    return [
      Text(
        'Type a dish or product name — poha, Parle-G, palak paneer.',
        style: CcText.body.copyWith(color: Cc.muted, height: 1.5),
      ),
    ];
  }
}

class _FoodRow extends StatelessWidget {
  const _FoodRow({required this.hit, this.onTap});
  final FoodHit hit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Cc.paperRaised,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x12151510)),
        ),
        child: Row(
          children: [
            const CcThumb(size: 42, radius: 11),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(hit.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CcText.listTitle),
                  if (hit.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(hit.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CcText.bodySm.copyWith(color: Cc.muted)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(hit.isPackaged ? 'PACKAGED' : 'DISH',
                style: CcText.mono.copyWith(
                    color: const Color(0xFFA3A491),
                    fontSize: 9,
                    letterSpacing: 0.8)),
          ],
        ),
      ),
    );
  }
}
