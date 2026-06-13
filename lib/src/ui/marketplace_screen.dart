import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../okayspace_api.dart';
import 'business_screen.dart';
import 'common.dart';
import 'create_listing_screen.dart';
import 'profile_screen.dart';

String _price(Listing l) => '${l.currency} ${l.price.toStringAsFixed(2)}';

/// Human label for a stored condition value (e.g. 'like_new' → 'Like new').
String _conditionLabel(String? c) {
  switch (c) {
    case 'new':
      return 'New';
    case 'like_new':
      return 'Like new';
    case 'good':
      return 'Good';
    case 'fair':
      return 'Fair';
    case 'used':
      return 'Used';
    default:
      return c ?? '';
  }
}

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
  ('Price: low to high', 'price_low'),
  ('Price: high to low', 'price_high'),
  ('Most popular', 'popular'),
];

const _kConditions = <(String, String?)>[
  ('Any condition', null),
  ('New', 'new'),
  ('Like new', 'like_new'),
  ('Good', 'good'),
  ('Fair', 'fair'),
];

const _kCategories = <(String, String?)>[
  ('All categories', null),
  ('Electronics', 'electronics'),
  ('Vehicles', 'vehicles'),
  ('Home', 'home'),
  ('Fashion', 'fashion'),
  ('Toys & games', 'toys'),
  ('Sports', 'sports'),
  ('Books', 'books'),
  ('Other', 'other'),
];

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  late Future<List<Listing>> _listings;
  final _search = TextEditingController();
  String? _sort;
  num? _minPrice;
  num? _maxPrice;
  String? _condition;
  String? _category;

  bool get _hasFilters =>
      _minPrice != null ||
      _maxPrice != null ||
      _condition != null ||
      _category != null;

  @override
  void initState() {
    super.initState();
    _query();
    refreshMarketplaceOffersBadge();
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
      category: _category,
    );
  }

  Future<void> _pickFilters() async {
    final minCtrl =
        TextEditingController(text: _minPrice?.toString() ?? '');
    final maxCtrl =
        TextEditingController(text: _maxPrice?.toString() ?? '');
    var condition = _condition;
    var category = _category;
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
              const Text('Category'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final c in _kCategories)
                    ChoiceChip(
                      label: Text(c.$1),
                      selected: category == c.$2,
                      onSelected: (_) => setSheet(() => category = c.$2),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              const Text('Condition'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
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
        _category = category;
      } else {
        _minPrice = null;
        _maxPrice = null;
        _condition = null;
        _category = null;
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

  Future<void> _saveCurrentSearch() async {
    final q = _search.text.trim();
    try {
      await api.marketplace.saveSearch(
        query: q.isEmpty ? null : q,
        category: _category,
        condition: _condition,
        minPrice: _minPrice,
        maxPrice: _maxPrice,
        sort: _sort,
      );
      if (mounted) showInfo(context, 'Search saved');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _openSavedSearches() async {
    final chosen = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(builder: (_) => const SavedSearchesScreen()));
    if (chosen == null || !mounted) return;
    // Apply the chosen saved search's criteria to the current view.
    setState(() {
      _search.text = '${chosen['query'] ?? ''}';
      _category = chosen['category'] as String?;
      _condition = chosen['condition'] as String?;
      _minPrice = chosen['min_price'] as num?;
      _maxPrice = chosen['max_price'] as num?;
      _sort = chosen['sort'] as String?;
      _query();
    });
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
              if (v == 'offers') {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const MyOffersScreen()));
              }
              if (v == 'purchases') {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const PurchasesScreen()));
              }
              if (v == 'save_search') _saveCurrentSearch();
              if (v == 'saved_searches') _openSavedSearches();
              if (v == 'business') {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const BusinessScreen()));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'mine', child: Text('My listings')),
              PopupMenuItem(value: 'offers', child: Text('My offers')),
              PopupMenuItem(value: 'purchases', child: Text('Purchases')),
              PopupMenuItem(value: 'save_search', child: Text('Save current search')),
              PopupMenuItem(value: 'saved_searches', child: Text('Saved searches')),
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

