import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import '../services/background_service.dart';
import 'aduan_screen.dart';
import 'checkpoint_screen.dart';
import 'history_screen.dart';
import 'map_screen.dart';
import 'profile_screen.dart';

enum PatrolStatus { idle, patrolling, standby, emergency }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  double? targetLat;
  double? targetLng;

  void _changeTab(int index) {
    setState(() {
      _currentIndex = index;
      if (index != 3) {
        targetLat = null;
        targetLng = null;
      }
    });
  }

  void navigateToMap(double lat, double lng) {
    setState(() {
      targetLat = lat;
      targetLng = lng;
      _currentIndex = 3;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      BerandaTab(onNavigateToMap: navigateToMap),
      AduanScreen(onSuccess: () => _changeTab(0)),
      const HistoryScreen(),
      MapScreen(initialLat: targetLat, initialLng: targetLng),
      const ProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF151B25),
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _changeTab,
        backgroundColor: const Color(0xFF222B36),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFFFFC107),
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_filled),
            label: 'Beranda',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.campaign), label: 'Laporan'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Riwayat'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Peta'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
class BerandaTab extends StatefulWidget {
  final Function(double, double) onNavigateToMap;
  const BerandaTab({super.key, required this.onNavigateToMap});
  @override
  State<BerandaTab> createState() => _BerandaTabState();
}

class _BerandaTabState extends State<BerandaTab> {
  PatrolStatus _status = PatrolStatus.idle;
  String _fullname = 'Memuat...';
  String _pangkat = '';
  String? _fotoUrl;
  bool _isLoading = false;
  List<dynamic> _jadwalList = [];
  int _checkpointCount = 0;
  bool _isUpdating = false;

  final List<Map<String, dynamic>> _notifications = [];
  int _lastNotifId = 0;

