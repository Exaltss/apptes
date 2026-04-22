import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

// ══════════════════════════════════════════════════════════════
//  Smooth-Tracking State — dead reckoning + lerp 60fps
// ══════════════════════════════════════════════════════════════
class _TrackState {
  double anchorLat, anchorLng;
  double speed;
  double heading;
  int anchorMs;
  double renderLat, renderLng;

  _TrackState({
    required this.anchorLat,
    required this.anchorLng,
    required this.speed,
    required this.heading,
  }) : renderLat = anchorLat,
       renderLng = anchorLng,
       anchorMs = DateTime.now().millisecondsSinceEpoch;

  void updateAnchor(double lat, double lng, double spd, double hdg) {
    final dist = _haversine(anchorLat, anchorLng, lat, lng);
    if (dist > 50) {
      renderLat = lat;
      renderLng = lng;
    }
    anchorLat = lat;
    anchorLng = lng;
    speed = spd;
    heading = hdg;
    anchorMs = DateTime.now().millisecondsSinceEpoch;
  }

  LatLng deadReckoning() {
    final elapsed = (DateTime.now().millisecondsSinceEpoch - anchorMs) / 1000.0;
    if (speed < 0.5 || elapsed <= 0 || elapsed > 4.0) {
      return LatLng(anchorLat, anchorLng);
    }
    const r = 6371000.0;
    final dist = speed * elapsed;
    final brRad = heading * math.pi / 180.0;
    final lat1 = anchorLat * math.pi / 180.0;
    final lng1 = anchorLng * math.pi / 180.0;
    final lat2 = math.asin(
      math.sin(lat1) * math.cos(dist / r) +
          math.cos(lat1) * math.sin(dist / r) * math.cos(brRad),
    );
    final lng2 =
        lng1 +
        math.atan2(
          math.sin(brRad) * math.sin(dist / r) * math.cos(lat1),
          math.cos(dist / r) - math.sin(lat1) * math.sin(lat2),
        );
    return LatLng(lat2 * 180 / math.pi, lng2 * 180 / math.pi);
  }

  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}

// ══════════════════════════════════════════════════════════════
//  MapScreen
// ══════════════════════════════════════════════════════════════
class MapScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  const MapScreen({super.key, this.initialLat, this.initialLng});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with SingleTickerProviderStateMixin {
  final _mapCtrl = MapController();
  final _sheetCtrl = DraggableScrollableController();

  LatLng _myLoc = const LatLng(-8.0667, 111.9000);

  List<dynamic> _others = [];
  List<Map<String, dynamic>> _missions = [];

  final Map<String, List<LatLng>> _trimmedRoutes = {};
  final Map<String, List<LatLng>> _fullRoutes = {};
  List<Polyline> _polylines = [];

  final Map<int, _TrackState> _tracks = {};
  final Map<int, LatLng> _renderPos = {};

  // dart:io WebSocket — tidak perlu package tambahan
  WebSocket? _ws;
  Timer? _wsReconnectTimer;
  Timer? _fallbackTimer;
  Timer? _missionTimer;
  late AnimationController _ticker;
  StreamSubscription<Position>? _posSub;

  bool _ready = false;
  bool _satellite = false;
  bool _panelExpanded = false;
  bool _wsConnected = false;

  // Ganti dengan URL WS backend kamu
  static const String wsUrl = 'wss://tulgungpatrol.my.id/ws/locations';
  static const double trimDist = 20.0;
  static const double arriveDist = 35.0;

  // ── Lifecycle ──────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _ticker =
        AnimationController(vsync: this, duration: const Duration(days: 365))
          ..addListener(_onTick)
          ..repeat();

    _init();

