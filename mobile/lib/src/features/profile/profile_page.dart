import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/fit_api.dart';
import '../../core/lifestyle_api.dart';
import '../../core/me_api.dart';
import '../../core/text.dart';
import '../../core/theme.dart';
import '../../core/vault_api.dart';
import '../../core/widgets.dart';

/// The full profile page — replaces the old half-screen bottom sheet. Everything
/// the user told us during onboarding, editable in place, plus the CareCart Fit
/// summary and the account actions.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({
    super.key,
    this.onClose,
    this.onOpenFit,
    this.onOpenMeds,
    this.onDeleteAccount,
  });

  final VoidCallback? onClose;
  final VoidCallback? onOpenFit;
  final VoidCallback? onOpenMeds;
  final Future<void> Function()? onDeleteAccount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider).asData?.value ?? const MeInfo();
    final life = ref.watch(lifestyleProfileProvider);
    final health = ref.watch(healthProfileProvider);
    final fit = ref.watch(fitProvider);

    return CcScreen(
      background: Cc.paper,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          const SizedBox(height: 4),
          Row(
            children: [
              CcRoundButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onTap: onClose,
                  size: 36),
              const SizedBox(width: 12),
              const Text('Profile', style: CcText.h1),
            ],
          ),
          const SizedBox(height: 18),

          // ---- you ----
          _Card(children: [
            _Row(
              label: 'Name',
              value: (me.displayName ?? '').trim().isEmpty
                  ? 'Not set'
                  : me.displayName!.trim(),
              onTap: () => _editName(context, ref, me.displayName ?? ''),
            ),
          ]),
          const SizedBox(height: 14),

          // ---- fit ----
          _FitCard(fit: fit, onTap: onOpenFit),
          const SizedBox(height: 14),

          _SectionLabel('Lifestyle'),
          const SizedBox(height: 8),
          life.when(
            loading: _loading,
            error: (_, _) => _errorCard("Couldn't load your lifestyle answers."),
            data: (lp) => _LifestyleCard(profile: lp ?? const LifestyleProfile(),
                ref: ref),
          ),
          const SizedBox(height: 14),

          _SectionLabel('Health basics'),
          const SizedBox(height: 8),
          health.when(
            loading: _loading,
            error: (_, _) => _errorCard("Couldn't load your health profile."),
            data: (hp) => _HealthCard(
                profile: hp ?? const HealthProfileData(), ref: ref),
          ),
          const SizedBox(height: 14),

          _Card(children: [
            _Row(
              label: 'Medications',
              value: 'Manage',
              onTap: onOpenMeds,
            ),
          ]),
          const SizedBox(height: 20),

          if (onDeleteAccount != null)
            _DeleteAccountButton(onConfirm: onDeleteAccount!),
          const SizedBox(height: 14),
          Text(
            'Everything here is stored encrypted on your device and the server, '
            'and cross-checked only against your own scans.',
            style: CcText.bodySm.copyWith(color: Cc.muted, height: 1.5),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- name edit
  Future<void> _editName(
      BuildContext context, WidgetRef ref, String current) async {
    final ctrl = TextEditingController(text: current);
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Cc.paper,
        title: const Text('Your name', style: CcText.h3),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(counterText: ''),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (v == null || v.isEmpty || !context.mounted) return;
    final err = await ref.read(meApiProvider).updateName(v);
    if (!context.mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    ref.invalidate(meProvider);
  }
}

Widget _loading() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 18),
    child: Center(
        child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2))));

Widget _errorCard(String text) => _Card(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text, style: CcText.bodySm.copyWith(color: Cc.muted)),
      ),
    ]);

// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: CcText.mono.copyWith(
          color: Cc.muted, fontSize: 11, letterSpacing: 1.0));
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: Cc.paperRaised,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x12151510)),
        ),
        child: Column(children: children),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.onTap});
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: CcText.body.copyWith(fontWeight: FontWeight.w500)),
              ),
              Text(value,
                  style: CcText.bodySm.copyWith(color: Cc.muted)),
              if (onTap != null) ...[
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: Cc.muted),
              ],
            ],
          ),
        ),
      );
}

