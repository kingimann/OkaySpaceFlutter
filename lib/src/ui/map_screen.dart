import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'marketplace_screen.dart';

/// An interactive map showing nearby marketplace listings (OpenStreetMap
/// tiles — no API key required).
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Default view (Toronto) until we have listings to frame.
  static const _fallback = LatLng(43.6532, -79.3832);

  final _controller = MapController();
  late Future<List<Listing>> _listings;

  @override
  void initState() {
    super.initState();
    _listings = api.marketplace.listings(
      lat: _fallback.latitude,
      lng: _fallback.longitude,
      radiusKm: 50,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Map')),
      body: FutureBuilder<List<Listing>>(
        future: _listings,
        builder: (context, snapshot) {
          final listings = (snapshot.data ?? const <Listing>[])
              .where((l) => l.latitude != null && l.longitude != null)
              .toList();
          final markers = [
            for (final l in listings)
              Marker(
                point: LatLng(l.latitude!, l.longitude!),
                width: 44,
                height: 44,
                child: GestureDetector(
                  onTap: () => _showListing(l),
                  child: Icon(Icons.location_on,
                      color: scheme.primary, size: 40),
                ),
              ),
          ];
          final center = markers.isNotEmpty
              ? LatLng(listings.first.latitude!, listings.first.longitude!)
              : _fallback;
          return Stack(
            children: [
              FlutterMap(
                mapController: _controller,
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 11,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'ca.okayspace.app',
                  ),
                  MarkerLayer(markers: markers),
                  const RichAttributionWidget(
                    attributions: [
                      TextSourceAttribution('© OpenStreetMap contributors'),
                    ],
                  ),
                ],
              ),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Positioned(
                  top: 12,
                  right: 12,
                  child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              Positioned(
                left: 12,
                bottom: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${markers.length} listings nearby',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showListing(Listing l) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: ListTile(
          leading: l.photos.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(l.photos.first,
                      width: 52, height: 52, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const SizedBox(width: 52, height: 52)))
              : const Icon(Icons.shopping_bag_outlined),
          title: Text(l.title),
          subtitle: Text('${l.currency} ${l.price.toStringAsFixed(2)}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.pop(context);
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ListingDetailScreen(listingId: l.id)));
          },
        ),
      ),
    );
  }
}
