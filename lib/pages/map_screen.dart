import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';

class MapScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  const MapScreen({super.key, this.initialLat, this.initialLng});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();

  // STATE VARIABLES
  LatLng _myLocation = const LatLng(-8.0667, 111.9000);
  List<dynamic> _otherPersonnels = [];
  final Map<String, List<LatLng>> _missionRoutes = {};
  List<Map<String, dynamic>> _activeMissions = [];
  List<Polyline> _cachedPolylines = [];

  Timer? _refreshTimer;
  bool _isMapReady = false;
  bool _isSatelliteMode = false;
  bool _isFetching = false;

  @override
  void initState() {
    super.initState();
    _initData();

    // Refresh berkala setiap 10 detik
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (t) {
      if (mounted && !_isFetching) {
        _fetchAllData();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _initData() async {
    await _fetchAllData();
    if (widget.initialLat != null && widget.initialLng != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isMapReady) {
          _mapController.move(
            LatLng(widget.initialLat!, widget.initialLng!),
            15.0,
          );
        }
      });
    }
  }

  Future<void> _fetchAllData() async {
    if (_isFetching) {
      return;
    }
    _isFetching = true;

    try {
      await Future.wait([
        _getCurrentLocation(),
        _fetchOtherPersonnels(), // Fungsi ini sudah dikembalikan
        _fetchMissions(),
      ]);

      _checkIfTargetReached();
      _rebuildPolylineCache();
    } catch (e) {
      debugPrint("Global Fetch Error: $e");
    } finally {
      if (mounted) {
        setState(() => _isFetching = false);
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 4));

      if (mounted) {
        setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
      }
    } catch (e) {
      debugPrint("GPS Error: $e");
    }
  }

  // --- FUNGSI DIAMBILNYA LOKASI PERSONEL LAIN ---
  Future<void> _fetchOtherPersonnels() async {
    try {
      final data = await ApiService().getOtherLocations();
      if (mounted) {
        setState(() => _otherPersonnels = data);
      }
    } catch (e) {
      debugPrint("Fetch Personnels Error: $e");
    }
  }

  Future<void> _fetchMissions() async {
    try {
      final api = ApiService();
      final results = await Future.wait([
        api.getJadwal(),
        api.getLatestInstruction(),
      ]);

      final List<dynamic> jadwal = results[0] as List<dynamic>;
      final dynamic inst = results[1];

      List<Map<String, dynamic>> tempMissions = [];
      Set<String> activeKeys = {};

      for (var j in jadwal) {
        double? lat = double.tryParse(j['latitude']?.toString() ?? '');
        double? lng = double.tryParse(j['longitude']?.toString() ?? '');

        if (lat != null && lng != null) {
          String key = "jadwal_${j['id']}";
          activeKeys.add(key);
          tempMissions.add({
            'key': key,
            'lat': lat,
            'lng': lng,
            'judul': j['lokasi_target'] ?? 'Patroli',
            'color': const Color(0xFF5DD35D),
          });
          if (!_missionRoutes.containsKey(key)) {
            _calculateRoute(key, LatLng(lat, lng));
          }
        }
      }

      if (inst != null) {
        double? lat = double.tryParse(inst['latitude']?.toString() ?? '');
        double? lng = double.tryParse(inst['longitude']?.toString() ?? '');

        if (lat != null && lng != null) {
          String key = "instruksi_${inst['id']}";
          activeKeys.add(key);
          bool isDarurat =
              inst['tipe'] == 'darurat' || inst['tipe_instruksi'] == 'darurat';
          tempMissions.add({
            'key': key,
            'lat': lat,
            'lng': lng,
            'judul': inst['judul'] ?? 'Instruksi',
            'color': isDarurat ? Colors.red : Colors.blue,
          });
          if (!_missionRoutes.containsKey(key)) {
            _calculateRoute(key, LatLng(lat, lng));
          }
        }
      }

      if (mounted) {
        setState(() {
          _activeMissions = tempMissions;
          _missionRoutes.removeWhere((key, _) => !activeKeys.contains(key));
        });
      }
    } catch (e) {
      debugPrint("Mission Sync Error: $e");
    }
  }

  Future<void> _calculateRoute(String key, LatLng target) async {
    try {
      final url =
          'https://router.project-osrm.org/route/v1/driving/${_myLocation.longitude},${_myLocation.latitude};${target.longitude},${target.latitude}?overview=full&geometries=geojson';
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final List coords = data['routes'][0]['geometry']['coordinates'];
          if (mounted) {
            setState(() {
              _missionRoutes[key] = coords
                  .map((c) => LatLng(c[1], c[0]))
                  .toList();
              _rebuildPolylineCache();
            });
          }
        }
      }
    } catch (e) {
      debugPrint("OSRM Error: $e");
    }
  }

  void _checkIfTargetReached() {
    if (_activeMissions.isEmpty) {
      return;
    }
    List<String> reachedKeys = [];

    for (var m in _activeMissions) {
      double dist = Geolocator.distanceBetween(
        _myLocation.latitude,
        _myLocation.longitude,
        m['lat'],
        m['lng'],
      );
      if (dist < 30) {
        reachedKeys.add(m['key']);
      }
    }

    if (reachedKeys.isNotEmpty && mounted) {
      setState(() {
        _activeMissions.removeWhere((m) => reachedKeys.contains(m['key']));
        for (var k in reachedKeys) {
          _missionRoutes.remove(k);
        }
        _rebuildPolylineCache();
      });
    }
  }

  void _rebuildPolylineCache() {
    _cachedPolylines = _activeMissions
        .where((m) => _missionRoutes.containsKey(m['key']))
        .map(
          (m) => Polyline(
            points: _missionRoutes[m['key']]!,
            strokeWidth: 5.0,
            color: m['color'].withValues(alpha: 0.7),
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF151B25),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _myLocation,
              initialZoom: 14.0,
              onMapReady: () => setState(() => _isMapReady = true),
            ),
            children: [
              TileLayer(
                urlTemplate: _isSatelliteMode
                    ? 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}'
                    : 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                userAgentPackageName: 'com.trackdigital.polres.tulungagung',
              ),
              PolylineLayer(polylines: _cachedPolylines),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _myLocation,
                    width: 60,
                    height: 60,
                    child: _buildMarkerIcon(
                      Colors.blue,
                      Icons.person_pin,
                      "SAYA",
                    ),
                  ),
                  ..._activeMissions.map(
                    (m) => Marker(
                      point: LatLng(m['lat'], m['lng']),
                      width: 70,
                      height: 70,
                      child: _buildMarkerIcon(
                        m['color'],
                        Icons.flag_circle,
                        m['judul'].toString().split(' ')[0],
                      ),
                    ),
                  ),
                  ..._otherPersonnels.map((p) {
                    double lat =
                        double.tryParse(p['latitude']?.toString() ?? '0') ?? 0;
                    double lng =
                        double.tryParse(p['longitude']?.toString() ?? '0') ?? 0;
                    if (lat == 0) {
                      return const Marker(
                        point: LatLng(0, 0),
                        child: SizedBox(),
                      );
                    }
                    return Marker(
                      point: LatLng(lat, lng),
                      width: 60,
                      height: 60,
                      child: GestureDetector(
                        onTap: () => _showPersonDetail(p),
                        child: _buildMarkerIcon(
                          const Color(0xFF5DD35D),
                          Icons.shield,
                          p['nama_lengkap'].toString().split(' ')[0],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ),
          Positioned(top: 50, left: 15, right: 15, child: _buildHeaderInfo()),
          Positioned(
            right: 15,
            bottom: 40,
            child: Column(
              children: [
                _buildMapAction(Icons.gps_fixed, () {
                  if (_isMapReady) {
                    _mapController.move(_myLocation, 16.0);
                  }
                }, iconColor: Colors.yellow),
                const SizedBox(height: 8),
                _buildMapAction(Icons.add, () {
                  if (_isMapReady) {
                    _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom + 1,
                    );
                  }
                }),
                _buildMapAction(Icons.remove, () {
                  if (_isMapReady) {
                    _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom - 1,
                    );
                  }
                }),
                _buildMapAction(
                  _isSatelliteMode ? Icons.map : Icons.satellite_alt,
                  () => setState(() => _isSatelliteMode = !_isSatelliteMode),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF222B36).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "PENUGASAN AKTIF",
            style: TextStyle(
              color: Colors.yellow,
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
          if (_activeMissions.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                "Menunggu instruksi...",
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ),
          ..._activeMissions.map(
            (m) => Padding(
              padding: const EdgeInsets.only(top: 4),
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
                  const SizedBox(width: 8),
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
  }

  Widget _buildMarkerIcon(Color color, IconData icon, String label) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(5),
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
        Icon(icon, color: color, size: 30),
      ],
    );
  }

  Widget _buildMapAction(
    IconData icon,
    VoidCallback onTap, {
    Color iconColor = Colors.white,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        margin: const EdgeInsets.only(bottom: 5),
        decoration: const BoxDecoration(
          color: Color(0xFF222B36),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
    );
  }

  void _showPersonDetail(dynamic p) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF222B36),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        height: 150,
        child: ListTile(
          leading: const CircleAvatar(
            backgroundColor: Colors.yellow,
            child: Icon(Icons.person, color: Colors.black),
          ),
          title: Text(
            p['nama_lengkap'] ?? 'No Name',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            p['status_aktif'] ?? 'OFFLINE',
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      ),
    );
  }
}
