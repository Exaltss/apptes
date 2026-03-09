import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
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

  // Fungsi untuk berpindah tab secara aman dari halaman anak
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
    final List<Widget> pages = [
      BerandaTab(onNavigateToMap: navigateToMap),
      // Kita kirim fungsi _changeTab ke AduanScreen
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
          BottomNavigationBarItem(icon: Icon(Icons.campaign), label: 'Aduan'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Riwayat'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Peta'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }
}

// --- BAGIAN BERANDA TAB (DENGAN LOGIKA GPS SAAT MULAI) ---
class BerandaTab extends StatefulWidget {
  final Function(double, double) onNavigateToMap;
  const BerandaTab({super.key, required this.onNavigateToMap});
  @override
  State<BerandaTab> createState() => _BerandaTabState();
}

class _BerandaTabState extends State<BerandaTab> {
  PatrolStatus _status = PatrolStatus.idle;
  String _fullname = "Memuat...";
  String _pangkat = "";
  bool _isLoading = false;
  List<dynamic> _jadwalList = [];
  int _checkpointCount = 0;
  int _lastNotifId = 0;
  StreamSubscription<Position>? _positionStream;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (t) {
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

  Future<void> _loadUserData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _fullname = prefs.getString('nama_lengkap') ?? "Petugas";
        _pangkat = prefs.getString('pangkat') ?? "Anggota";
      });
    }
    _fetchSyncData();
  }

  Future<void> _fetchSyncData() async {
    final j = await ApiService().getJadwal();
    final r = await ApiService().getRingkasan();
    if (mounted) {
      setState(() {
        _jadwalList = j;
        _checkpointCount = r['checkpoint_count'] ?? 0;
      });
    }
  }

  Future<void> _checkInstructions() async {
    final latest = await ApiService().getLatestInstruction();
    if (latest != null && (latest['id'] ?? 0) > _lastNotifId) {
      _lastNotifId = latest['id'];
      _showNotif(latest['judul'], latest['isi'], latest['tipe']);
    }
  }

  void _showNotif(String title, String body, String type) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF222B36),
        title: Text(
          title,
          style: TextStyle(
            color: type == 'darurat' ? Colors.red : Colors.yellow,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(body, style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  // --- MODIFIKASI: LOGIKA GPS SAAT TEKAN MULAI ---
  Future<void> _handleMainTap() async {
    if (_status == PatrolStatus.idle) {
      // 1. Cek apakah GPS (Service Lokasi) di HP sudah aktif
      bool isLocationEnabled = await Geolocator.isLocationServiceEnabled();

      if (!isLocationEnabled) {
        // 2. Jika mati, tampilkan dialog notifikasi aktifkan GPS
        if (mounted) {
          _showGpsActivationDialog();
        }
        return;
      }

      // 3. Jika sudah aktif, cek izin (Permissions)
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      // 4. Lanjut Update Backend
      _updateBackend('patroli', PatrolStatus.patrolling);
    } else if (_status == PatrolStatus.patrolling) {
      _showStopDialog();
    } else {
      _updateBackend('patroli', PatrolStatus.patrolling);
    }
  }

  // Dialog Notifikasi Aktifkan GPS
  void _showGpsActivationDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF222B36),
        title: const Row(
          children: [
            Icon(Icons.location_off, color: Colors.red),
            SizedBox(width: 10),
            Text("GPS Tidak Aktif", style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          "Mohon aktifkan Lokasi (GPS) pada ponsel Anda untuk memulai patroli.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("BATAL", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.yellow),
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openLocationSettings(); // Membuka pengaturan GPS HP
            },
            child: const Text(
              "AKTIFKAN",
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
    setState(() => _isLoading = true);
    try {
      Position p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      bool ok = await ApiService().updatePatrolStatus(
        lat: p.latitude,
        long: p.longitude,
        status: bStat,
      );
      if (ok && mounted) {
        setState(() => _status = uiStat);
        if (uiStat != PatrolStatus.idle) {
          _positionStream?.cancel();
          _positionStream =
              Geolocator.getPositionStream(
                locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy.high,
                  distanceFilter: 10,
                ),
              ).listen((pos) {
                ApiService().updatePatrolStatus(
                  lat: pos.latitude,
                  long: pos.longitude,
                  status: _statusString(),
                );
              });
        } else {
          _positionStream?.cancel();
        }
      }
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _statusString() {
    if (_status == PatrolStatus.patrolling) return 'patroli';
    if (_status == PatrolStatus.standby) return 'bersiaga';
    if (_status == PatrolStatus.emergency) return 'darurat';
    return 'offline';
  }

  @override
  Widget build(BuildContext context) {
    bool active = _status != PatrolStatus.idle;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _fetchSyncData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20.0),
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
                        "Checkpoint\n($_checkpointCount)",
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
                        "Siaga",
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

  void _showStopDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Hentikan Patroli?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Batal"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _updateBackend('offline', PatrolStatus.idle);
            },
            child: const Text("YA", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderUI() {
    return Row(
      children: [
        const CircleAvatar(
          radius: 25,
          backgroundColor: Colors.yellow,
          child: Icon(Icons.person, color: Colors.black),
        ),
        const SizedBox(width: 15),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "WELCOME",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              "$_pangkat $_fullname",
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
        const Spacer(),
        Stack(
          children: [
            const Icon(Icons.notifications, color: Colors.grey, size: 30),
            if (_lastNotifId > 0)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(minWidth: 8, minHeight: 8),
                ),
              ),
          ],
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
            a ? "Sharelock Aktif" : "Offline",
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
    String t = "Mulai";
    if (_status == PatrolStatus.patrolling) {
      c = const Color(0xFF5DD35D);
      t = "Berhenti";
    } else if (_status == PatrolStatus.standby) {
      c = const Color(0xFFD48C56);
      t = "Lanjut";
    } else if (_status == PatrolStatus.emergency) {
      c = Colors.red;
      t = "Matikan";
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
          "SINYAL DARURAT",
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
          "Jadwal Patroli Saya",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconColor: Colors.white,
        collapsedIconColor: Colors.white,
        children: _jadwalList.isEmpty
            ? [
                const ListTile(
                  title: Text(
                    "Tidak ada jadwal",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ]
            : _jadwalList.map((j) {
                return ListTile(
                  onTap: () {
                    double? lat = double.tryParse(j['latitude'].toString());
                    double? lng = double.tryParse(j['longitude'].toString());
                    if (lat != null && lng != null && lat != 0.0) {
                      widget.onNavigateToMap(lat, lng);
                    }
                  },
                  leading: const Icon(
                    Icons.map_rounded,
                    color: Colors.yellow,
                    size: 24,
                  ),
                  title: Text(
                    j['lokasi_target'] ?? 'Lokasi Belum Diatur',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    "${j['tanggal']} | ${j['shift']}",
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

class _BouncingButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _BouncingButton({required this.child, required this.onTap});
  @override
  State<_BouncingButton> createState() => _BouncingButtonState();
}

class _BouncingButtonState extends State<_BouncingButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: Tween<double>(begin: 1.0, end: 0.95).animate(_controller),
        child: widget.child,
      ),
    );
  }
}