class _FitCard extends StatelessWidget {
  const _FitCard({required this.fit, this.onTap});
  final AsyncValue<FitResult> fit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final f = fit.asData?.value;
    int? score;
    String tier = '';
    if (f is FitLoaded) {
      score = f.fit.score;
      tier = f.fit.tier ?? '';
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Cc.sageSoft,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Text(score?.toString() ?? '–',
                style: const TextStyle(
                    fontFamily: 'Bricolage',
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: Cc.oliveDark)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('CareCart Fit',
                      style: TextStyle(
                          fontFamily: 'Bricolage',
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: Cc.ink)),
                  const SizedBox(height: 2),
                  Text(
                      score == null
                          ? 'Answer lifestyle + scan a few labels'
                          : 'Lifestyle + medicines · $tier',
                      style: CcText.bodySm.copyWith(color: Cc.oliveDark)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Cc.oliveDark),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ lifestyle card

class _LifestyleCard extends StatelessWidget {
  const _LifestyleCard({required this.profile, required this.ref});
  final LifestyleProfile profile;
  final WidgetRef ref;

  Future<void> _save(BuildContext context, LifestyleProfile next) async {
    final err = await ref.read(lifestyleApiProvider).put(next);
    if (!context.mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    ref.invalidate(lifestyleProfileProvider);
    ref.invalidate(fitProvider);
  }

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return _Card(children: [
      _Row(
        label: 'Sleep',
        value: p.sleepHours == null
            ? 'Not set'
            : '${p.sleepHours!.toStringAsFixed(1)} h',
        onTap: () => _pickNumber(context, 'Sleep (hours/night)',
            p.sleepHours ?? 7.0, 3, 12, 0.5,
            (v) => _save(context, p.copyWith(sleepHours: v))),
      ),
      _Row(
        label: 'Active days / week',
        value: p.exerciseDays?.toString() ?? 'Not set',
        onTap: () => _pickChoice(
            context,
            'Active days a week',
            [for (var i = 0; i <= 7; i++) '$i'],
            p.exerciseDays?.toString(),
            (v) => _save(context, p.copyWith(exerciseDays: int.parse(v)))),
      ),
      _Row(
        label: 'Smoking',
        value: p.smoking ?? 'Not set',
        onTap: () => _pickChoice(context, 'Smoking',
            const ['none', 'occasional', 'daily'], p.smoking,
            (v) => _save(context, p.copyWith(smoking: v))),
      ),
      _Row(
        label: 'Alcohol',
        value: p.alcohol ?? 'Not set',
        onTap: () => _pickChoice(context, 'Alcohol',
            const ['none', 'occasional', 'weekly', 'daily'], p.alcohol,
            (v) => _save(context, p.copyWith(alcohol: v))),
      ),
      _Row(
        label: 'Typical stress',
        value: p.stress == null ? 'Not set' : '${p.stress}/5',
        onTap: () => _pickChoice(context, 'Typical stress (1–5)',
            const ['1', '2', '3', '4', '5'], p.stress?.toString(),
            (v) => _save(context, p.copyWith(stress: int.parse(v)))),
      ),
    ]);
  }
}

// -------------------------------------------------------------- health card

class _HealthCard extends StatelessWidget {
  const _HealthCard({required this.profile, required this.ref});
  final HealthProfileData profile;
  final WidgetRef ref;

  Future<void> _save(BuildContext context, HealthProfileData next) async {
    final err = await ref.read(vaultApiProvider).putHealthProfile(
          gender: next.gender,
          activityLevel: next.activityLevel,
          weight: next.weight,
          height: next.height,
          weightUnit: next.weightUnit ?? 'kg',
          heightUnit: next.heightUnit ?? 'cm',
          diet: next.diet,
        );
    if (!context.mounted) return;
    if (err is VaultError) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err.message)));
      return;
    }
    ref.invalidate(healthProfileProvider);
    ref.invalidate(fitProvider);
  }

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return _Card(children: [
      _Row(
        label: 'Sex',
        value: p.gender ?? 'Not set',
        onTap: () => _pickChoice(context, 'Sex',
            const ['male', 'female', 'prefer not to say'], p.gender,
            (v) => _save(context, p.copyWith(gender: v))),
      ),
      _Row(
        label: 'Weight',
        value: p.weight == null
            ? 'Not set'
            : '${p.weight!.toStringAsFixed(0)} ${p.weightUnit ?? 'kg'}',
        onTap: () => _pickNumber(context, 'Weight', p.weight ?? 70, 20, 350, 1,
            (v) => _save(context, p.copyWith(weight: v))),
      ),
      _Row(
        label: 'Height',
        value: p.height == null
            ? 'Not set'
            : '${p.height!.toStringAsFixed(0)} ${p.heightUnit ?? 'cm'}',
        onTap: () => _pickNumber(context, 'Height', p.height ?? 170, 90, 250, 1,
            (v) => _save(context, p.copyWith(height: v))),
      ),
      _Row(
        label: 'Diet preferences',
        value: p.diet.isEmpty ? 'None' : p.diet.join(', '),
        onTap: () => _pickMulti(
            context,
            'Diet preferences',
            const [
              'Low sodium', 'Low sugar', 'Low fat', 'Low potassium',
              'Vegetarian', 'Vegan', 'Jain', 'High protein'
            ],
            p.diet,
            (v) => _save(context, p.copyWith(diet: v))),
      ),
    ]);
  }
}