/// A small rounded meta chip (condition / negotiable / sold) on the detail.
class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, this.icon, this.highlight = false});

  final String label;
  final IconData? icon;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = highlight ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: highlight ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Text(label, style: TextStyle(fontSize: 12, color: fg)),
        ],
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
                        loadingBuilder: (_, child, progress) => progress == null
                            ? child
                            : ColoredBox(color: scheme.surfaceContainerHighest),
                        errorBuilder: (_, __, ___) => ColoredBox(
                            color: scheme.surfaceContainerHighest,
                            child: const Icon(Icons.image_not_supported)))
                  else
                    ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: const Center(
                            child: Icon(Icons.shopping_bag_outlined))),
                  // Sold listings get a dimming overlay + ribbon.
                  if (listing.status == 'sold')
                    Container(
                      color: Colors.black.withValues(alpha: 0.45),
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('SOLD',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5)),
                      ),
                    ),
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
                  // "Negotiable" hint so buyers know offers are welcome.
                  if (listing.negotiable && listing.status != 'sold')
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('Negotiable',
                            style: TextStyle(color: Colors.white, fontSize: 11)),
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
                Text(_conditionLabel(listing.condition),
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
  Future<List<Listing>>? _moreFromSeller;
  bool? _saved; // local override once toggled
  Future<int>? _openOfferCount; // memoized open-offer count for the owner

  /// Count of still-open offers on this listing (owner only). Memoized so it
  /// isn't re-fetched on every rebuild; reset after the offers sheet closes.
  Future<int> _openOffersFuture() {
    return _openOfferCount ??= api.marketplace
        .listingOffers(widget.listingId)
        .then((offers) => offers
            .where((o) => o['status'] == 'pending' || o['status'] == 'countered')
            .length)
        .catchError((_) => 0);
  }

  @override
  void initState() {
    super.initState();
    _listing = api.marketplace.get(widget.listingId);
    _comments = api.marketplace.comments(widget.listingId);
    // Other listings by the same seller (current one excluded).
    _listing.then((l) {
      if (mounted && l.userId.isNotEmpty) {
        setState(() {
          _moreFromSeller = api.marketplace.userListings(l.userId).then(
              (items) =>
                  items.where((x) => x.id != widget.listingId).toList());
        });
      }
    }).catchError((_) {});
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

  Future<void> _makeOffer(Listing l) async {
    final amountCtl =
        TextEditingController(text: l.price > 0 ? l.price.toStringAsFixed(0) : '');
    final msgCtl = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Make an offer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  prefixText: '${l.currency} ', labelText: 'Your offer'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: msgCtl,
              decoration: const InputDecoration(labelText: 'Message (optional)'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Send offer')),
        ],
      ),
    );
    if (submitted != true) return;
    final amount = num.tryParse(amountCtl.text.trim());
    if (amount == null || amount <= 0) {
      if (mounted) showInfo(context, 'Enter a valid amount');
      return;
    }
    try {
      await api.marketplace
          .makeOffer(l.id, amount, message: msgCtl.text.trim());
      if (mounted) showInfo(context, 'Offer sent');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _viewOffers(Listing l) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _ListingOffersSheet(listingId: l.id, currency: l.currency),
    );
    // Acting on offers in the sheet may change the open count — re-fetch it.
    if (mounted) setState(() => _openOfferCount = null);
    refreshMarketplaceOffersBadge();
  }

  Future<void> _markSold(Listing l) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark as sold?'),
        content: const Text("Buyers won't be able to make new offers, and it'll "
            'show as sold.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mark sold')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await api.marketplace.update(l.id, {'status': 'sold'});
      if (mounted) {
        setState(() => _listing = api.marketplace.get(widget.listingId));
        showInfo(context, 'Marked as sold');
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
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (l.status == 'sold')
                          const _MetaChip(label: 'Sold', icon: Icons.sell),
                        if (l.condition != null)
                          _MetaChip(label: _conditionLabel(l.condition)),
                        if (l.negotiable && l.status != 'sold')
                          const _MetaChip(
                              label: 'Negotiable',
                              icon: Icons.local_offer_outlined,
                              highlight: true),
                      ],
                    ),
                    if (l.locality != null) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.place_outlined, size: 16),
                        const SizedBox(width: 4),
                        Text(l.locality!),
                      ]),
                    ],
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: l.userId.isEmpty
                          ? null
                          : () => ProfileScreen.open(context, l.userId),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Avatar(
                              url: l.seller.picture,
                              name: l.seller.name,
                              radius: 16),
                          const SizedBox(width: 8),
                          Expanded(child: Text(l.seller.name)),
                          Icon(Icons.chevron_right,
                              size: 18,
                              color: Theme.of(context).colorScheme.outline),
                        ]),
                      ),
                    ),
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
                    if (currentUserId != null &&
                        currentUserId != l.userId &&
                        l.status != 'sold') ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _makeOffer(l),
                          icon: const Icon(Icons.local_offer_outlined),
                          label: const Text('Make an offer'),
                        ),
                      ),
                    ],
                    if (currentUserId != null && currentUserId == l.userId) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _viewOffers(l),
                              icon: const Icon(Icons.local_offer_outlined),
                              label: FutureBuilder<int>(
                                future: _openOffersFuture(),
                                builder: (_, s) {
                                  final n = s.data ?? 0;
                                  return Text(
                                      n > 0 ? 'View offers ($n)' : 'View offers');
                                },
                              ),
                            ),
                          ),
                          if (l.status != 'sold') ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _markSold(l),
                                icon: const Icon(Icons.sell_outlined),
                                label: const Text('Mark sold'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                    if (_moreFromSeller != null)
                      FutureBuilder<List<Listing>>(
                        future: _moreFromSeller,
                        builder: (context, snap) {
                          final more = snap.data ?? const <Listing>[];
                          if (more.isEmpty) return const SizedBox.shrink();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Divider(height: 32),
                              const Text('More from this seller',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 150,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: more.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: 10),
                                  itemBuilder: (context, i) {
                                    final m = more[i];
                                    final scheme =
                                        Theme.of(context).colorScheme;
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () => Navigator.of(context)
                                          .push(MaterialPageRoute(
                                        builder: (_) => ListingDetailScreen(
                                            listingId: m.id),
                                      )),
                                      child: SizedBox(
                                        width: 120,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              child: m.photos.isNotEmpty
                                                  ? Image.network(
                                                      m.photos.first,
                                                      width: 120,
                                                      height: 92,
                                                      fit: BoxFit.cover)
                                                  : Container(
                                                      width: 120,
                                                      height: 92,
                                                      color: scheme
                                                          .surfaceContainerHighest,
                                                      child: Icon(
                                                          Icons
                                                              .storefront_outlined,
                                                          color: scheme
                                                              .outline),
                                                    ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(m.title,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontSize: 12.5,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                            Text(_price(m),
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: scheme.primary,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          );
                        },
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


/// Seller's view of the offers on a listing, with accept / decline / counter.
class _ListingOffersSheet extends StatefulWidget {
  const _ListingOffersSheet({required this.listingId, required this.currency});

  final String listingId;
  final String currency;

  @override
  State<_ListingOffersSheet> createState() => _ListingOffersSheetState();
}

class _ListingOffersSheetState extends State<_ListingOffersSheet> {
  late Future<List<Map<String, dynamic>>> _offers;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _offers = api.marketplace.listingOffers(widget.listingId);
  }

  void _reload() =>
      setState(() => _offers = api.marketplace.listingOffers(widget.listingId));

  Future<void> _act(Future<void> Function() op) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await op();
      _reload();
      refreshMarketplaceOffersBadge();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _counter(String offerId) async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Counter offer'),
        content: TextField(
          controller: ctl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(prefixText: '${widget.currency} ', labelText: 'Your price'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Counter')),
        ],
      ),
    );
    if (ok != true) return;
    final amount = num.tryParse(ctl.text.trim());
    if (amount == null || amount <= 0) {
      if (mounted) showInfo(context, 'Enter a valid amount');
      return;
    }
    await _act(() => api.marketplace.counterOffer(offerId, amount));
  }

  String _money(Object? v) =>
      '${widget.currency} ${(num.tryParse('${v ?? 0}') ?? 0).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _offers,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final offers = snap.data ?? const [];
            if (offers.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Text('No offers yet.', textAlign: TextAlign.center),
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Offers',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: offers.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final o = offers[i];
                      final status = '${o['status'] ?? 'pending'}';
                      final open = status == 'pending' || status == 'countered';
                      final id = '${o['id']}';
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            '${o['buyer_name'] ?? 'A buyer'} · ${_money(o['amount'])}'),
                        subtitle: Text([
                          status,
                          if (o['counter_amount'] != null)
                            'countered ${_money(o['counter_amount'])}',
                          if ((o['message'] ?? '').toString().isNotEmpty) '“${o['message']}”',
                        ].join(' · ')),
                        trailing: open
                            ? Wrap(
                                spacing: 4,
                                children: [
                                  IconButton(
                                    tooltip: 'Accept',
                                    icon: const Icon(Icons.check_circle_outline),
                                    onPressed: _busy
                                        ? null
                                        : () => _act(() => api.marketplace.acceptOffer(id)),
                                  ),
                                  IconButton(
                                    tooltip: 'Counter',
                                    icon: const Icon(Icons.swap_horiz),
                                    onPressed: _busy ? null : () => _counter(id),
                                  ),
                                  IconButton(
                                    tooltip: 'Decline',
                                    icon: const Icon(Icons.cancel_outlined),
                                    onPressed: _busy
                                        ? null
                                        : () => _act(() => api.marketplace.declineOffer(id)),
                                  ),
                                ],
                              )
                            : null,
                      );
                    },
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


/// The current user's offers: ones they received (on their listings) and ones
/// they made. Sellers accept/counter/decline; buyers accept a counter or
/// withdraw. Completes the offers flow begun on the listing detail screen.
class MyOffersScreen extends StatefulWidget {
  const MyOffersScreen({super.key});

  @override
  State<MyOffersScreen> createState() => _MyOffersScreenState();
}

class _MyOffersScreenState extends State<MyOffersScreen> {
  late Future<Map<String, dynamic>> _offers;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _offers = api.marketplace.myOffers();
  }

  void _reload() => setState(() => _offers = api.marketplace.myOffers());

  Future<void> _act(Future<void> Function() op) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await op();
      _reload();
      refreshMarketplaceOffersBadge();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _counter(String offerId) async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Counter offer'),
        content: TextField(
          controller: ctl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Your price'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Counter')),
        ],
      ),
    );
    if (ok != true) return;
    final amount = num.tryParse(ctl.text.trim());
    if (amount == null || amount <= 0) {
      if (mounted) showInfo(context, 'Enter a valid amount');
      return;
    }
    await _act(() => api.marketplace.counterOffer(offerId, amount));
  }

  String _money(Object? v) =>
      '\$${(num.tryParse('${v ?? 0}') ?? 0).toStringAsFixed(2)}';

  List<Map<String, dynamic>> _asList(Object? v) => v is List
      ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : const [];

  Widget _receivedTile(Map<String, dynamic> o) {
    final status = '${o['status'] ?? 'pending'}';
    final open = status == 'pending' || status == 'countered';
    final id = '${o['id']}';
    return ListTile(
      title: Text('${o['buyer_name'] ?? 'A buyer'} · ${_money(o['amount'])}'),
      subtitle: Text([
        '${o['listing_title'] ?? 'Listing'}',
        status,
        if (o['counter_amount'] != null) 'you countered ${_money(o['counter_amount'])}',
      ].join(' · ')),
      trailing: open
          ? Wrap(spacing: 4, children: [
              IconButton(
                  tooltip: 'Accept',
                  icon: const Icon(Icons.check_circle_outline),
                  onPressed: _busy ? null : () => _act(() => api.marketplace.acceptOffer(id))),
              IconButton(
                  tooltip: 'Counter',
                  icon: const Icon(Icons.swap_horiz),
                  onPressed: _busy ? null : () => _counter(id)),
              IconButton(
                  tooltip: 'Decline',
                  icon: const Icon(Icons.cancel_outlined),
                  onPressed: _busy ? null : () => _act(() => api.marketplace.declineOffer(id))),
            ])
          : null,
    );
  }

  Widget _madeTile(Map<String, dynamic> o) {
    final status = '${o['status'] ?? 'pending'}';
    final id = '${o['id']}';
    final countered = status == 'countered' && o['counter_amount'] != null;
    final open = status == 'pending' || status == 'countered';
    return ListTile(
      title: Text('${o['listing_title'] ?? 'Listing'} · ${_money(o['amount'])}'),
      subtitle: Text(countered
          ? 'Seller countered ${_money(o['counter_amount'])}'
          : status),
      trailing: Wrap(spacing: 4, children: [
        if (countered)
          IconButton(
              tooltip: 'Accept counter',
              icon: const Icon(Icons.check_circle_outline),
              onPressed: _busy ? null : () => _act(() => api.marketplace.acceptCounter(id))),
        if (open)
          IconButton(
              tooltip: 'Withdraw',
              icon: const Icon(Icons.undo),
              onPressed: _busy ? null : () => _act(() => api.marketplace.withdrawOffer(id))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My offers'),
          bottom: const TabBar(tabs: [Tab(text: 'Received'), Tab(text: 'Made')]),
        ),
        body: FutureBuilder<Map<String, dynamic>>(
          future: _offers,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('Couldn\'t load offers: ${snap.error}'));
            }
            final received = _asList(snap.data?['received']);
            final made = _asList(snap.data?['made']);
            return TabBarView(children: [
              _OfferList(items: received, empty: 'No offers received yet.', tile: _receivedTile),
              _OfferList(items: made, empty: "You haven't made any offers yet.", tile: _madeTile),
            ]);
          },
        ),
      ),
    );
  }
}

