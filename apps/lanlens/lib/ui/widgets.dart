import 'package:flutter/material.dart';

import '../core/net.dart';

/// Shown on every active-scan screen. Scanning networks you don't own or
/// administer may be illegal; LanLens is meant for your own LAN.
class AuthorizedUseBanner extends StatelessWidget {
  const AuthorizedUseBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Icon(Icons.verified_user_outlined, color: scheme.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Only scan networks and devices you own or have permission to test.',
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Asks for confirmation before probing a public (non-RFC1918) address.
Future<bool> confirmPublicTarget(BuildContext context, String host) async {
  if (!isValidIPv4(host) || isPrivateIPv4(host)) return true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Public address'),
      content: Text(
          '$host is outside your local network. Only continue if you own this '
          'host or have written permission to test it.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('I am authorized')),
      ],
    ),
  );
  return ok ?? false;
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
        ]),
      );
}

/// Small coloured pill used for severity, state and confidence labels.
class Pill extends StatelessWidget {
  const Pill(this.label, this.color, {super.key});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}
