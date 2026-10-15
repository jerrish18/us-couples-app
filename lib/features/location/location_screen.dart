import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ui.dart';
import 'live_location.dart';

class LocationScreen extends ConsumerStatefulWidget {
  const LocationScreen({super.key});
  @override
  ConsumerState<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends ConsumerState<LocationScreen> {
  bool _map = false;
  final _controller = MapController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(locationProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Live location')),
      body: ListenableBuilder(
        listenable: live,
        builder: (context, _) {
          final rows = live.active;
          final point = rows.isEmpty
              ? null
              : LatLng(
                  (rows.first['latitude'] as num).toDouble(),
                  (rows.first['longitude'] as num).toDouble(),
                );
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Closer, wherever you are',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'Each person chooses when to share. Only your partner can see your position. Sharing stops at the selected time. No location history is saved.',
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        live.sharing
                            ? 'Your location is being shared'
                            : 'Your location is off',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (live.sharing)
                        Text(
                          'Until ${displayTime(live.until!.toIso8601String())} · stops automatically',
                        ),
                      const SizedBox(height: 12),
                      if (live.sharing)
                        FilledButton.icon(
                          onPressed: () => live.stop(),
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: const Text('Stop sharing now'),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final minutes in [15, 60, 480])
                              FilledButton.tonal(
                                onPressed: live.starting
                                    ? null
                                    : () => live.start(
                                        Duration(minutes: minutes),
                                      ),
                                child: Text(
                                  minutes == 15
                                      ? '15 min'
                                      : minutes == 60
                                      ? '1 hour'
                                      : '8 hours',
                                ),
                              ),
                          ],
                        ),
                      if (live.starting)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: LinearProgressIndicator(),
                        ),
                    ],
                  ),
                ),
              ),
              if (live.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(live.error!),
                ),
              const SizedBox(height: 16),
              if (rows.isEmpty)
                const EmptyCard(
                  'No one is sharing',
                  'Your partner’s location appears here after they choose to share.',
                  icon: Icons.location_off_outlined,
                ),
              for (final r in rows)
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Icon(
                      r['user_id'] == live.session.userId
                          ? Icons.my_location
                          : Icons.favorite_border,
                    ),
                    title: Text(
                      r['user_id'] == live.session.userId
                          ? 'You'
                          : 'Your person',
                    ),
                    subtitle: Text(
                      'Accuracy ±${(r['accuracy'] as num).round()} m\nUpdated ${DateTime.now().difference(DateTime.parse(r['updated_at'] as String)).inSeconds.clamp(0, 999999)} seconds ago${DateTime.now().difference(DateTime.parse(r['updated_at'] as String)).inSeconds > 30 ? ' · may be out of date' : ''}',
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      tooltip: 'Open in a maps app',
                      onPressed: () => launchUrl(
                        Uri.parse(
                          'geo:${r['latitude']},${r['longitude']}?q=${r['latitude']},${r['longitude']}',
                        ),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.open_in_new),
                    ),
                    onTap: () => setState(() => _map = true),
                  ),
                ),
              if (point != null && !_map)
                OutlinedButton.icon(
                  onPressed: () => setState(() => _map = true),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Show map · loads OpenStreetMap tiles'),
                ),
              if (point != null && _map) ...[
                const Text(
                  'Map tiles come from OpenStreetMap. GPS accuracy depends on your phone, permissions and surroundings.',
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: SizedBox(
                    height: 360,
                    child: FlutterMap(
                      mapController: _controller,
                      options: MapOptions(
                        initialCenter: point,
                        initialZoom: 15,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.jerrish18.us',
                        ),
                        CircleLayer(
                          circles: [
                            for (final r in rows)
                              CircleMarker(
                                point: LatLng(
                                  (r['latitude'] as num).toDouble(),
                                  (r['longitude'] as num).toDouble(),
                                ),
                                radius: (r['accuracy'] as num).toDouble(),
                                useRadiusInMeter: true,
                                color: Theme.of(context).colorScheme.primary
                                    .withValues(alpha: .13),
                                borderColor: Theme.of(context)
                                    .colorScheme
                                    .primary,
                                borderStrokeWidth: 1,
                              ),
                          ],
                        ),
                        MarkerLayer(
                          markers: [
                            for (final r in rows)
                              Marker(
                                point: LatLng(
                                  (r['latitude'] as num).toDouble(),
                                  (r['longitude'] as num).toDouble(),
                                ),
                                width: 48,
                                height: 48,
                                child: Icon(
                                  r['user_id'] == live.session.userId
                                      ? Icons.location_on
                                      : Icons.favorite,
                                  color: r['user_id'] == live.session.userId
                                      ? Colors.blue
                                      : Theme.of(context).colorScheme.primary,
                                  size: 34,
                                ),
                              ),
                          ],
                        ),
                        RichAttributionWidget(
                          attributions: [
                            TextSourceAttribution(
                              'OpenStreetMap contributors',
                              onTap: () => launchUrl(
                                Uri.parse(
                                  'https://www.openstreetmap.org/copyright',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              const Text(
                'For best accuracy, choose Precise location and keep Location enabled. Android may pause updates to save battery. A stale marker is never a guarantee of someone’s current position.',
              ),
            ],
          );
        },
      ),
    );
  }
}