    _missionTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) _fetchMissions();
    });

    _posSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 1,
          ),
        ).listen((pos) {
          if (!mounted) return;
          setState(() => _myLoc = LatLng(pos.latitude, pos.longitude));
          _checkArrival();
        });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _wsReconnectTimer?.cancel();
    _fallbackTimer?.cancel();
    _missionTimer?.cancel();
    _ws?.close();
    _posSub?.cancel();
    _sheetCtrl.dispose();
    super.dispose();
  }

  // ── Init ───────────────────────────────────────────────────
  Future<void> _init() async {
    await _getMyLoc();
    await _fetchMissions();
    _connectWebSocket();
    if (widget.initialLat != null && widget.initialLng != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_ready) {
          _mapCtrl.move(LatLng(widget.initialLat!, widget.initialLng!), 15);
        }
      });
    }
  }

  Future<void> _getMyLoc() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 6));
      if (mounted) setState(() => _myLoc = LatLng(pos.latitude, pos.longitude));
    } catch (_) {}
  }

  // ── WebSocket (dart:io) ────────────────────────────────────
  Future<void> _connectWebSocket() async {
    _wsReconnectTimer?.cancel();
    try {
      _ws = await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 5));
      if (!mounted) {
        _ws?.close();
        return;
      }
      setState(() => _wsConnected = true);
      _fallbackTimer?.cancel();

      _ws!.listen(
        (raw) {
          if (!mounted) return;
          try {
            final msg = jsonDecode(raw as String) as Map<String, dynamic>;
            if (msg['type'] == 'location_update') {
              _applyLocationData(
                List<dynamic>.from(msg['data'] as List? ?? []),
              );
            } else if (msg['type'] == 'offline') {
              final id = msg['id'] as int?;
              if (id != null) _removePersonnel(id);
            }
          } catch (_) {}
        },
        onDone: _onWsDisconnected,
        onError: (_) => _onWsDisconnected(),
        cancelOnError: true,
      );
    } catch (_) {
      _onWsDisconnected();
    }
  }

  void _onWsDisconnected() {
    if (!mounted) return;
    setState(() => _wsConnected = false);
    _ws = null;

    _fallbackTimer?.cancel();
    _fallbackTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _fetchOthersFallback();
    });

    _wsReconnectTimer?.cancel();
    _wsReconnectTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) _connectWebSocket();
    });
  }

  Future<void> _fetchOthersFallback() async {
    try {
      final data = await ApiService().getAllPersonnelLocations();
      if (mounted) _applyLocationData(data);
    } catch (_) {}
  }

  void _applyLocationData(List<dynamic> data) {
    if (!mounted) return;
    for (final p in data) {
      final id = p['id'] as int;
      final lat = double.tryParse(p['latitude']?.toString() ?? '0') ?? 0;
      final lng = double.tryParse(p['longitude']?.toString() ?? '0') ?? 0;
      final spd = double.tryParse(p['speed']?.toString() ?? '0') ?? 0;
      final hdg = double.tryParse(p['heading']?.toString() ?? '0') ?? 0;
      if (lat == 0 && lng == 0) continue;

      if (!_tracks.containsKey(id)) {
        _tracks[id] = _TrackState(
          anchorLat: lat,
          anchorLng: lng,
          speed: spd,
          heading: hdg,
        );
        _renderPos[id] = LatLng(lat, lng);
      } else {
        _tracks[id]!.updateAnchor(lat, lng, spd, hdg);
      }
    }

    final activeIds = data.map((p) => p['id'] as int).toSet();
    for (final id in _tracks.keys.toList()) {
      if (!activeIds.contains(id)) _removePersonnel(id);
    }
    setState(() => _others = data);
  }

  void _removePersonnel(int id) {
    _tracks.remove(id);
    _renderPos.remove(id);
    _others.removeWhere((p) => p['id'] == id);
    if (mounted) setState(() {});
  }

  // ── 60 FPS lerp ───────────────────────────────────────────
  void _onTick() {
    if (!mounted) return;
    var changed = false;

    _tracks.forEach((id, tr) {
      final target = tr.deadReckoning();
      final cur = _renderPos[id] ?? LatLng(tr.anchorLat, tr.anchorLng);
      final t = tr.speed > 5 ? 0.30 : 0.20;
      final lat = cur.latitude + (target.latitude - cur.latitude) * t;
      final lng = cur.longitude + (target.longitude - cur.longitude) * t;
      final diff =
          (target.latitude - lat).abs() + (target.longitude - lng).abs();
      if (diff > 1e-8) {
        _renderPos[id] = LatLng(lat, lng);
        tr.renderLat = lat;
        tr.renderLng = lng;
        changed = true;
      }
    });

    if (changed) setState(() {});
  }

  // ── Misi & Rute ───────────────────────────────────────────
  Future<void> _fetchMissions() async {
    try {
      final jadwal = await ApiService().getJadwal();
      final inst = await ApiService().getLatestInstruction();
      final List<Map<String, dynamic>> temp = [];
      final activeKeys = <String>{};

      for (final j in jadwal) {
        final lat = double.tryParse(j['latitude']?.toString() ?? '');
        final lng = double.tryParse(j['longitude']?.toString() ?? '');
        if (lat == null || lng == null) continue;
        final key = 'j_${j['id']}';
        activeKeys.add(key);
        temp.add({
          'key': key,
          'lat': lat,
          'lng': lng,
          'judul': j['lokasi_target'] ?? 'Patroli',
          'color': const Color(0xFF5DD35D),
        });
        if (!_fullRoutes.containsKey(key)) _calcRoute(key, LatLng(lat, lng));
      }

      if (inst != null) {
        final lat = double.tryParse(inst['latitude']?.toString() ?? '');
        final lng = double.tryParse(inst['longitude']?.toString() ?? '');
        if (lat != null && lng != null) {
          final key = 'i_${inst['id']}';
          final isDarurat =
              inst['tipe'] == 'darurat' || inst['tipe_instruksi'] == 'darurat';
          activeKeys.add(key);
          temp.add({
            'key': key,
            'lat': lat,
            'lng': lng,
            'judul': inst['judul'] ?? 'Instruksi',
            'color': isDarurat ? Colors.red : Colors.blue,
          });
          if (!_fullRoutes.containsKey(key)) _calcRoute(key, LatLng(lat, lng));
        }
      }

      if (mounted) {
        setState(() {
          _missions = temp;
          _fullRoutes.removeWhere((k, _) => !activeKeys.contains(k));
          _trimmedRoutes.removeWhere((k, _) => !activeKeys.contains(k));
          _buildPolylines();
        });
      }
    } catch (_) {}
  }

  Future<void> _calcRoute(String key, LatLng target) async {
    try {
      final url =
          'https://router.project-osrm.org/route/v1/driving/'
          '${_myLoc.longitude},${_myLoc.latitude};'
          '${target.longitude},${target.latitude}'
          '?overview=full&geometries=geojson';
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final d = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = d['routes'] as List?;
      if (routes == null || routes.isEmpty) return;
      final ll = (routes[0]['geometry']['coordinates'] as List)
          .map((c) => LatLng(c[1] as double, c[0] as double))
          .toList();
      if (mounted) {
        setState(() {
          _fullRoutes[key] = ll;
          _trimmedRoutes[key] = List.from(ll);
          _buildPolylines();
        });
      }
    } catch (_) {}
  }

  void _checkArrival() {
    if (!mounted) return;
    final reached = <String>[];

    for (final m in _missions) {
      final key = m['key'] as String;
      final dist = Geolocator.distanceBetween(
        _myLoc.latitude,
        _myLoc.longitude,
        m['lat'] as double,
        m['lng'] as double,
      );

      if (dist < arriveDist) {
        reached.add(key);
        continue;
      }

      final pts = _trimmedRoutes[key];
      if (pts == null || pts.length < 2) continue;
      var trimmed = false;
      while (_trimmedRoutes[key]!.length > 2) {
        final first = _trimmedRoutes[key]!.first;
        final d = Geolocator.distanceBetween(
          _myLoc.latitude,
          _myLoc.longitude,
          first.latitude,
          first.longitude,
        );
        if (d <= trimDist) {
          _trimmedRoutes[key]!.removeAt(0);
          trimmed = true;
        } else {
          break;
        }
      }
      if (trimmed) setState(_buildPolylines);
    }

    if (reached.isNotEmpty) {
      setState(() {
        _missions.removeWhere((m) => reached.contains(m['key']));
        for (final k in reached) {
          _fullRoutes.remove(k);
          _trimmedRoutes.remove(k);
        }
        _buildPolylines();
      });
    }
  }

  void _buildPolylines() {
    _polylines = _missions
        .where((m) => _trimmedRoutes.containsKey(m['key']))
        .map(
          (m) => Polyline(
            points: _trimmedRoutes[m['key']]!,
            strokeWidth: 4,
            color: (m['color'] as Color).withValues(alpha: .80),
          ),
        )
        .toList();
  }

  // ── Helpers ───────────────────────────────────────────────
  Color _statusColor(String? s) {
    switch (s?.toLowerCase()) {
      case 'patroli':
        return Colors.blue;
      case 'bersiaga':
      case 'siaga':
        return Colors.yellow;
      case 'darurat':
        return Colors.red;
      default:
        return Colors.green;
    }
  }

  Future<void> _openWA(String noHp) async {
    if (noHp.isEmpty || noHp == '-') return;
    var fmt = noHp.replaceAll(RegExp(r'[\s\-]'), '');
    if (fmt.startsWith('0')) fmt = '62${fmt.substring(1)}';
    final waUri = Uri.parse('whatsapp://send?phone=$fmt');
    final webUri = Uri.parse('https://wa.me/$fmt');
    if (await canLaunchUrl(waUri)) {
      await launchUrl(waUri, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _personMarker(Color c, String? foto, String label) {
    String? url;
    if (foto != null && foto.isNotEmpty) {
      url = foto.startsWith('http')
          ? foto
          : 'https://tulgungpatrol.my.id/$foto';
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: c, width: 3),
            color: const Color(0xFF222B36),
            image: url != null
                ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover)
                : null,
          ),
          child: url == null ? Icon(Icons.person, color: c, size: 22) : null,
        ),
        Icon(Icons.arrow_drop_down, color: c, size: 14),
      ],
    );
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF151B25),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: _myLoc,
              initialZoom: 14,
              onMapReady: () => setState(() => _ready = true),
            ),
            children: [
              TileLayer(
                urlTemplate: _satellite
                    ? 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}'
                    : 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                userAgentPackageName: 'id.my.tulgungpatrol',
              ),
              CircleLayer(
                circles: _others.map((p) {
                  final id = p['id'] as int;
                  final pos = _renderPos[id];
                  if (pos == null) {
                    return CircleMarker(
                      point: const LatLng(0, 0),
                      radius: 0,
                      color: Colors.transparent,
                    );
                  }
                  final sc = _statusColor(p['status_aktif'] as String?);
                  return CircleMarker(
                    point: pos,
                    color: sc.withValues(alpha: .12),
                    borderColor: sc.withValues(alpha: .45),
                    borderStrokeWidth: 1.5,
                    useRadiusInMeter: true,
                    radius: p['status_aktif'] == 'darurat' ? 150 : 60,
                  );
                }).toList(),
              ),
              PolylineLayer(polylines: _polylines),
              MarkerLayer(
                markers: [
                  ..._missions.map(
                    (m) => Marker(
                      point: LatLng(m['lat'] as double, m['lng'] as double),
                      width: 70,
                      height: 72,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: m['color'] as Color,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              m['judul'].toString().split(' ').first,
                              style: const TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.flag_circle,
                            color: m['color'] as Color,
                            size: 32,
                          ),
                        ],
                      ),
                    ),
                  ),
                  ..._others.map((p) {
                    final id = p['id'] as int;
                    final pos = _renderPos[id];
                    if (pos == null) {
                      return const Marker(
                        point: LatLng(0, 0),
                        child: SizedBox(),
                      );
                    }
                    final short =
                        p['nama_lengkap']?.toString().split(' ').first ?? '...';
                    return Marker(
                      point: pos,
                      width: 65,
                      height: 85,
                      child: GestureDetector(
                        onTap: () => _showPersonDetail(p),
                        child: _personMarker(
                          _statusColor(p['status_aktif'] as String?),
                          p['foto_profil'] as String?,
                          short,
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ),

          Positioned(
            top: 50,
            left: 15,
            right: 15,
            child: _buildMissionHeader(),
          ),

          // Indikator LIVE / SYNC
          Positioned(
            top: 12,
            right: 15,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (_wsConnected ? Colors.green : Colors.orange).withValues(
                  alpha: .85,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _wsConnected ? Icons.wifi : Icons.wifi_off,
                    color: Colors.white,
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _wsConnected ? 'LIVE' : 'SYNC',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          Positioned(
            right: 15,
            bottom: 130,
            child: Column(
              children: [
                _mapBtn(
                  Icons.gps_fixed,
                  () => _mapCtrl.move(_myLoc, 16),
                  iconColor: Colors.yellow,
                ),
                const SizedBox(height: 6),
                _mapBtn(
                  Icons.add,
                  () => _mapCtrl.move(
                    _mapCtrl.camera.center,
                    _mapCtrl.camera.zoom + 1,
                  ),
                ),
                _mapBtn(
                  Icons.remove,
                  () => _mapCtrl.move(
                    _mapCtrl.camera.center,
                    _mapCtrl.camera.zoom - 1,
                  ),
                ),
                _mapBtn(
                  _satellite ? Icons.map : Icons.satellite_alt,
                  () => setState(() => _satellite = !_satellite),
                ),
              ],
            ),
          ),

          _buildBottomPanel(),
        ],
      ),
    );
  }

  // ── Sub-widgets ───────────────────────────────────────────
  Widget _buildMissionHeader() => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xFF222B36).withValues(alpha: .92),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'PENUGASAN AKTIF',
          style: TextStyle(
            color: Colors.yellow,
            fontWeight: FontWeight.bold,
            fontSize: 10,
          ),
        ),
        if (_missions.isEmpty)
          const Text(
            'Menunggu instruksi...',
            style: TextStyle(color: Colors.grey, fontSize: 11),
          )
        else
          ..._missions.map(
            (m) => Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: m['color'] as Color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      m['judul'].toString(),
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  Widget _buildBottomPanel() => DraggableScrollableSheet(
    controller: _sheetCtrl,
    initialChildSize: .12,
    minChildSize: .08,
    maxChildSize: .55,
    builder: (ctx, scroll) => Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: .5), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () {
              _panelExpanded = !_panelExpanded;
              _sheetCtrl.animateTo(
                _panelExpanded ? .5 : .12,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'REKAN AKTIF (${_others.length})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  Icon(
                    _panelExpanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_up,
                    color: Colors.blueAccent,
                  ),
                ],
              ),
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              padding: EdgeInsets.zero,
              itemCount: _others.length,
              itemBuilder: (_, i) {
                final p = _others[i];
                final sc = _statusColor(p['status_aktif'] as String?);
                final noHp = p['nrp']?.toString() ?? '';
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 2,
                  ),
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: sc.withValues(alpha: .2),
                    child: Icon(Icons.person, color: sc, size: 18),
                  ),
                  title: Text(
                    p['nama_lengkap']?.toString() ?? 'Petugas',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: noHp.isNotEmpty
                      ? GestureDetector(
                          onTap: () => _openWA(noHp),
                          child: Text(
                            '📱 $noHp',
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 11,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        )
                      : Text(
                          (p['pangkat'] ?? '-').toString(),
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 11,
                          ),
                        ),
                  onTap: () {
                    final pos = _renderPos[p['id'] as int];
                    if (pos != null) _mapCtrl.move(pos, 17);
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  Widget _mapBtn(
    IconData ic,
    VoidCallback fn, {
    Color iconColor = Colors.white,
  }) => GestureDetector(
    onTap: fn,
    child: Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF222B36),
        shape: BoxShape.circle,
      ),
      child: Icon(ic, color: iconColor, size: 22),
    ),
  );

  void _showPersonDetail(dynamic p) {
    final sc = _statusColor(p['status_aktif'] as String?);
    final noHp = p['nrp']?.toString() ?? '';
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF222B36),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(25, 25, 25, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: sc.withValues(alpha: .2),
                  child: Icon(Icons.person, color: sc, size: 32),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p['nama_lengkap']?.toString() ?? '-',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        p['pangkat']?.toString() ?? '-',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      if (p['satuan'] != null)
                        Text(
                          p['satuan'].toString(),
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: sc.withValues(alpha: .2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    (p['status_aktif'] ?? 'ONLINE').toString().toUpperCase(),
                    style: TextStyle(
                      color: sc,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white12),
            const SizedBox(height: 8),
            _infoRow(Icons.badge, 'NRP', p['nrp']?.toString() ?? '-'),
            _infoRow(Icons.phone, 'No. HP / WA', noHp.isNotEmpty ? noHp : '-'),
            _infoRow(
              Icons.speed,
              'Kecepatan',
              '${(double.tryParse(p['speed']?.toString() ?? '0') ?? 0).toStringAsFixed(1)} m/s',
            ),
            _infoRow(
              Icons.my_location,
              'Koordinat',
              '${double.tryParse(p['latitude']?.toString() ?? '0')?.toStringAsFixed(6)}, '
                  '${double.tryParse(p['longitude']?.toString() ?? '0')?.toStringAsFixed(6)}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Icon(icon, color: Colors.grey, size: 16),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}
