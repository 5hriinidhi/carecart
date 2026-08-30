import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/drugs_api.dart';
import '../../core/text.dart';
import '../../core/theme.dart';
import '../../core/vault_api.dart';
import 'pin_dialog.dart';

/// Bottom sheet: search the medicine catalogue, pick one, add an optional
/// dosage, then confirm with the PIN. Returns true if a medication was added.
Future<bool> showAddMedicationSheet(BuildContext context) async {
  final added = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AddMedicationSheet(),
  );
  return added ?? false;
}

class _AddMedicationSheet extends ConsumerStatefulWidget {
  const _AddMedicationSheet();

  @override
  ConsumerState<_AddMedicationSheet> createState() => _AddMedicationSheetState();
}

class _AddMedicationSheetState extends ConsumerState<_AddMedicationSheet> {
  final _query = TextEditingController();
  final _dosage = TextEditingController();
  Timer? _debounce;

  List<DrugHit> _hits = const [];
  bool _searching = false;
  String? _searchError;
  DrugHit? _picked;
  bool _saving = false;
  String? _saveError;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _dosage.dispose();
    super.dispose();
  }

  void _onQueryChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(v));
  }

  Future<void> _run(String v) async {
    final q = v.trim();
    if (q.replaceAll(RegExp(r'\s'), '').length < 2) {
      setState(() {
        _hits = const [];
        _searchError = null;
        _searching = false;
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    final res = await ref.read(drugsApiProvider).search(q);
    if (!mounted || _query.text.trim() != q) return;
    setState(() {
      _searching = false;
      switch (res) {
        case DrugSearchHits(:final hits):
          _hits = hits;
          _searchError = hits.isEmpty ? 'No matches. Check the spelling.' : null;
        case DrugSearchError(:final message):
          _hits = const [];
          _searchError = message;
      }
    });
  }

  Future<void> _add() async {
    final picked = _picked;
    if (picked == null || _saving) return;

    final unlocked = await showMedPinDialog(context, ref,
        actionLabel: 'add this medication');
    if (!unlocked || !mounted) return;

    setState(() {
      _saving = true;
      _saveError = null;
    });
    final res = await ref.read(vaultApiProvider).addMedication(
          picked.name,
          dosage: _dosage.text.trim(),
        );
    if (!mounted) return;
    switch (res) {
      case VaultOk():
        Navigator.of(context).pop(true);
      case VaultError(:final message):
        setState(() {
          _saving = false;
          _saveError = message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Cc.paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                    color: const Color(0x22202419),
                    borderRadius: BorderRadius.circular(99)),
              ),
            ),
            const SizedBox(height: 14),
            Text(_picked == null ? 'Add a medication' : 'Add “${_picked!.name}”',
                style: CcText.h2),
            const SizedBox(height: 10),
            if (_picked == null) ..._searchBody() else ..._confirmBody(),
          ],
        ),
      ),
    );
  }

  List<Widget> _searchBody() => [
        TextField(
          key: const Key('med-search-field'),
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onQueryChanged,
          decoration: const InputDecoration(
            hintText: 'Start typing a brand or salt — e.g. Telma, aspirin',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: 6),
        if (_searching)
          const Padding(
            padding: EdgeInsets.only(top: 18),
            child: Center(
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          )
        else if (_searchError != null)
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 4),
            child: Text(_searchError!,
                key: const Key('med-search-note'),
                style: CcText.bodySm.copyWith(color: Cc.muted)),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.separated(
              key: const Key('med-search-results'),
              shrinkWrap: true,
              padding: const EdgeInsets.only(top: 6),
              itemCount: _hits.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (_, i) {
                final d = _hits[i];
                return InkWell(
                  onTap: () => setState(() => _picked = d),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                    decoration: BoxDecoration(
                      color: Cc.paperRaised,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0x14151510)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.name, style: CcText.listTitle),
                        if (d.subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(d.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  CcText.bodySm.copyWith(color: Cc.muted)),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ];

  List<Widget> _confirmBody() => [
        if ((_picked!.subtitle).isNotEmpty)
          Text(_picked!.subtitle,
              style: CcText.bodySm.copyWith(color: Cc.muted)),
        const SizedBox(height: 14),
        TextField(
          key: const Key('med-dosage-field'),
          controller: _dosage,
          decoration: const InputDecoration(
            labelText: 'Dosage (optional)',
            hintText: 'e.g. 40 mg once daily',
          ),
        ),
        if (_saveError != null) ...[
          const SizedBox(height: 10),
          Text(_saveError!,
              key: const Key('med-save-error'),
              style: CcText.bodySm.copyWith(color: Cc.avoid)),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            TextButton(
              onPressed:
                  _saving ? null : () => setState(() => _picked = null),
              child: const Text('Back'),
            ),
            const Spacer(),
            FilledButton(
              key: const Key('med-add-confirm'),
              onPressed: _saving ? null : _add,
              child: Text(_saving ? 'Adding…' : 'Add medication'),
            ),
          ],
        ),
      ];
}
