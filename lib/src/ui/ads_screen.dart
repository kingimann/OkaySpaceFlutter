import 'package:flutter/material.dart';

import 'common.dart';

/// Advertiser hub: ad-account balance, top-up and active campaigns.
class AdsScreen extends StatefulWidget {
  const AdsScreen({super.key});

  @override
  State<AdsScreen> createState() => _AdsScreenState();
}

class _AdsScreenState extends State<AdsScreen> {
  late Future<Map<String, dynamic>> _account;
  late Future<List<Map<String, dynamic>>> _campaigns;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _account = api.ads.account();
    _campaigns = api.ads.campaignList();
  }

  Future<void> _reload() async {
    setState(_load);
    await _account;
  }

  Future<void> _topup() async {
    final amount = await promptText(context,
        title: 'Top up ad balance',
        hint: 'Amount',
        action: 'Add');
    if (amount == null) return;
    final value = num.tryParse(amount.trim());
    if (value == null || value <= 0) return;
    try {
      await api.ads.topup(value);
      if (mounted) {
        showInfo(context, 'Ad balance topped up');
        _reload();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Advertising')),
      body: MaxWidth(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FutureBuilder<Map<String, dynamic>>(
                future: _account,
                builder: (context, snap) {
                  final a = snap.data ?? const {};
                  final balV = a['balance'] ?? a['ad_balance'] ?? 0;
                  final bal = balV is num ? balV : (num.tryParse('$balV') ?? 0);
                  final currency = '${a['currency'] ?? 'USD'}'.toUpperCase();
                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [scheme.primary, darken(scheme.primary, 0.22)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.campaign,
                                color: Colors.white.withValues(alpha: 0.9)),
                            const SizedBox(width: 8),
                            Text('Ad balance',
                                style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.85))),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text('$currency ${bal.toStringAsFixed(2)}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _topup,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: scheme.primary,
                          ),
                          icon: const Icon(Icons.add),
                          label: const Text('Top up'),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              Text('Campaigns',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _campaigns,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()));
                  }
                  final items = snap.data ?? const [];
                  if (items.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                          child: Text(
                              'No campaigns yet.\nPromote a post to start one.',
                              textAlign: TextAlign.center)),
                    );
                  }
                  return Column(
                    children: [
                      for (final c in items) _campaignTile(c, scheme),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _campaignTile(Map<String, dynamic> c, ColorScheme scheme) {
    final title =
        '${c['headline'] ?? c['title'] ?? c['post_text'] ?? 'Campaign'}';
    final status = '${c['status'] ?? 'active'}';
    final spentV = c['spent'] ?? c['spend'] ?? 0;
    final budgetV = c['budget'] ?? 0;
    final clicks = c['clicks'] ?? c['click_count'] ?? 0;
    final impressions = c['impressions'] ?? c['views'] ?? 0;
    final spent = spentV is num ? spentV : (num.tryParse('$spentV') ?? 0);
    final budget = budgetV is num ? budgetV : (num.tryParse('$budgetV') ?? 0);
    final progress = budget > 0 ? (spent / budget).clamp(0.0, 1.0) : 0.0;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(status,
                      style: TextStyle(
                          color: scheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: progress, minHeight: 6),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Spent \$${spent.toStringAsFixed(2)} / '
                    '\$${budget.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.bodySmall),
                Text('$impressions views · $clicks clicks',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
