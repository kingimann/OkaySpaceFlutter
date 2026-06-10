import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'create_listing_screen.dart';

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

  Future<void> _create() async {
    final listing = await Navigator.of(context).push<Listing>(
        MaterialPageRoute(builder: (_) => const CreateListingScreen()));
    if (listing == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ListingDetailScreen(listingId: listing.id)));
    _reload();
  }

  void _openSaved() {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const _SavedListingsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _create,
        child: const Icon(Icons.add),
      ),
      appBar: AppBar(
        title: const Text('Marketplace'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark_border),
            tooltip: 'Saved',
            onPressed: _openSaved,
          ),
        ],
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
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ListingDetailScreen(listingId: listing.id),
      )),
      borderRadius: BorderRadius.circular(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (photo != null)
                    Image.network(photo,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => ColoredBox(
                            color: scheme.surfaceContainerHighest,
                            child: const Icon(Icons.image_not_supported)))
                  else
                    ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: const Center(
                            child: Icon(Icons.shopping_bag_outlined))),
                  // Price chip.
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(_price(listing),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                    ),
                  ),
                  // Saved heart.
                  if (listing.savedByMe || listing.likedByMe)
                    const Positioned(
                      right: 8,
                      top: 8,
                      child: Icon(Icons.favorite, color: Colors.redAccent, size: 20),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(listing.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          Row(
            children: [
              if (listing.condition != null) ...[
                Text(listing.condition!,
                    style: TextStyle(color: scheme.outline, fontSize: 12)),
                if (listing.locality != null)
                  Text(' · ',
                      style: TextStyle(color: scheme.outline, fontSize: 12)),
              ],
              if (listing.locality != null)
                Expanded(
                  child: Text(listing.locality!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.outline, fontSize: 12)),
                ),
            ],
          ),
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
  late Future<List<ListingComment>> _comments;

  @override
  void initState() {
    super.initState();
    _listing = api.marketplace.get(widget.listingId);
    _comments = api.marketplace.comments(widget.listingId);
  }

  Future<void> _addComment() async {
    final text = await promptText(context,
        title: 'Add a comment', hint: 'Comment', action: 'Send');
    if (text == null) return;
    try {
      await api.marketplace.addComment(widget.listingId, text);
      if (mounted) {
        setState(
            () => _comments = api.marketplace.comments(widget.listingId));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
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
                    const Divider(height: 32),
                    Row(
                      children: [
                        const Text('Comments',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _addComment,
                          icon: const Icon(Icons.add_comment_outlined, size: 18),
                          label: const Text('Add'),
                        ),
                      ],
                    ),
                    FutureBuilder<List<ListingComment>>(
                      future: _comments,
                      builder: (context, snap) {
                        final comments = snap.data ?? const [];
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (comments.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text('No comments yet.',
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.outline)),
                          );
                        }
                        return Column(
                          children: [
                            for (final cm in comments)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Avatar(
                                    url: cm.author.picture,
                                    name: cm.author.name,
                                    radius: 16),
                                title: Text(cm.author.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14)),
                                subtitle: Text(cm.text),
                              ),
                          ],
                        );
                      },
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

/// The current user's saved listings.
class _SavedListingsScreen extends StatefulWidget {
  const _SavedListingsScreen();

  @override
  State<_SavedListingsScreen> createState() => _SavedListingsScreenState();
}

class _SavedListingsScreenState extends State<_SavedListingsScreen> {
  late Future<List<Listing>> _saved = api.marketplace.saved();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved listings')),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() => _saved = api.marketplace.saved());
          await _saved;
        },
        child: AsyncList<Listing>(
          future: _saved,
          emptyMessage: 'No saved listings.',
          emptyIcon: Icons.bookmark_border,
          builder: (context, items) => ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final l = items[i];
              return ListTile(
                leading: l.photos.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(l.photos.first,
                            width: 52, height: 52, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox(
                                width: 52, height: 52)))
                    : const Icon(Icons.shopping_bag_outlined),
                title: Text(l.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${l.currency} ${l.price.toStringAsFixed(2)}'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ListingDetailScreen(listingId: l.id))),
              );
            },
          ),
        ),
      ),
    );
  }
}