// -------------------------------------------------------------- edit helpers

Future<void> _pickChoice(BuildContext context, String title,
    List<String> options, String? current, void Function(String) onPick) async {
  final v = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Cc.paper,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            child: Text(title, style: CcText.h3),
          ),
          for (final o in options)
            ListTile(
              title: Text(o, style: CcText.body),
              trailing: o == current
                  ? const Icon(Icons.check_rounded, color: Cc.oliveDark)
                  : null,
              onTap: () => Navigator.pop(context, o),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (v != null) onPick(v);
}

Future<void> _pickMulti(BuildContext context, String title,
    List<String> options, List<String> current,
    void Function(List<String>) onDone) async {
  final sel = {...current};
  final done = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Cc.paper,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Text(title, style: CcText.h3),
            ),
            for (final o in options)
              CheckboxListTile(
                value: sel.contains(o),
                title: Text(o, style: CcText.body),
                onChanged: (b) => setState(
                    () => b == true ? sel.add(o) : sel.remove(o)),
              ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (done == true) onDone(sel.toList());
}

Future<void> _pickNumber(BuildContext context, String title, double start,
    double min, double max, double step, void Function(double) onPick) async {
  final ctrl = TextEditingController(text: start.toStringAsFixed(step < 1 ? 1 : 0));
  final v = await showDialog<double>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: Cc.paper,
      title: Text(title, style: CcText.h3),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            final parsed = double.tryParse(ctrl.text.trim());
            if (parsed == null) return Navigator.pop(context);
            Navigator.pop(context, parsed.clamp(min, max).toDouble());
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (v != null) onPick(v);
}

// --------------------------------------------------------- delete account

class _DeleteAccountButton extends StatefulWidget {
  const _DeleteAccountButton({required this.onConfirm});
  final Future<void> Function() onConfirm;

  @override
  State<_DeleteAccountButton> createState() => _DeleteAccountButtonState();
}

class _DeleteAccountButtonState extends State<_DeleteAccountButton> {
  bool _busy = false;

  Future<void> _run() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: Cc.paper,
        title: const Text('Delete everything?'),
        content: const Text(
          'This permanently removes your profile, lifestyle answers, '
          'medications, scan history and Fit score. It cannot be undone.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dctx).pop(false),
              child: const Text('Keep my data')),
          TextButton(
            key: const Key('profile-delete-confirm'),
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Cc.avoid)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    await widget.onConfirm();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('profile-delete-account'),
      onTap: _busy ? null : _run,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF7E2D5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          _busy ? 'Deleting…' : 'Delete account & all data',
          style: CcText.body.copyWith(
              color: const Color(0xFF8A4526), fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
