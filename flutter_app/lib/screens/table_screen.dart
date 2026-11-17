import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../models/game_models.dart';
import '../widgets/playing_card_widget.dart';
import 'home_screen.dart';

class TableScreen extends StatefulWidget {
  final IO.Socket socket;
  final String roomCode;
  final String playerName;
  final String token;
  final int mySeat;

  const TableScreen({
    super.key, required this.socket, required this.roomCode,
    required this.playerName, required this.token, required this.mySeat,
  });

  @override
  State<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> {
  static const List<String> _emojis = ['😂', '😎', '😡', '👏', '🤔', '🔥', '💪'];
  static const List<String> _suits = ['SPADES', 'HEARTS', 'DIAMONDS', 'CLUBS'];
  static const Map<String, String> _symbols = {
    'SPADES': '♠', 'HEARTS': '♥', 'DIAMONDS': '♦', 'CLUBS': '♣',
  };
  static const Map<String, String> _suitNames = {
    'SPADES': 'بستوني', 'HEARTS': 'كبة', 'DIAMONDS': 'ديناري', 'CLUBS': 'سنك',
  };

  Map<String, dynamic> _state = {};
  List<dynamic> _players = [];
  List<int> _rematchVotes = [];
  final Map<int, String> _reactions = {};
  String _selectedSuit = 'SPADES';
  int _selectedBid = 7;
  int _secondsLeft = 15;
  bool _disconnected = false;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  Timer? _clock;

  int get _mySeat => widget.mySeat;
  int get _turnSeat => (_state['turnSeat'] as num?)?.toInt() ?? -1;
  String get _phase => (_state['phase'] ?? 'waiting').toString();
  String get _status => (_state['status'] ?? 'waiting').toString();
  bool get _myTurn => _turnSeat == _mySeat;
  bool get _isHost => _players.length > _mySeat &&
      _players[_mySeat] is Map && (_players[_mySeat]['isHost'] == true);
  List<dynamic> get _hand => (_state['myHand'] as List?) ?? [];
  List<dynamic> get _trick => (_state['currentTrick'] as List?) ?? [];
  List<dynamic> get _counts => (_state['handCounts'] as List?) ?? [0, 0, 0, 0];
  List<dynamic> get _scores => (_state['scores'] as List?) ?? [0, 0];
  List<dynamic> get _tricks => (_state['tricks'] as List?) ?? [0, 0];
  int get _target => (_state['targetScore'] as num?)?.toInt() ?? 41;
  int get _deadline => (_state['deadline'] as num?)?.toInt() ?? 0;

  @override
  void initState() {
    super.initState();
    final s = widget.socket;
    s.on('room_update', _onRoomUpdate);
    s.on('game_state', _onGameState);
    s.on('notice', _onNotice);
    s.on('room_error', _onNotice);
    s.on('reaction', _onReaction);
    s.on('rematch_votes', _onRematchVotes);
    // Re-announce this seat after listeners are attached so no initial state is missed.
    s.emit('join_room', {
      'roomCode': widget.roomCode,
      'playerName': widget.playerName,
      'token': widget.token,
    });
    s.onDisconnect((_) {
      if (mounted) setState(() => _disconnected = true);
    });
    s.onConnect((_) {
      if (_disconnected) {
        _disconnected = false;
        s.emit('join_room', {
          'roomCode': widget.roomCode,
          'playerName': widget.playerName,
          'token': widget.token,
        });
      }
    });
    _clock = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (!mounted) return;
      final left = _deadline == 0 ? 0 : ((_deadline - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
      if (left != _secondsLeft) setState(() => _secondsLeft = left.clamp(0, 15));
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    final s = widget.socket;
    s.off('room_update');
    s.off('game_state');
    s.off('notice');
    s.off('room_error');
    s.off('reaction');
    s.off('rematch_votes');
    super.dispose();
  }

  void _onRoomUpdate(dynamic data) {
    if (!mounted) return;
    final map = Map<String, dynamic>.from(data as Map);
    setState(() {
      _players = (map['players'] as List?) ?? [];
      _state['targetScore'] = map['targetScore'];
      _state['status'] = map['status'];
    });
  }

  void _onGameState(dynamic data) {
    if (!mounted) return;
    setState(() {
      _state = Map<String, dynamic>.from(data as Map);
      _players = (_state['players'] as List?) ?? _players;
      _secondsLeft = 15;
    });
  }

  void _onNotice(dynamic message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message.toString()), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)),
    );
  }

  void _onReaction(dynamic data) {
    if (!mounted) return;
    final map = Map<String, dynamic>.from(data as Map);
    final seat = (map['seat'] as num).toInt();
    setState(() => _reactions[seat] = map['emoji'].toString());
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _reactions[seat] == map['emoji']) setState(() => _reactions.remove(seat));
    });
  }

  void _onRematchVotes(dynamic data) {
    if (!mounted) return;
    setState(() => _rematchVotes = (data as List).map((e) => (e as num).toInt()).toList());
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: widget.roomCode));
    _onNotice('تم نسخ رقم الطاولة');
  }

  void _startGame() => widget.socket.emit('start_game');
  void _feedback() {
    if (_soundEnabled) SystemSound.play(SystemSoundType.click);
    if (_vibrationEnabled) HapticFeedback.selectionClick();
  }

  void _submitBid(int amount) {
    if (!_myTurn) return;
    _feedback();
    widget.socket.emit('submit_bid', {
      'roomCode': widget.roomCode, 'amount': amount, 'suit': _selectedSuit,
    });
  }
  void _passBid() {
    if (!_myTurn) return;
    _feedback();
    widget.socket.emit('submit_bid', {'roomCode': widget.roomCode, 'pass': true});
  }
  bool _isLegalCard(dynamic raw) {
    if (_phase != 'playing' || _trick.isEmpty) return true;

    final firstTrickItem = Map<String, dynamic>.from(_trick.first as Map);
    final leadCard = Map<String, dynamic>.from(firstTrickItem['card'] as Map);
    final ledSuit = leadCard['suit'].toString().toUpperCase();
    final hasLedSuit = _hand.any((item) {
      final handCard = Map<String, dynamic>.from(item as Map);
      return handCard['suit'].toString().toUpperCase() == ledSuit;
    });

    if (!hasLedSuit) return true;
    final card = Map<String, dynamic>.from(raw as Map);
    return card['suit'].toString().toUpperCase() == ledSuit;
  }

  void _playCard(dynamic card) {
    if (!_myTurn || _phase != 'playing' || !_isLegalCard(card)) return;
    if (_soundEnabled) SystemSound.play(SystemSoundType.click);
    if (_vibrationEnabled) HapticFeedback.mediumImpact();
    widget.socket.emit('play_card', {
      'roomCode': widget.roomCode, 'cardCode': card['code'].toString(),
    });
  }
  void _sendEmoji(String emoji) {
    _feedback();
    widget.socket.emit('quick_reaction', {'roomCode': widget.roomCode, 'emoji': emoji});
  }
  void _nextRound() => widget.socket.emit('next_round');
  void _playAgain() => widget.socket.emit('play_again');

  Future<void> _leave() async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: kPanel,
          title: const Text('مغادرة الطاولة؟', style: TextStyle(color: Colors.white)),
          content: const Text('يمكنك الرجوع لاحقاً باستخدام رقم الطاولة ورمز الاستعادة المحفوظ على جهازك.', style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('البقاء')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('مغادرة')),
          ],
        ),
      ),
    );
    if (shouldLeave == true && mounted) {
      widget.socket.emit('leave_room');
      widget.socket.disconnect();
      Navigator.pop(context);
    }
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context, backgroundColor: kPanel,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.all(18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('إعدادات الطاولة', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            SwitchListTile(
              value: _soundEnabled, activeColor: kGold, title: const Text('المؤثرات الصوتية', style: TextStyle(color: Colors.white)),
              onChanged: (v) { setSheet(() => _soundEnabled = v); setState(() => _soundEnabled = v); },
            ),
            SwitchListTile(
              value: _vibrationEnabled, activeColor: kGold, title: const Text('الاهتزاز', style: TextStyle(color: Colors.white)),
              onChanged: (v) { setSheet(() => _vibrationEnabled = v); setState(() => _vibrationEnabled = v); },
            ),
            ListTile(
              leading: const Icon(Icons.exit_to_app, color: Colors.redAccent),
              title: const Text('مغادرة الطاولة', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(ctx); _leave(); },
            ),
          ]),
        )),
      ),
    );
  }

  PlayingCardModel _cardModel(dynamic raw) {
    final map = Map<String, dynamic>.from(raw as Map);
    final suitName = map['suit'].toString().toLowerCase();
    final suit = CardSuit.values.firstWhere((s) => s.name == suitName, orElse: () => CardSuit.spades);
    return PlayingCardModel(
      suit: suit,
      rank: (map['rank'] as num).toInt(),
      code: map['code'].toString(),
    );
  }

  String _playerName(int seat) {
    if (seat >= _players.length || _players[seat] == null) return 'بانتظار لاعب';
    return (_players[seat]['name'] ?? 'لاعب').toString();
  }

  bool _connected(int seat) => seat < _players.length && _players[seat] != null && _players[seat]['connected'] == true;

  Widget _playerBadge(int seat, String position) {
    final active = _turnSeat == seat && _status == 'playing';
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Stack(clipBehavior: Clip.none, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: active ? kGold.withOpacity(.22) : Colors.black.withOpacity(.24),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: active ? kGold : Colors.white24, width: active ? 1.5 : 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(position, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 82),
              child: Text(_playerName(seat), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
            ),
            const SizedBox(width: 4),
            Text('${seat < _counts.length ? _counts[seat] : 0}', style: const TextStyle(color: kGold, fontSize: 10)),
          ]),
        ),
        if (!_connected(seat))
          const Positioned(right: -3, top: -4, child: Icon(Icons.wifi_off, color: Colors.orangeAccent, size: 13)),
        if (_reactions.containsKey(seat))
          Positioned(top: -38, left: 8, child: _ReactionBubble(emoji: _reactions[seat]!)),
      ]),
    ]);
  }

  Widget _reactionBar() => Container(
    padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
    decoration: BoxDecoration(color: Colors.black.withOpacity(.25), borderRadius: BorderRadius.circular(16)),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: _emojis.map((emoji) => InkWell(
        onTap: () => _sendEmoji(emoji),
        borderRadius: BorderRadius.circular(30),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: .92, end: 1),
            duration: const Duration(milliseconds: 500),
            curve: Curves.elasticOut,
            builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
            child: Text(emoji, style: const TextStyle(fontSize: 25)),
          ),
        ),
      )).toList(),
    ),
  );

  Widget _centerTable() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF146047), Color(0xFF083B2E)]),
        border: Border.all(color: kGold.withOpacity(.35), width: 1.3),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.25), blurRadius: 15, offset: const Offset(0, 6))],
      ),
      child: Stack(children: [
        Positioned.fill(child: Center(
          child: Opacity(opacity: .08, child: Icon(Icons.style, size: 110, color: kGold)),
        )),
        Positioned(top: 8, left: 0, right: 0, child: Center(child: _playerBadge(2, '👑'))),
        Positioned(left: 3, top: 0, bottom: 0, child: Center(child: RotatedBox(quarterTurns: 3, child: _playerBadge(1, '🂠')))),
        Positioned(right: 3, top: 0, bottom: 0, child: Center(child: RotatedBox(quarterTurns: 1, child: _playerBadge(3, '🂠')))),
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 5,
            runSpacing: 4,
            children: _trick.map((item) {
              final m = Map<String, dynamic>.from(item as Map);
              return PlayingCardWidget(card: _cardModel(m['card']), isMini: true, isPlayable: false);
            }).toList(),
          ),
        ),
        Positioned(bottom: 7, left: 0, right: 0, child: Center(
          child: Text(
            _phase == 'bidding' ? 'مرحلة الطلب' : _phase == 'playing' ? 'الأكلة الحالية' : _phase == 'round_result' ? 'نتيجة الجولة' : 'الطاولة',
            style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        )),
      ]),
    );
  }

  Widget _biddingPanel() {
    if (_phase != 'bidding' || _status != 'playing') return const SizedBox.shrink();
    final bid = _state['bid'] as Map?;
    final minBid = bid == null ? 7 : ((bid['amount'] as num).toInt() + 1);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(16), border: Border.all(color: kGold.withOpacity(.2))),
      child: Column(children: [
        Row(children: [
          const Text('اختيار الطرنيب', style: TextStyle(color: Colors.white70, fontSize: 11)),
          const Spacer(),
          Text(bid == null ? 'أول طلب يبدأ من 7' : 'أعلى طلب: ${bid['amount']} ${bid['symbol']}', style: const TextStyle(color: kGold, fontSize: 11)),
        ]),
        const SizedBox(height: 6),
        Row(
          children: _suits.map((suit) => Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: InkWell(
              onTap: () => setState(() => _selectedSuit = suit),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: _selectedSuit == suit ? kGold : Colors.black.withOpacity(.2),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: _selectedSuit == suit ? kGold : Colors.white12),
                ),
                child: Text('${_symbols[suit]}', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, color: _selectedSuit == suit ? kInk : (suit == 'HEARTS' || suit == 'DIAMONDS' ? Colors.redAccent : Colors.white))),
              ),
            ),
          ))).toList(),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: Wrap(
            spacing: 5,
            children: List.generate(7, (i) {
              final bidValue = i + 7;
              final enabled = _myTurn && bidValue >= minBid;
              return SizedBox(width: 34, height: 34, child: ElevatedButton(
                onPressed: enabled ? () => _submitBid(bidValue) : null,
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: kGold,
                  foregroundColor: kInk,
                  disabledBackgroundColor: Colors.white10,
                  disabledForegroundColor: Colors.white24,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text('$bidValue', style: const TextStyle(fontWeight: FontWeight.bold)),
              ));
            }),
          )),
          const SizedBox(width: 6),
          TextButton(onPressed: _myTurn ? _passBid : null, child: const Text('تمرير', style: TextStyle(color: Colors.white70))),
        ]),
      ]),
    );
  }

  Widget _handArea() {
    if (_hand.isEmpty) return const SizedBox(height: 10);
    return Container(
      margin: const EdgeInsets.fromLTRB(9, 0, 9, 3),
      padding: const EdgeInsets.fromLTRB(5, 6, 5, 3),
      decoration: BoxDecoration(color: Colors.black.withOpacity(.23), borderRadius: BorderRadius.circular(16)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Text('أوراقك', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
          const Spacer(),
          Text('${_hand.length} ورقة', style: const TextStyle(color: kGold, fontSize: 10)),
        ]),
        const SizedBox(height: 3),
        LayoutBuilder(
          builder: (context, constraints) {
            const cardWidth = 42.0;
            const cardHeight = 64.0;
            final count = _hand.length;
            final availableWidth = constraints.maxWidth;
            final step = count <= 1
                ? cardWidth
                : ((availableWidth - cardWidth) / (count - 1))
                    .clamp(18.0, cardWidth)
                    .toDouble();
            final handWidth = cardWidth + (count - 1) * step;

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: handWidth,
                height: cardHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: List.generate(count, (index) {
                    final raw = _hand[index];
                    return Positioned(
                      left: index * step,
                      top: 0,
                      child: PlayingCardWidget(
                        card: _cardModel(raw),
                        isCompact: true,
                        isLegal: _isLegalCard(raw),
                        onTap: _myTurn && _phase == 'playing'
                            ? () => _playCard(raw)
                            : null,
                        isPlayable: _myTurn && _phase == 'playing',
                      ),
                    );
                  }),
                ),
              ),
            );
          },
        ),
      ]),
    );
  }

  Widget _waitingOrResult() {
    if (_status == 'waiting') {
      final count = _players.where((p) => p != null).length;
      return Container(
        margin: const EdgeInsets.all(12), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          Text('رقم الطاولة: ${widget.roomCode}', style: const TextStyle(color: kGold, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text('شارك الرقم مع أصدقائك • اللاعبون: $count / 4', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 7),
          if (_isHost) ElevatedButton(
            onPressed: count == 4 ? _startGame : null,
            style: ElevatedButton.styleFrom(backgroundColor: kGold, foregroundColor: kInk),
            child: const Text('ابدأ اللعب'),
          ) else const Text('بانتظار صاحب الطاولة لبدء اللعب', style: TextStyle(color: Colors.white54)),
        ]),
      );
    }
    if (_phase == 'round_result' && _status == 'playing') {
      final round = _state['lastRound'] as Map?;
      return Container(
        margin: const EdgeInsets.all(10), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(14), border: Border.all(color: kGold.withOpacity(.3))),
        child: Column(children: [
          const Text('انتهت الجولة', style: TextStyle(color: kGold, fontSize: 18, fontWeight: FontWeight.bold)),
          if (round != null) Text(
            'نتيجة الطلب: ${round['bidMet'] == true ? 'ناجح' : 'لم يتحقق'} • النتيجة ${_scores[0]} - ${_scores[1]}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (_isHost) ElevatedButton(onPressed: _nextRound, child: const Text('الجولة التالية')),
          if (!_isHost) const Text('بانتظار صاحب الطاولة', style: TextStyle(color: Colors.white54)),
        ]),
      );
    }
    if (_status == 'finished') {
      final winner = _state['winnerTeam'];
      final text = winner == null ? 'تعادل!' : (winner == (_mySeat % 2) ? 'مبروك! فريقك فاز 🏆' : 'انتهت المباراة، الفريق الآخر فاز');
      return Container(
        margin: const EdgeInsets.all(10), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(14), border: Border.all(color: kGold)),
        child: Column(children: [
          Text(text, style: const TextStyle(color: kGold, fontSize: 18, fontWeight: FontWeight.bold)),
          Text('النتيجة النهائية: ${_scores[0]} - ${_scores[1]}', style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 6),
          ElevatedButton(
            onPressed: _rematchVotes.contains(_mySeat) ? null : _playAgain,
            style: ElevatedButton.styleFrom(backgroundColor: kGold, foregroundColor: kInk),
            child: Text(_rematchVotes.contains(_mySeat) ? 'تم تسجيل طلبك' : 'العبوا مرة أخرى بنفس رقم الطاولة'),
          ),
          Text('الموافقون: ${_rematchVotes.length}/4', style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ]),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final bid = _state['bid'] as Map?;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF071A18),
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 5, 10, 2),
              child: Row(children: [
                IconButton(onPressed: _openSettings, icon: const Icon(Icons.menu_rounded, color: Colors.white)),
                Expanded(child: InkWell(
                  onTap: _copyCode,
                  child: Column(children: [
                    Text('طاولة ${widget.roomCode}  ⧉', style: const TextStyle(color: kGold, fontWeight: FontWeight.bold, fontSize: 13)),
                    Text('الهدف $_target • ${_scores[0]} - ${_scores[1]}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ]),
                )),
                if (_status == 'playing' && (_phase == 'playing' || _phase == 'bidding'))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: _secondsLeft <= 5 ? Colors.red.withOpacity(.2) : kGold.withOpacity(.15), borderRadius: BorderRadius.circular(20)),
                    child: Text('$_secondsLeft ث', style: TextStyle(color: _secondsLeft <= 5 ? Colors.redAccent : kGold, fontWeight: FontWeight.bold)),
                  ),
                IconButton(onPressed: _openSettings, icon: const Icon(Icons.more_horiz, color: Colors.white70)),
              ]),
            ),
            if (_disconnected)
              Container(width: double.infinity, color: Colors.orange.shade900, padding: const EdgeInsets.all(5),
                child: const Text('الاتصال منقطع — نحاول إعادة الاتصال بالطاولة...', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 11))),
            Expanded(child: _centerTable()),
            _waitingOrResult(),
            if (_phase == 'playing' && _status == 'playing')
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  Text('لنا: ${_tricks[0]}', style: const TextStyle(color: kGold, fontSize: 11)),
                  const Spacer(),
                  Text(bid == null ? 'الطلب' : 'الطلب ${bid['amount']} ${bid['symbol']}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  const Spacer(),
                  Text('لهم: ${_tricks[1]}', style: const TextStyle(color: kGold, fontSize: 11)),
                ]),
              ),
            _biddingPanel(),
            _handArea(),
            Padding(padding: const EdgeInsets.fromLTRB(12, 2, 12, 7), child: _reactionBar()),
            if (_phase == 'playing' && _status == 'playing' && _myTurn)
              const Padding(padding: EdgeInsets.only(bottom: 3), child: Text('دورك الآن — اختر ورقة', style: TextStyle(color: kGold, fontSize: 11, fontWeight: FontWeight.bold))),
          ]),
        ),
      ),
    );
  }
}

class _ReactionBubble extends StatelessWidget {
  final String emoji;
  const _ReactionBubble({required this.emoji});
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: .2, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.elasticOut,
      builder: (_, value, child) => Transform.scale(scale: value, child: child),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Text(emoji, style: const TextStyle(fontSize: 25)),
      ),
    );
  }
}
