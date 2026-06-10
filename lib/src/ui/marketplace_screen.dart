import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../okayspace_api.dart';
import 'business_screen.dart';
import 'common.dart';
import 'create_listing_screen.dart';

String _price(Listing l) => '${l.currency} ${l.price.toStringAsFixed(2)}';

/// Marketplace browse grid with a search field.
class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key, this.embedded = false});

  /// True when shown as a home tab (the shell already provides the bottom nav);
  /// false when pushed as a standalone route (it shows its own nav).
  final bool embedded;

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

const _kSorts = <(String, String?)>[
  ('Newest', null),
  ('Price: low to high', 'price_asc'),
  ('Price: high to low', 'price_desc'),
  ('Most popular', 'popular'),
];

const _kConditions = <(String, String?)>[
  ('Any condition', null),
  ('New', 'new'),
  ('Like new', 'like_new'),
  ('Good', 'good'),
  ('Fair', 'fair'),
];

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  late Future<List<Listing>> _listings;
  final _search = TextEditingController();
  String? _sort;
  num? _minPrice;
  num? _maxPrice;
  String? _condition;

  bool get _hasFilters =>
      _minPrice != null || _maxPrice != null || _condition != null;

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
    _listings = api.marketplace.listings(
      query: q.isEmpty ? null : q,
      sort: _sort,
      minPrice: _minPrice,
      maxPrice: _maxPrice,
      condition: _condition,
    );
  }

  Future<void> _pickFilters() async {
    final minCtrl =
        TextEditingController(text: _minPrice?.toString() ?? '');
    final maxCtrl =
        TextEditingController(text: _maxPrice?.toString() ?? '');
    var condition = _condition;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (context, setSheet) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Filters',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: minCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Min price', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: maxCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Max price', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                children: [
                  for (final c in _kConditions)
                    ChoiceChip(
                      label: Text(c.$1),
                      selected: condition == c.$2,
                      onSelected: (_) => setSheet(() => condition = c.$2),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Clear'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (applied == null) return;
    setState(() {
      if (applied) {
        _minPrice = num.tryParse(minCtrl.text.trim());
        _maxPrice = num.tryParse(maxCtrl.text.trim());
        _condition = condition;
      } else {
        _minPrice = null;
        _maxPrice = null;
        _condition = null;
      }
      _query();
    });
    minCtrl.dispose();
    maxCtrl.dispose();
  }

  void _pickSort() async {
    final chosen = await showModalBottomSheet<String?>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
                title: Text('Sort by',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            for (final s in _kSorts)
              ListTile(
                title: Text(s.$1),
                trailing: s.$2 == _sort ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, s.$2),
              ),
          ],
        ),
      ),
    );
    // showModalBottomSheet returns null both for "Newest" and for dismiss;
    // only apply when the sheet item was actually tapped.
    if (!mounted) return;
    setState(() {
      _sort = chosen;
      _query();
    });
  }

  void _openMine() {
    if (currentUserId == null) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _MyListingsScreen(userId: currentUserId!)));
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
    if (mounted) _reload();
  }

  void _openSaved() {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const _SavedListingsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: !widget.embedded,
      bottomNavigationBar: widget.embedded ? null : const OkayBottomNav(),
      appBar: OkayAppBar(
        title: const Text('Marketplace'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Sell something',
            onPressed: _create,
          ),
          IconButton(
            icon: Icon(_hasFilters ? Icons.filter_alt : Icons.filter_alt_outlined),
            tooltip: 'Filters',
            color: _hasFilters ? Theme.of(context).colorScheme.primary : null,
            onPressed: _pickFilters,
          ),
          IconButton(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
            onPressed: _pickSort,
          ),
          IconButton(
            icon: const Icon(Icons.bookmark_border),
            tooltip: 'Saved',
            onPressed: _openSaved,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'mine') _openMine();
              if (v == 'business') {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const BusinessScreen()));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'mine', child: Text('My listings')),
              PopupMenuItem(value: 'business', child: Text('My storefront')),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
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
      body: MaxWidth(
        maxWidth: 1000,
        child: RefreshIndicator(
        onRefresh: _reload,
        child: AsyncList<Listing>(
          future: _listings,
          loading: const GridSkeleton(),
          emptyMessage: 'No listings found.',
          emptyIcon: Icons.storefront_outlined,
          builder: (context, items) => GridView.builder(
            // Bottom inset clears the floating nav pill.
            padding: const EdgeInsets.fromLTRB(12, 12, 12, kBottomNavInset),
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
  bool? _saved; // local override once toggled

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

  Future<void> _toggleSave(Listing l) async {
    final wasSaved = _saved ?? l.savedByMe;
    setState(() => _saved = !wasSaved);
    try {
      wasSaved
          ? await api.marketplace.unsave(widget.listingId)
          : await api.marketplace.save(widget.listingId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(wasSaved ? 'Removed' : 'Saved')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saved = wasSaved);
        showError(context, e);
      }
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

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(
        text: 'https://okayspace.ca/listing/${widget.listingId}'));
    if (mounted) showInfo(context, 'Link copied');
  }

  String _convName(ConversationView c) {
    if (c.name != null && c.name!.isNotEmpty) return c.name!;
    if (c.otherUser != null) return c.otherUser!.name;
    if (c.members.isNotEmpty) return c.members.map((m) => m.name).join(', ');
    return 'Conversation';
  }

  Future<void> _shareToChat() async {
    Listing? l;
    try {
      l = await _listing;
    } catch (_) {}
    final convs = await api.messaging
        .conversations()
        .catchError((_) => <ConversationView>[]);
    if (!mounted) return;
    final target = await showModalBottomSheet<ConversationView>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
                title: Text('Share to',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in convs)
                    ListTile(
                      leading: Avatar(
                          url: c.avatar ?? c.otherUser?.picture,
                          name: _convName(c)),
                      title: Text(_convName(c),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(context, c),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;
    final text = 'Check out this listing: ${l?.title ?? ''}\n'
        'https://okayspace.ca/listing/${widget.listingId}';
    try {
      await api.messaging.sendText(target.id, text);
      if (mounted) showInfo(context, 'Shared to chat');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OkayAppBar(
        title: const Text('Listing'),
        actions: [
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: 'Copy link',
            onPressed: _copyLink,
          ),
          IconButton(
            icon: const Icon(Icons.forward_to_inbox_outlined),
            tooltip: 'Share to a chat',
            onPressed: _shareToChat,
          ),
        ],
      ),
      body: MaxWidth(
        child: FutureBuilder<Listing>(
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
                          child: Builder(builder: (context) {
                            final saved = _saved ?? l.savedByMe;
                            return OutlinedButton.icon(
                              onPressed: () => _toggleSave(l),
                              icon: Icon(saved
                                  ? Icons.bookmark
                                  : Icons.bookmark_border),
                              label: Text(saved ? 'Saved' : 'Save'),
                            );
                          }),
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
      ),
    );
  }
}

/// The current user's saved listings.
/// The current user's own listings, with delete.
class _MyListingsScreen extends StatefulWidget {
  const _MyListingsScreen({required this.userId});

  final String userId;

  @override
  State<_MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<_MyListingsScreen> {
  late Future<List<Listing>> _mine;

  @override
  void initState() {
    super.initState();
    _mine = api.marketplace.userListings(widget.userId);
  }

  Future<void> _reload() async {
    setState(() => _mine = api.marketplace.userListings(widget.userId));
    await _mine;
  }

  Future<void> _delete(Listing l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete listing?'),
        content: Text('“${l.title}” will be removed permanently.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await api.marketplace.delete(l.id);
      if (mounted) showInfo(context, 'Listing deleted');
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const OkayAppBar(title: Text('My listings')),
      body: MaxWidth(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: AsyncList<Listing>(
            future: _mine,
            emptyMessage: 'You have no listings yet.',
            emptyIcon: Icons.sell_outlined,
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
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox(width: 52, height: 52)))
                      : const Icon(Icons.shopping_bag_outlined),
                  title:
                      Text(l.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle:
                      Text('${l.currency} ${l.price.toStringAsFixed(2)}'),
                  trailing: IconButton(
                    icon: Icon(Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error),
                    onPressed: () => _delete(l),
                  ),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ListingDetailScreen(listingId: l.id))),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

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
      appBar: const OkayAppBar(title: Text('Saved listings')),
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
