import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

class MapScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  const MapScreen({super.key, this.initialLat, this.initialLng});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _mapCtrl = MapController();
  final _sheetCtrl = DraggableScrollableController();

  LatLng _myLoc = const LatLng(-8.0667, 111.9000);
  List<dynamic> _others = [];
  List<Map<String, dynamic>> _missions = [];
  final Map<String, List<LatLng>> _routes = {};
  List<Polyline> _polylines = [];

  Timer? _timer;
  bool _ready = false,
      _satellite = false,
      _fetching = false,
      _panelExpanded = false;
  StreamSubscription<Position>? _posSub;

  @override
  void initState() {
    super.initState();
    _init();
    // Realtime 1 detik tanpa delay
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_fetching) _fetchOthers();
    });
    // Posisi saya realtime
    _posSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 1,
          ),
        ).listen((pos) {
          if (mounted)
            setState(() => _myLoc = LatLng(pos.latitude, pos.longitude));
        });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _posSub?.cancel();
    _sheetCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _getMyLoc();
    await _fetchOthers();
    await _fetchMissions();
    if (widget.initialLat != null && widget.initialLng != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_ready)
          _mapCtrl.move(LatLng(widget.initialLat!, widget.initialLng!), 15);
      });
    }
  }

  Future<void> _getMyLoc() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 8));
      if (mounted) setState(() => _myLoc = LatLng(pos.latitude, pos.longitude));
    } catch (_) {}
  }

  Future<void> _fetchOthers() async {
    _fetching = true;
    try {
      final data = await ApiService().getAllPersonnelLocations();
      if (mounted) setState(() => _others = data);
    } catch (_) {}
    _fetching = false;
  }

  Future<void> _fetchMissions() async {
    try {
      final jadwal = await ApiService().getJadwal();
      final inst = await ApiService().getLatestInstruction();
      final List<Map<String, dynamic>> temp = [];
      final Set<String> activeKeys = {};

      for (var j in jadwal) {
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
        if (!_routes.containsKey(key)) _calcRoute(key, LatLng(lat, lng));
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
          if (!_routes.containsKey(key)) _calcRoute(key, LatLng(lat, lng));
        }
      }

      if (mounted) {
        setState(() {
          _missions = temp;
          _routes.removeWhere((k, _) => !activeKeys.contains(k));
          _buildPolylines();
        });
      }
    } catch (_) {}
  }

  Future<void> _calcRoute(String key, LatLng target) async {
    try {
      final url =
          'https://router.project-osrm.org/route/v1/driving/${_myLoc.longitude},${_myLoc.latitude};${target.longitude},${target.latitude}?overview=full&geometries=geojson';
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return;
      final d = jsonDecode(res.body);
      if (d['routes'] == null || (d['routes'] as List).isEmpty) return;
      final coords = d['routes'][0]['geometry']['coordinates'] as List;
      if (mounted) {
        setState(() {
          _routes[key] = coords.map((c) => LatLng(c[1], c[0])).toList();
          _buildPolylines();
        });
      }
    } catch (_) {}
  }

  void _buildPolylines() {
    _polylines = _missions
        .where((m) => _routes.containsKey(m['key']))
        .map(
          (m) => Polyline(
            points: _routes[m['key']]!,
            strokeWidth: 4,
            color: (m['color'] as Color).withValues(alpha: .7),
          ),
        )
        .toList();
  }

  void _checkArrival() {
    final reached = _missions
        .where((m) {
          final dist = Geolocator.distanceBetween(
            _myLoc.latitude,
            _myLoc.longitude,
            m['lat'],
            m['lng'],
          );
          return dist < 35;
        })
        .map((m) => m['key'])
        .toList();

    if (reached.isNotEmpty && mounted) {
      setState(() {
        _missions.removeWhere((m) => reached.contains(m['key']));
        for (var k in reached) _routes.remove(k);
        _buildPolylines();
      });
    }
  }

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

  void _openWA(String noHp) async {
    final uri = Uri.parse('https://wa.me/$noHp');
    if (await canLaunchUrl(uri))
      await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _personMarker(Color c, String? foto, String label) {
    String? url;
    if (foto != null && foto.isNotEmpty) {
      url = foto.startsWith('http')
          ? foto
          : 'https://tulgungpatrol.my.id/$foto';
    }
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
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

  @override
  Widget build(BuildContext context) {
    _checkArrival();
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
              ),
              CircleLayer(
                circles: _others.map((p) {
                  final lat =
                      double.tryParse(p['latitude']?.toString() ?? '0') ?? 0;
                  final lng =
                      double.tryParse(p['longitude']?.toString() ?? '0') ?? 0;
                  return CircleMarker(
                    point: LatLng(lat, lng),
                    color: _statusColor(
                      p['status_aktif'],
                    ).withValues(alpha: .15),
                    borderColor: _statusColor(
                      p['status_aktif'],
                    ).withValues(alpha: .4),
                    borderStrokeWidth: 1.5,
                    useRadiusInMeter: true,
                    radius: p['status_aktif'] == 'darurat' ? 150 : 60,
                  );
                }).toList(),
              ),
              PolylineLayer(polylines: _polylines),
              MarkerLayer(
                markers: [
                  // Marker saya
                  Marker(
                    point: _myLoc,
                    width: 60,
                    height: 80,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.yellow[700],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'SAYA',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Icon(
                          Icons.person_pin,
                          color: Colors.yellow,
                          size: 36,
                        ),
                      ],
                    ),
                  ),
                  // Misi / target
                  ..._missions.map(
                    (m) => Marker(
                      point: LatLng(m['lat'], m['lng']),
                      width: 70,
                      height: 70,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: m['color'],
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
                          Icon(Icons.flag_circle, color: m['color'], size: 32),
                        ],
                      ),
                    ),
                  ),
                  // Rekan personel
                  ..._others.map((p) {
                    final lat =
                        double.tryParse(p['latitude']?.toString() ?? '0') ?? 0;
                    final lng =
                        double.tryParse(p['longitude']?.toString() ?? '0') ?? 0;
                    if (lat == 0)
                      return const Marker(
                        point: LatLng(0, 0),
                        child: SizedBox(),
                      );
                    final shortName =
                        p['nama_lengkap']?.toString().split(' ').first ?? '...';
                    return Marker(
                      point: LatLng(lat, lng),
                      width: 65,
                      height: 85,
                      child: GestureDetector(
                        onTap: () => _showPersonDetail(p),
                        child: _personMarker(
                          _statusColor(p['status_aktif']),
                          p['foto_profil'],
                          shortName,
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ),

          // Header misi
          Positioned(
            top: 50,
            left: 15,
            right: 15,
            child: _buildMissionHeader(),
          ),

          // Kontrol kanan
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

          // Panel bawah
          _buildBottomPanel(),
        ],
      ),
    );
  }

  Widget _buildMissionHeader() => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xFF222B36).withValues(alpha: .9),
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
                      color: m['color'],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      m['judul'],
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
            child: Container(
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
                final sc = _statusColor(p['status_aktif']);
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
                    p['nama_lengkap'] ?? 'Petugas',
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
                            '📞 $noHp',
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 11,
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
                    final lat = double.tryParse(
                      p['latitude']?.toString() ?? '',
                    );
                    final lng = double.tryParse(
                      p['longitude']?.toString() ?? '',
                    );
                    if (lat != null && lng != null)
                      _mapCtrl.move(LatLng(lat, lng), 17);
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
    final sc = _statusColor(p['status_aktif']);
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
                        p['nama_lengkap'] ?? '-',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        p['pangkat'] ?? '-',
                        style: const TextStyle(color: Colors.grey),
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
            if (noHp.isNotEmpty) ...[
              const SizedBox(height: 15),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => _openWA(noHp),
                  icon: const Icon(Icons.chat, color: Colors.white),
                  label: Text(
                    'WhatsApp: $noHp',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
