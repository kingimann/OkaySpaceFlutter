import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';

String _price(Listing l) => '${l.currency} ${l.price.toStringAsFixed(2)}';

/// Marketplace browse grid with a search field.
class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  late Future<List<Listing>> _listings;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _query();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _query() {
    final q = _search.text.trim();
    _listings = api.marketplace.listings(query: q.isEmpty ? null : q);
  }

  Future<void> _reload() async {
    setState(_query);
    await _listings;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Marketplace'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _reload(),
              decoration: InputDecoration(
                hintText: 'Search listings',
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _reload,
                ),
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: AsyncList<Listing>(
          future: _listings,
          emptyMessage: 'No listings found.',
          emptyIcon: Icons.storefront_outlined,
          builder: (context, items) => GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              childAspectRatio: 0.72,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) =>
                _ListingCard(listing: items[i]),
          ),
        ),
      ),
    );
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final photo = listing.photos.isNotEmpty ? listing.photos.first : null;
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ListingDetailScreen(listingId: listing.id),
      )),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: photo != null
                  ? Image.network(photo,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const ColoredBox(
                          color: Colors.black12,
                          child: Icon(Icons.image_not_supported)))
                  : const ColoredBox(
                      color: Colors.black12,
                      child: Center(child: Icon(Icons.shopping_bag_outlined))),
            ),
          ),
          const SizedBox(height: 6),
          Text(listing.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(_price(listing),
              style: TextStyle(color: Theme.of(context).colorScheme.primary)),
        ],
      ),
    );
  }
}

/// Full detail for a listing, with save / contact actions.
class ListingDetailScreen extends StatefulWidget {
  const ListingDetailScreen({super.key, required this.listingId});

  final String listingId;

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  late Future<Listing> _listing;

  @override
  void initState() {
    super.initState();
    _listing = api.marketplace.get(widget.listingId);
  }

  Future<void> _save() async {
    try {
      await api.marketplace.save(widget.listingId);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Saved')));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _contact() async {
    try {
      await api.marketplace.contactSeller(widget.listingId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Conversation started — see Messages')));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Listing')),
      body: FutureBuilder<Listing>(
        future: _listing,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return CenteredMessage(message: messageFor(snapshot.error));
          }
          final l = snapshot.data!;
          return ListView(
            children: [
              if (l.photos.isNotEmpty)
                AspectRatio(
                  aspectRatio: 1,
                  child: PageView(
                    children: [
                      for (final p in l.photos)
                        Image.network(p,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const ColoredBox(color: Colors.black12)),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.title,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(_price(l),
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary)),
                    if (l.locality != null) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.place_outlined, size: 16),
                        const SizedBox(width: 4),
                        Text(l.locality!),
                      ]),
                    ],
                    const SizedBox(height: 12),
                    Row(children: [
                      Avatar(url: l.seller.picture, name: l.seller.name, radius: 16),
                      const SizedBox(width: 8),
                      Text(l.seller.name),
                    ]),
                    if (l.description != null) ...[
                      const Divider(height: 32),
                      Text(l.description!),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _save,
                            icon: const Icon(Icons.bookmark_border),
                            label: const Text('Save'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _contact,
                            icon: const Icon(Icons.chat_bubble_outline),
                            label: const Text('Contact'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
