import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../okayspace_api.dart';
import 'common.dart';

String _money(num amount, String currency) =>
    '$currency ${amount.toStringAsFixed(2)}';

/// Insights over the wallet's recent transactions: money in vs out, volume
/// by transaction type, the biggest single transaction, and a CSV export.
class WalletInsightsScreen extends StatefulWidget {
  const WalletInsightsScreen({super.key});

  @override
  State<WalletInsightsScreen> createState() => _WalletInsightsScreenState();
}

class _WalletInsightsScreenState extends State<WalletInsightsScreen> {
  late Future<WalletSummary> _summary = api.wallet.summary();

  Future<void> _reload() async {
    setState(() => _summary = api.wallet.summary());
    await _summary;
  }

  /// Copies recent transactions to the clipboard as CSV.
  Future<void> _exportCsv(WalletSummary w) async {
    String esc(String? v) {
      final s = (v ?? '').replaceAll('"', '""');
      return '"$s"';
    }

    final rows = [
      'reference,type,amount,currency,counterparty,note,date',
      for (final t in w.recent)
        [
          esc(t.id),
          esc(t.type),
          t.amount.toString(),
          esc(t.currency),
          esc(t.counterpartyName),
          esc(t.note),
          esc(t.createdAt?.toIso8601String()),
        ].join(','),
    ];
    await Clipboard.setData(ClipboardData(text: rows.join('\n')));
    if (mounted) {
      showInfo(context, 'Copied ${w.recent.length} transactions as CSV');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: OkayAppBar(
        title: const Text('Wallet insights'),
        actions: [
          FutureBuilder<WalletSummary>(
            future: _summary,
            builder: (context, snapshot) => IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Export CSV',
              onPressed: snapshot.hasData && snapshot.data!.recent.isNotEmpty
                  ? () => _exportCsv(snapshot.data!)
                  : null,
            ),
          ),
        ],
      ),
      body: MaxWidth(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: FutureBuilder<WalletSummary>(
            future: _summary,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return CenteredMessage(
                    message: messageFor(snapshot.error),
                    icon: Icons.error_outline,
                    onRetry: _reload);
              }
              final w = snapshot.data!;
              if (w.recent.isEmpty) {
                return const CenteredMessage(
                    message: 'No transactions to analyze yet.',
                    icon: Icons.insights_outlined);
              }

              final inTotal = w.recent
                  .where((t) => t.amount >= 0)
                  .fold<num>(0, (a, t) => a + t.amount);
              final outTotal = w.recent
                  .where((t) => t.amount < 0)
                  .fold<num>(0, (a, t) => a + t.amount.abs());
              final net = inTotal - outTotal;
              final flow = inTotal + outTotal;

              // Volume per transaction type, largest first.
              final byType = <String, ({num volume, int count})>{};
              for (final t in w.recent) {
                final k = t.type ?? 'other';
                final cur = byType[k] ?? (volume: 0, count: 0);
                byType[k] =
                    (volume: cur.volume + t.amount.abs(), count: cur.count + 1);
              }
              final types = byType.entries.toList()
                ..sort((a, b) => b.value.volume.compareTo(a.value.volume));
              final biggest = w.recent
                  .reduce((a, b) => b.amount.abs() > a.amount.abs() ? b : a);

              const inColor = Color(0xFF22C55E);
              final outColor = scheme.error;

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Net flow headline.
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [scheme.primary, darken(scheme.primary, 0.28)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Net flow (recent activity)',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 12)),
                        const SizedBox(height: 6),
                        Text(
                            '${net >= 0 ? '+' : '−'}${_money(net.abs(), w.currency)}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 28)),
                        const SizedBox(height: 14),
                        // In vs out proportion bar.
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: SizedBox(
                            height: 10,
                            child: Row(
                              children: [
                                Expanded(
                                  flex: flow > 0
                                      ? ((inTotal / flow) * 1000).round()
                                      : 1,
                                  child: const ColoredBox(color: inColor),
                                ),
                                Expanded(
                                  flex: flow > 0
                                      ? ((outTotal / flow) * 1000).round()
                                      : 1,
                                  child: ColoredBox(color: outColor),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('In ${_money(inTotal, w.currency)}',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12)),
                            Text('Out ${_money(outTotal, w.currency)}',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('By type',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  for (final e in types)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(e.key,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                              ),
                              Text(
                                  '${_money(e.value.volume, w.currency)} · ${e.value.count}×',
                                  style: TextStyle(
                                      color: scheme.outline, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 5),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: flow > 0 ? e.value.volume / flow : 0,
                              minHeight: 7,
                              backgroundColor: scheme.surfaceContainerHighest,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text('Biggest transaction',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: (biggest.amount >= 0
                                ? inColor
                                : outColor)
                            .withValues(alpha: 0.15),
                        child: Icon(
                            biggest.amount >= 0
                                ? Icons.south_west
                                : Icons.north_east,
                            color:
                                biggest.amount >= 0 ? inColor : outColor),
                      ),
                      title: Text(biggest.type ?? 'Transaction',
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          biggest.note ?? biggest.counterpartyName ?? ''),
                      trailing: Text(
                        '${biggest.amount >= 0 ? '+' : '−'}${_money(biggest.amount.abs(), w.currency)}',
                        style: TextStyle(
                            color: biggest.amount >= 0 ? inColor : outColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 15),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: scheme.outline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                            'Based on the ${w.recent.length} most recent transactions.',
                            style: TextStyle(
                                color: scheme.outline, fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
