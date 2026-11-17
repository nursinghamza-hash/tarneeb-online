import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';
import 'table_screen.dart';

const Color kInk = Color(0xFF071A18);
const Color kFelt = Color(0xFF0D4938);
const Color kGold = Color(0xFFE2BD68);
const Color kPanel = Color(0xFF12372F);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _server = TextEditingController();
  int _target = 41;
  bool _busy = false;
  String _serverUrl = const String.fromEnvironment(
    'SERVER_URL',
    defaultValue: 'https://YOUR-TARNEEB-SERVER.onrender.com',
  );

  @override
  void initState() { super.initState(); _loadSettings(); }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _name.text = prefs.getString('player_name') ?? '';
    _serverUrl = prefs.getString('server_url') ?? _serverUrl;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _name.dispose(); _code.dispose(); _server.dispose(); super.dispose();
  }

  Future<void> _saveName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('player_name', _name.text.trim());
    await prefs.setString('server_url', _serverUrl.trim());
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _openServerSettings() async {
    _server.text = _serverUrl;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: kPanel,
          title: const Text('إعداد الاتصال', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: _server, keyboardType: TextInputType.url,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'رابط خادم اللعبة',
              hintText: 'https://your-server.onrender.com',
              labelStyle: TextStyle(color: kGold),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, _server.text.trim()), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (result != null && result.isNotEmpty) {
      setState(() => _serverUrl = result);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_url', result);
    }
  }

  bool _validate() {
    if (_name.text.trim().isEmpty) { _toast('اكتب اسمك أولاً'); return false; }
    if (!_serverUrl.startsWith('http://') && !_serverUrl.startsWith('https://')) {
      _toast('أدخل رابط الخادم بشكل صحيح من إعدادات الاتصال'); return false;
    }
    if (_serverUrl.contains('YOUR-TARNEEB-SERVER')) {
      _toast('يجب نشر خادم اللعبة وإدخال رابطه أولاً. راجع ملف README المرفق'); return false;
    }
    return true;
  }

  IO.Socket _newSocket() => IO.io(
    _serverUrl.trim(),
    IO.OptionBuilder().setTransports(['websocket']).disableAutoConnect()
      .enableReconnection().setReconnectionAttempts(999)
      .setReconnectionDelay(1000).build(),
  );

  Future<void> _createRoom() async {
    if (_busy || !_validate()) return;
    setState(() => _busy = true);
    await _saveName();
    final socket = _newSocket();
    bool opened = false, sent = false;
    socket.onConnect((_) {
      if (sent) return;
      sent = true;
      socket.emit('create_room', {'playerName': _name.text.trim(), 'targetScore': _target});
    });
    socket.on('room_created', (dynamic data) async {
      if (opened || !mounted) return;
      opened = true;
      final map = Map<String, dynamic>.from(data as Map);
      final code = map['roomCode'].toString(), token = map['token'].toString();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_room', code);
      await prefs.setString('room_token_$code', token);
      if (!mounted) return;
      setState(() => _busy = false);
      Navigator.push(context, MaterialPageRoute(builder: (_) => TableScreen(
        socket: socket, roomCode: code, playerName: _name.text.trim(), token: token, mySeat: 0,
      )));
    });
    socket.on('room_error', (dynamic message) {
      _toast(message.toString());
      if (mounted) setState(() => _busy = false);
      socket.disconnect();
    });
    socket.onConnectError((_) {
      _toast('تعذر الاتصال بالخادم. تأكد من الرابط وأن الخادم يعمل');
      if (mounted) setState(() => _busy = false);
    });
    socket.connect();
  }

  Future<void> _joinRoom() async {
    if (_busy || !_validate()) return;
    if (_code.text.trim().isEmpty) { _toast('أدخل رقم الطاولة'); return; }
    setState(() => _busy = true);
    await _saveName();
    final code = _code.text.trim().toUpperCase();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('room_token_$code') ?? '';
    final socket = _newSocket();
    bool opened = false, sent = false;
    socket.onConnect((_) {
      if (sent) return;
      sent = true;
      socket.emit('join_room', {
        'roomCode': code, 'playerName': _name.text.trim(), 'token': token,
      });
    });
    socket.on('room_joined', (dynamic data) async {
      if (opened || !mounted) return;
      opened = true;
      final map = Map<String, dynamic>.from(data as Map);
      final returnedToken = map['token'].toString();
      final seat = (map['seat'] as num).toInt();
      await prefs.setString('last_room', code);
      await prefs.setString('room_token_$code', returnedToken);
      if (!mounted) return;
      setState(() => _busy = false);
      Navigator.push(context, MaterialPageRoute(builder: (_) => TableScreen(
        socket: socket, roomCode: code, playerName: _name.text.trim(),
        token: returnedToken, mySeat: seat,
      )));
    });
    socket.on('room_error', (dynamic message) {
      _toast(message.toString());
      if (mounted) setState(() => _busy = false);
      socket.disconnect();
    });
    socket.onConnectError((_) {
      _toast('تعذر الاتصال بالخادم. افحص رابط الخادم');
      if (mounted) setState(() => _busy = false);
    });
    socket.connect();
  }

  Future<void> _showJoinDialog() async {
    _code.clear();
    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: kPanel,
          title: const Text('الانضمام إلى طاولة', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: _code, textCapitalization: TextCapitalization.characters,
            style: const TextStyle(color: Colors.white, fontSize: 20, letterSpacing: 2),
            decoration: const InputDecoration(
              hintText: 'TR-12345', labelText: 'رقم الطاولة',
              labelStyle: TextStyle(color: kGold),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(onPressed: () { Navigator.pop(ctx); _joinRoom(); }, child: const Text('دخول')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: kInk,
      body: SafeArea(
        child: Stack(children: [
          Positioned(top: -80, left: -50, child: _glow(220)),
          Positioned(bottom: -90, right: -60, child: _glow(260)),
          Positioned.fill(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    Container(
                      width: 54, height: 54,
                      decoration: BoxDecoration(
                        color: kGold.withOpacity(.13), borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: kGold.withOpacity(.55)),
                      ),
                      child: const Icon(Icons.style_rounded, color: kGold, size: 30),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('طرنيب', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                        Text('جلسات الأصدقاء • لعب جماعي مباشر', style: TextStyle(color: Colors.white60, fontSize: 12)),
                      ],
                    )),
                    IconButton(onPressed: _openServerSettings, icon: const Icon(Icons.settings_rounded, color: Colors.white70)),
                  ]),
                  const SizedBox(height: 28),
                  Container(
                    width: 148, height: 148,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [kGold.withOpacity(.25), kGold.withOpacity(.02)]),
                      border: Border.all(color: kGold.withOpacity(.35), width: 1.5),
                    ),
                    child: const Center(child: Text('♠  ♥\n♦  ♣', textAlign: TextAlign.center,
                      style: TextStyle(color: kGold, fontSize: 42, height: 1.35, fontWeight: FontWeight.bold))),
                  ),
                  const SizedBox(height: 22),
                  const Text('اجمع أصحابك حول الطاولة', textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  const Text('أنشئ غرفة خاصة، شارك الرقم، وابدأوا التحدي', textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60, fontSize: 14)),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _name, textAlign: TextAlign.center, maxLength: 18,
                    style: const TextStyle(color: Colors.white, fontSize: 17),
                    decoration: InputDecoration(
                      counterText: '', hintText: 'اسمك على الطاولة',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true, fillColor: Colors.white.withOpacity(.06),
                      prefixIcon: const Icon(Icons.person_outline, color: kGold),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Colors.white.withOpacity(.1))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Colors.white.withOpacity(.12))),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: kGold.withOpacity(.2))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('نهاية المباراة', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: _targetButton(41)),
                        const SizedBox(width: 10),
                        Expanded(child: _targetButton(61)),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(width: double.infinity, height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _busy ? null : _createRoom,
                      icon: const Icon(Icons.add_circle_outline),
                      label: Text(_busy ? 'جارٍ الاتصال...' : 'إنشاء طاولة جديدة',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(backgroundColor: kGold, foregroundColor: kInk,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, height: 56,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _showJoinDialog,
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('دخول برقم الطاولة',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white,
                        side: BorderSide(color: kGold.withOpacity(.7), width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text('٤ لاعبين • فريقان • ١٥ ثانية لكل دور',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
                  const SizedBox(height: 12),
                ]),
              ),
            ),
          ),
        ]),
      ),
    ),
  );

  Widget _targetButton(int value) {
    final selected = _target == value;
    return InkWell(
      onTap: () => setState(() => _target = value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? kGold : Colors.white.withOpacity(.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? kGold : Colors.white24),
        ),
        child: Center(child: Text('$value نقطة',
          style: TextStyle(color: selected ? kInk : Colors.white70, fontWeight: FontWeight.bold))),
      ),
    );
  }

  Widget _glow(double size) => Container(
    width: size, height: size,
    decoration: BoxDecoration(shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: kFelt.withOpacity(.8), blurRadius: 100, spreadRadius: 20)]),
  );
}