  StreamSubscription<Position>? _positionStream;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _setInitialOffline();
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        _fetchSyncData();
        _checkInstructions();
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _positionStream?.cancel();
    super.dispose();
  }

  Future<void> _setInitialOffline() async {
    await ApiService().updatePatrolStatus(lat: 0, long: 0, status: 'offline');
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _fullname = prefs.getString('nama_lengkap') ?? 'Petugas';
        _pangkat = prefs.getString('pangkat') ?? 'Anggota';
        final saved = prefs.getString('foto_profil');
        _fotoUrl = (saved != null && !saved.contains('10.0.2.2'))
            ? saved
            : null;
      });
    }
    _fetchSyncData();
  }

  Future<void> _fetchSyncData() async {
    try {
      final j = await ApiService().getJadwal();
      final r = await ApiService().getRingkasan();
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('foto_profil');
      if (mounted) {
        setState(() {
          _jadwalList = j;
          _checkpointCount = r['checkpoint_count'] ?? 0;
          _fotoUrl = (saved != null && !saved.contains('10.0.2.2'))
              ? saved
              : null;
        });
      }
    } catch (e) {
      debugPrint('Refresh error: $e');
    }
  }

  Future<void> _checkInstructions() async {
    final latest = await ApiService().getLatestInstruction();
    if (latest == null || (latest['id'] ?? 0) <= _lastNotifId) return;
    setState(() {
      _lastNotifId = latest['id'];
      _notifications.insert(0, latest);
    });
    if (latest['tipe'] == 'darurat' || latest['tipe_instruksi'] == 'darurat') {
      _showEmergencyPriorityDialog(latest);
    }
  }

  void _showEmergencyPriorityDialog(Map<String, dynamic> data) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF8B0000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white, width: 2),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_rounded, color: Colors.white, size: 30),
            SizedBox(width: 10),
            Text(
              'PERINTAH DARURAT',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data['judul'] ?? 'Prioritas Tinggi',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              data['isi'] ?? '-',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.red,
            ),
            onPressed: () {
              Navigator.pop(context);
              if (data['latitude'] != null) {
                widget.onNavigateToMap(
                  double.parse(data['latitude'].toString()),
                  double.parse(data['longitude'].toString()),
                );
              }
            },
            child: const Text(
              'LIHAT LOKASI',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showNotificationHistory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1F2937),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              'INSTRUKSI MASUK',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const Divider(color: Colors.white12),
            Expanded(
              child: _notifications.isEmpty
                  ? const Center(
                      child: Text(
                        'Belum ada instruksi',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _notifications.length,
                      itemBuilder: (_, i) {
                        final item = _notifications[i];
                        return ListTile(
                          leading: Icon(
                            Icons.info_outline,
                            color: item['tipe'] == 'darurat'
                                ? Colors.red
                                : Colors.yellow,
                          ),
                          title: Text(
                            item['judul'] ?? '-',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            item['isi'] ?? '-',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            if (item['latitude'] != null) {
                              widget.onNavigateToMap(
                                double.parse(item['latitude'].toString()),
                                double.parse(item['longitude'].toString()),
                              );
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleMainTap() async {
    if (_status == PatrolStatus.idle) {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (mounted) _showGpsActivationDialog();
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) return;
      }
      _updateBackend('patroli', PatrolStatus.patrolling);
    } else if (_status == PatrolStatus.patrolling) {
      _showStopDialog();
    } else {
      _updateBackend('patroli', PatrolStatus.patrolling);
    }
  }

  void _showGpsActivationDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF222B36),
        title: const Text(
          'GPS Tidak Aktif',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Layanan Lokasi (GPS) diperlukan untuk memulai patroli.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('BATAL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.yellow),
            onPressed: () {
              Navigator.pop(context);
              Geolocator.openLocationSettings();
            },
            child: const Text(
              'AKTIFKAN',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateBackend(String bStat, PatrolStatus uiStat) async {
    // Cegah double-tap / double-request
    if (_isUpdating) return;
    _isUpdating = true;
    setState(() => _isLoading = true);

    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (mounted) _showGpsActivationDialog();
        return;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Izin GPS ditolak permanen. Buka Pengaturan.'),
              backgroundColor: Colors.red,
            ),
          );
          await Geolocator.openAppSettings();
        }
        return;
      }

      // Ambil posisi — 3 kali percobaan agar tidak gagal di jaringan lambat
      Position? p;
      for (int attempt = 0; attempt < 3 && p == null; attempt++) {
        try {
          p = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          ).timeout(const Duration(seconds: 8));
        } catch (_) {
          if (attempt == 2) p = await Geolocator.getLastKnownPosition();
        }
      }

      final lat = p?.latitude ?? -8.0667;
      final lng = p?.longitude ?? 111.9000;
      final spd = (p?.speed ?? 0) < 0 ? 0.0 : (p?.speed ?? 0);
      final hdg = (p?.heading ?? 0) < 0 ? 0.0 : (p?.heading ?? 0);

      // Retry API hingga 3 kali
      bool ok = false;
      for (int i = 0; i < 3 && !ok; i++) {
        ok = await ApiService().updatePatrolStatus(
          lat: lat,
          long: lng,
          status: bStat,
          speed: spd,
          heading: hdg,
        );
        if (!ok) await Future.delayed(const Duration(milliseconds: 500));
      }

      if (!mounted) return;

      if (ok) {
        setState(() => _status = uiStat);

        if (uiStat != PatrolStatus.idle) {
          await startBackgroundService(bStat);

          // Batalkan stream lama sebelum buat yang baru
          await _positionStream?.cancel();
          _positionStream = null;

          // Time-based stream setiap 2 detik
          _positionStream = Stream.periodic(const Duration(seconds: 2))
              .asyncMap((_) async {
                try {
                  return await Geolocator.getCurrentPosition(
                    locationSettings: const LocationSettings(
                      accuracy: LocationAccuracy.bestForNavigation,
                    ),
                  ).timeout(const Duration(seconds: 4));
                } catch (_) {
                  return await Geolocator.getLastKnownPosition();
                }
              })
              .where((pos) => pos != null)
              .cast<Position>()
              .listen((pos) {
                final s = pos.speed < 0 ? 0.0 : pos.speed;
                final h = pos.heading < 0 ? 0.0 : pos.heading;
                ApiService().updatePatrolStatus(
                  lat: pos.latitude,
                  long: pos.longitude,
                  status: _statusString(),
                  speed: s,
                  heading: h,
                );
                updateBackgroundStatus(_statusString());
              });
        } else {
          await _positionStream?.cancel();
          _positionStream = null;
          await stopBackgroundService();
          // Kirim offline sekali lagi untuk memastikan backend tahu
          ApiService().updatePatrolStatus(
            lat: lat,
            long: lng,
            status: 'offline',
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Gagal update status. Cek koneksi internet.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('_updateBackend error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      _isUpdating = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _statusString() {
    switch (_status) {
      case PatrolStatus.patrolling:
        return 'patroli';
      case PatrolStatus.standby:
        return 'bersiaga';
      case PatrolStatus.emergency:
        return 'darurat';
      default:
        return 'offline';
    }
  }

  void _showStopDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hentikan Patroli?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _updateBackend('offline', PatrolStatus.idle);
            },
            child: const Text('YA', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _status != PatrolStatus.idle;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _fetchSyncData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _buildHeaderUI(),
              const SizedBox(height: 20),
              _buildTrackingIndicator(active),
              const SizedBox(height: 30),
              _BouncingButton(
                onTap: _isLoading ? () {} : _handleMainTap,
                child: _isLoading ? _buildLoader() : _buildMainBtn(),
              ),
              const SizedBox(height: 30),
              Row(
                children: [
                  Expanded(
                    child: _BouncingButton(
                      onTap: active
                          ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const CheckpointScreen(),
                              ),
                            ).then((_) => _fetchSyncData())
                          : () {},
                      child: _buildMenu(
                        active ? const Color(0xFF5DD35D) : Colors.grey,
                        Icons.visibility,
                        'Checkpoint\n($_checkpointCount)',
                      ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: _BouncingButton(
                      onTap: active
                          ? () =>
                                _updateBackend('bersiaga', PatrolStatus.standby)
                          : () {},
                      child: _buildMenu(
                        active ? const Color(0xFFD48C56) : Colors.grey,
                        Icons.local_cafe,
                        'Siaga',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              _BouncingButton(
                onTap: active
                    ? () => _updateBackend('darurat', PatrolStatus.emergency)
                    : () {},
                child: _buildEmergency(active),
              ),
              const SizedBox(height: 25),
              _buildSchedules(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderUI() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.yellow.withValues(alpha: .5),
              width: 2,
            ),
          ),
          child: CircleAvatar(
            radius: 25,
            backgroundColor: const Color(0xFF222B36),
            key: ValueKey(_fotoUrl),
            backgroundImage: _fotoUrl != null ? NetworkImage(_fotoUrl!) : null,
            child: _fotoUrl == null
                ? const Icon(Icons.person, color: Colors.yellow)
                : null,
          ),
        ),
        const SizedBox(width: 15),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'WELCOME',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '$_pangkat $_fullname',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
        const Spacer(),
        GestureDetector(
          onTap: _showNotificationHistory,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications, color: Colors.grey, size: 30),
              if (_notifications.isNotEmpty)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      _notifications.length.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTrackingIndicator(bool a) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2C3542),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.location_on, color: a ? Colors.blue : Colors.grey),
          const SizedBox(width: 10),
          Text(
            a ? 'Terdeteksi di Peta (Online)' : 'Tidak Terdeteksi (Offline)',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoader() {
    return Container(
      width: double.infinity,
      height: 140,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.elliptical(300, 180)),
        border: Border.all(color: Colors.grey, width: 3),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }

  Widget _buildMainBtn() {
    Color c = const Color(0xFFFFC107);
    String t = 'Mulai';
    if (_status == PatrolStatus.patrolling) {
      c = const Color(0xFF5DD35D);
      t = 'Selesai';
    } else if (_status == PatrolStatus.standby) {
      c = const Color(0xFFD48C56);
      t = 'Lanjut';
    } else if (_status == PatrolStatus.emergency) {
      c = Colors.red;
      t = 'Matikan';
    }
    return Container(
      width: double.infinity,
      height: 140,
      decoration: BoxDecoration(
        color: const Color(0xFF151B25),
        borderRadius: const BorderRadius.all(Radius.elliptical(300, 180)),
        border: Border.all(color: c, width: 4),
      ),
      child: Center(
        child: Text(
          t,
          style: TextStyle(
            color: c,
            fontSize: 28,
            fontWeight: FontWeight.bold,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }

  Widget _buildMenu(Color c, IconData i, String l) {
    return Container(
      height: 100,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Icon(i, color: Colors.white, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmergency(bool a) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: a ? Colors.red : Colors.grey,
        borderRadius: BorderRadius.circular(15),
      ),
      child: const Center(
        child: Text(
          'SINYAL DARURAT',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
    );
  }

  Widget _buildSchedules() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2C3542),
        borderRadius: BorderRadius.circular(15),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: const Text(
          'Jadwal Patroli Saya',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconColor: Colors.white,
        collapsedIconColor: Colors.white,
        children: _jadwalList.isEmpty
            ? [
                const ListTile(
                  title: Text(
                    'Tidak ada jadwal',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ]
            : _jadwalList.map((j) {
                return ListTile(
                  onTap: () {
                    final lat = double.tryParse(j['latitude'].toString());
                    final lng = double.tryParse(j['longitude'].toString());
                    if (lat != null && lng != null && lat != 0.0) {
                      widget.onNavigateToMap(lat, lng);
                    }
                  },
                  leading: const Icon(Icons.map_rounded, color: Colors.yellow),
                  title: Text(
                    j['lokasi_target'] ?? 'Lokasi Belum Diatur',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    '${j['tanggal']} | ${j['shift']}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.grey,
                    size: 16,
                  ),
                );
              }).toList(),
      ),
    );
  }
}

// ── Bouncing Button ──────────────────────────────────────────────
class _BouncingButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _BouncingButton({required this.child, required this.onTap});
  @override
  State<_BouncingButton> createState() => _BouncingButtonState();
}

class _BouncingButtonState extends State<_BouncingButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: Tween<double>(begin: 1.0, end: 0.95).animate(_ctrl),
        child: widget.child,
      ),
    );
  }
}