class _OfferList extends StatelessWidget {
  const _OfferList({required this.items, required this.empty, required this.tile});

  final List<Map<String, dynamic>> items;
  final String empty;
  final Widget Function(Map<String, dynamic>) tile;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(child: Text(empty));
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => tile(items[i]),
    );
  }
}


/// The current user's saved searches, each showing how many new listings match
/// since they last looked. Tapping one applies it (and clears the badge);
/// the trailing button deletes it.
class SavedSearchesScreen extends StatefulWidget {
  const SavedSearchesScreen({super.key});

  @override
  State<SavedSearchesScreen> createState() => _SavedSearchesScreenState();
}

class _SavedSearchesScreenState extends State<SavedSearchesScreen> {
  late Future<List<Map<String, dynamic>>> _searches;

  @override
  void initState() {
    super.initState();
    _searches = api.marketplace.savedSearches();
  }

  void _reload() => setState(() => _searches = api.marketplace.savedSearches());

  Future<void> _open(Map<String, dynamic> s) async {
    try {
      await api.marketplace.markSearchSeen('${s['id']}');
    } catch (_) {}
    if (mounted) Navigator.pop(context, s);
  }

  Future<void> _delete(Map<String, dynamic> s) async {
    try {
      await api.marketplace.deleteSavedSearch('${s['id']}');
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved searches')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _searches,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final searches = snap.data ?? const [];
          if (searches.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                    'No saved searches yet. Set filters or a query, then '
                    '"Save current search".',
                    textAlign: TextAlign.center),
              ),
            );
          }
          return ListView.separated(
            itemCount: searches.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final s = searches[i];
              final newCount =
                  num.tryParse('${s['new_count'] ?? 0}')?.toInt() ?? 0;
              return ListTile(
                title: Text('${s['name'] ?? 'Search'}'),
                subtitle: newCount > 0
                    ? Text('$newCount new since you last looked')
                    : null,
                leading: const Icon(Icons.search),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (newCount > 0)
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('$newCount',
                            style: const TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete',
                      onPressed: () => _delete(s),
                    ),
                  ],
                ),
                onTap: () => _open(s),
              );
            },
          );
        },
      ),
    );
  }
}


/// The current user's purchase history — listings they bought (verified sold
/// to them). Reuses the marketplace grid card.
class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  late Future<List<Listing>> _purchases;

  @override
  void initState() {
    super.initState();
    _purchases = api.marketplace.purchases();
  }

  Future<void> _reload() async {
    setState(() => _purchases = api.marketplace.purchases());
    await _purchases;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Purchases')),
      body: MaxWidth(
        maxWidth: 1000,
        child: RefreshIndicator(
          onRefresh: _reload,
          child: AsyncList<Listing>(
            future: _purchases,
            loading: const GridSkeleton(),
            emptyMessage: "You haven't bought anything yet.",
            emptyIcon: Icons.shopping_bag_outlined,
            builder: (context, items) => GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                childAspectRatio: 0.72,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) => _ListingCard(listing: items[i]),
            ),
          ),
        ),
      ),
    );
  }
}
