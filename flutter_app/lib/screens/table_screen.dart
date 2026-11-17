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
  int _secondsLeft = 15;
  int _customCutAt = 18;
  String? _selectedCardCode;
  String? _firstTappedCardCode;
  Timer? _cardTapTimer;
  bool _disconnected = false;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  Timer? _clock;

  int get _mySeat => widget.mySeat;
  int? get _partnerSeat => (_state['partnerSeat'] as num?)?.toInt();
  String get _dealMode => (_state['dealMode'] ?? 'random').toString();
  int get _myTeam => (_mySeat == 0 || _partnerSeat == _mySeat) ? 0 : 1;
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
    s.on('report_debug_result', _onDebugHands);
    s.on('report_ack', _onReportAck);
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
    _cardTapTimer?.cancel();
    final s = widget.socket;
    s.off('room_update');
    s.off('game_state');
    s.off('notice');
    s.off('room_error');
    s.off('reaction');
    s.off('rematch_votes');
    s.off('report_debug_result');
    s.off('report_ack');
    super.dispose();
  }

  void _onRoomUpdate(dynamic data) {
    if (!mounted) return;
    final map = Map<String, dynamic>.from(data as Map);
    setState(() {
      _players = (map['players'] as List?) ?? [];
      _state['targetScore'] = map['targetScore'];
      _state['status'] = map['status'];
      _state['partnerSeat'] = map['partnerSeat'];
      _state['dealMode'] = map['dealMode'];
    });
  }

  void _onGameState(dynamic data) {
    if (!mounted) return;
    final incoming = Map<String, dynamic>.from(data as Map);
    final oldTrick = (_state['currentTrick'] as List?) ?? const [];
    final newTrick = (incoming['currentTrick'] as List?) ?? const [];
    final hasNewPlayedCard = newTrick.length > oldTrick.length;
    final lastPlayed = newTrick.isNotEmpty ? newTrick.last : null;
    final playedByOther = hasNewPlayedCard && lastPlayed is Map &&
        (lastPlayed['seat'] as num?)?.toInt() != _mySeat;
    if (playedByOther && _soundEnabled) SystemSound.play(SystemSoundType.click);
    setState(() {
      _state = incoming;
      _players = (_state['players'] as List?) ?? _players;
      final handCodes = _hand.map((card) => (card as Map)['code'].toString()).toSet();
      if (_selectedCardCode != null && !handCodes.contains(_selectedCardCode)) {
        _selectedCardCode = null;
        _firstTappedCardCode = null;
        _cardTapTimer?.cancel();
      }
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

  void _onReportAck(dynamic data) {
    if (!mounted) return;
    final message = data is Map ? (data['message'] ?? 'تم استلام البلاغ') : 'تم استلام البلاغ';
    _onNotice(message);
  }

  void _onDebugHands(dynamic data) {
    if (!mounted || data is! Map) return;
    final hands = (data['hands'] as List?) ?? const [];
    if (hands.isEmpty) {
      _onNotice('لا توجد أوراق منافسين مكشوفة في هذه المرحلة');
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: kPanel,
          title: const Text('أوراق اللاعبين الآخرين • وضع فحص التطوير', style: TextStyle(color: kGold, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: hands.map((raw) {
                final item = Map<String, dynamic>.from(raw as Map);
                final cards = (item['cards'] as List?) ?? const [];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${item['name'] ?? _playerName((item['seat'] as num).toInt())}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    SizedBox(height: 46, child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: cards.map((card) => PlayingCardWidget(
                        card: _cardModel(card), isMini: true, isPlayable: false,
                      )).toList()),
                    )),
                  ]),
                );
              }).toList()),
            ),
          ),
          actions: [
            if (data['mode'] == 'host-development-diagnostic')
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  widget.socket.emit('debug_boost_hand', {'roomCode': widget.roomCode});
                },
                child: const Text('🔥 تعزيز يدي (قبل اللعب فقط)', style: TextStyle(color: kGold)),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
          ],
        ),
      ),
    );
  }

  void _openReportDialog() {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: kPanel,
          title: const Text('إبلاغ', style: TextStyle(color: kGold, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            maxLength: 500,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'اكتب مشكلتك',
              hintStyle: const TextStyle(color: Colors.white54),
              filled: true, fillColor: Colors.black26,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                final message = controller.text.trim();
                if (message.isEmpty) return;
                Navigator.pop(ctx);
                widget.socket.emit('submit_report', {'roomCode': widget.roomCode, 'message': message});
              },
              style: ElevatedButton.styleFrom(backgroundColor: kGold, foregroundColor: kInk),
              child: const Text('إرسال'),
            ),
          ],
        ),
      ),
    ).whenComplete(controller.dispose);
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: widget.roomCode));
    _onNotice('تم نسخ رقم الطاولة');
  }

  String _trackerRankLabel(int rank) {
    switch (rank) {
      case 14: return 'A';
      case 13: return 'K';
      case 12: return 'Q';
      case 11: return 'J';
      default: return rank.toString();
    }
  }

  void _openCardTracker() {
    final playedCodes = <String>{};
    for (final raw in (_state['playedCards'] as List?) ?? const []) {
      if (raw is Map && raw['card'] is Map) playedCodes.add((raw['card'] as Map)['code'].toString());
    }
    final myCodes = _hand.map((raw) => (raw as Map)['code'].toString()).toSet();
    const suits = ['SPADES', 'HEARTS', 'DIAMONDS', 'CLUBS'];
    const ranks = [14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2];

    showModalBottomSheet<void>(
      context: context, isScrollControlled: true, backgroundColor: kPanel,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * .72,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(children: [
                  const Icon(Icons.style_rounded, color: kGold),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('حافظ الورق ومتابعة الأكلات', style: TextStyle(color: kGold, fontSize: 16, fontWeight: FontWeight.bold))),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, color: Colors.white70)),
                ]),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('الأخضر: معك • الرمادي: لُعبت • الأبيض: ورقة غير مكشوفة', style: TextStyle(color: Colors.white60, fontSize: 10)),
              ),
              const SizedBox(height: 8),
              Expanded(child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                children: suits.map((suit) {
                  final symbol = _symbols[suit]!;
                  final red = suit == 'HEARTS' || suit == 'DIAMONDS';
                  final playedCount = ranks.where((rank) => playedCodes.contains('$rank-$suit')).length;
                  final myCount = ranks.where((rank) => myCodes.contains('$rank-$suit')).length;
                  final unknownCount = 13 - playedCount - myCount;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.black.withOpacity(.22), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text('$symbol ${_suitNames[suit]}', style: TextStyle(color: red ? Colors.redAccent : Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        const Spacer(),
                        Text('معك $myCount • لُعبت $playedCount • مخفية $unknownCount', style: const TextStyle(color: Colors.white60, fontSize: 9)),
                      ]),
                      const SizedBox(height: 7),
                      Wrap(spacing: 5, runSpacing: 5, children: ranks.map((rank) {
                        final code = '$rank-$suit';
                        final wasPlayed = playedCodes.contains(code);
                        final inMyHand = myCodes.contains(code);
                        final bg = inMyHand ? const Color(0xFF146047) : wasPlayed ? Colors.white10 : Colors.white;
                        final fg = inMyHand ? Colors.white : wasPlayed ? Colors.white30 : (red ? Colors.red : const Color(0xFF17202A));
                        return Container(
                          width: 34, height: 38, alignment: Alignment.center,
                          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6), border: Border.all(color: inMyHand ? kGold : Colors.white12)),
                          child: Text('${_trackerRankLabel(rank)}$symbol', style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 10, decoration: wasPlayed ? TextDecoration.lineThrough : TextDecoration.none)),
                        );
                      }).toList()),
                    ]),
                  );
                }).toList(),
              )),
            ]),
          ),
        ),
      ),
    );
  }

  void _startGame() => widget.socket.emit('start_game');
  void _selectPartner(int seat) => widget.socket.emit('select_partner', {'roomCode': widget.roomCode, 'partnerSeat': seat});
  void _selectDealMode(String mode) => widget.socket.emit('select_deal_mode', {'roomCode': widget.roomCode, 'mode': mode});
  void _cutDeck(int cutAt) {
    if (_phase != 'cutting' || (_state['cutSeat'] as num?)?.toInt() != _mySeat) return;
    _feedback();
    widget.socket.emit('cut_deck', {'roomCode': widget.roomCode, 'cutAt': cutAt});
  }
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

  void _onHandCardTap(dynamic raw) {
    if (!_myTurn || _phase != 'playing' || !_isLegalCard(raw)) return;
    final code = (raw as Map)['code'].toString();
    if (_firstTappedCardCode == code && _cardTapTimer?.isActive == true) {
      _cardTapTimer?.cancel();
      _firstTappedCardCode = null;
      _playCard(raw);
      return;
    }
    _cardTapTimer?.cancel();
    _firstTappedCardCode = code;
    setState(() => _selectedCardCode = code);
    _cardTapTimer = Timer(const Duration(milliseconds: 550), () {
      if (_firstTappedCardCode == code) _firstTappedCardCode = null;
    });
  }

  void _playCard(dynamic card) {
    if (!_myTurn || _phase != 'playing' || !_isLegalCard(card)) return;
    _cardTapTimer?.cancel();
    _firstTappedCardCode = null;
    if (_soundEnabled) SystemSound.play(SystemSoundType.click);
    if (_vibrationEnabled) HapticFeedback.mediumImpact();
    setState(() => _selectedCardCode = null);
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

  void _openReactions() {
    showModalBottomSheet<void>(
      context: context, backgroundColor: kPanel, isScrollControlled: false,
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Wrap(alignment: WrapAlignment.spaceEvenly, spacing: 10, runSpacing: 8,
          children: _emojis.map((emoji) => InkWell(
            onTap: () { Navigator.pop(ctx); _sendEmoji(emoji); },
            borderRadius: BorderRadius.circular(20),
            child: Padding(padding: const EdgeInsets.all(6), child: Text(emoji, style: const TextStyle(fontSize: 26))),
          )).toList(),
        ),
      )),
    );
  }

  Widget _reactionButton() => Align(
    alignment: Alignment.centerRight,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 12, 5),
      child: InkWell(
        onTap: _openReactions,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 38, height: 34,
          decoration: BoxDecoration(color: Colors.black.withOpacity(.28), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
          child: const Icon(Icons.emoji_emotions_outlined, color: kGold, size: 19),
        ),
      ),
    ),
  );

  Widget _centerTable() {
    Widget trickCardForSeat(int seat) {
      final raw = _trick.cast<dynamic>().firstWhere(
        (item) => (item as Map)['seat'] == seat,
        orElse: () => null,
      );
      if (raw == null) return const SizedBox.shrink();
      final item = Map<String, dynamic>.from(raw as Map);
      return PlayingCardWidget(
        card: _cardModel(item['card']),
        isCompact: true,
        isPlayable: false,
      );
    }

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
        Positioned(right: 3, top: 0, bottom: 0, child: Center(child: RotatedBox(quarterTurns: 1, child: _playerBadge(1, '🂠')))),
        Positioned(left: 3, top: 0, bottom: 0, child: Center(child: RotatedBox(quarterTurns: 3, child: _playerBadge(3, '🂠')))),
        Center(
          child: DragTarget<Map<String, dynamic>>(
            onWillAcceptWithDetails: (details) => _myTurn && _phase == 'playing' && _isLegalCard(details.data),
            onAcceptWithDetails: (details) => _playCard(details.data),
            builder: (context, candidateData, rejectedData) {
              final hovering = candidateData.isNotEmpty;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 286,
                height: 188,
                decoration: BoxDecoration(
                  color: hovering ? kGold.withOpacity(.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: hovering ? kGold : Colors.white.withOpacity(.07),
                    width: hovering ? 2 : 1,
                  ),
                ),
                child: Stack(children: [
                  Positioned(top: 2, left: 0, right: 0, height: 68,
                    child: Center(child: trickCardForSeat(2))),
                  Positioned(bottom: 2, left: 0, right: 0, height: 68,
                    child: Center(child: trickCardForSeat(0))),
                  Positioned(left: 2, top: 0, bottom: 0, width: 52,
                    child: Center(child: trickCardForSeat(3))),
                  Positioned(right: 2, top: 0, bottom: 0, width: 52,
                    child: Center(child: trickCardForSeat(1))),
                  if (_trick.isEmpty && _myTurn && _phase == 'playing')
                    const Center(
                      child: Text('اسحب الورقة إلى منتصف الطاولة',
                        style: TextStyle(color: Colors.white38, fontSize: 10)),
                    ),
                  if (_phase == 'trick_resolving')
                    const Positioned(
                      bottom: 5, left: 0, right: 0,
                      child: Center(child: Text('تحديد الفائز بالأكلة…',
                        style: TextStyle(color: kGold, fontSize: 10, fontWeight: FontWeight.bold))),
                    ),
                ]),
              );
            },
          ),
        ),
        Positioned(bottom: 7, left: 0, right: 0, child: Center(
          child: Text(
            _phase == 'bidding' ? 'مرحلة الطلب' : _phase == 'playing' || _phase == 'trick_resolving' ? 'الأكلة الحالية' : _phase == 'round_result' ? 'نتيجة الجولة' : 'الطاولة',
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
          Builder(builder: (context) {
            final passed = (_state['passed'] as List?)?.map((e) => (e as num).toInt()).toSet() ?? <int>{};
            final dealer = (_state['dealerSeat'] as num?)?.toInt() ?? -1;
            final forcedOpen = bid == null && _myTurn && _mySeat == dealer &&
                [0, 1, 2, 3].where((seat) => seat != dealer).every(passed.contains);
            return TextButton(
              onPressed: _myTurn && !forcedOpen ? _passBid : null,
              child: Text(forcedOpen ? 'طلب إجباري 7' : 'تمرير', style: const TextStyle(color: Colors.white70)),
            );
          }),
        ]),
      ]),
    );
  }

  Widget _handArea() {
    if (_hand.isEmpty) return const SizedBox(height: 8);
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 2),
      padding: const EdgeInsets.fromLTRB(5, 5, 5, 2),
      decoration: BoxDecoration(color: Colors.black.withOpacity(.23), borderRadius: BorderRadius.circular(13)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Text('أوراقك', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
          const Spacer(),
          Text('${_hand.length} ورقة', style: const TextStyle(color: kGold, fontSize: 10)),
        ]),
        const SizedBox(height: 4),
        LayoutBuilder(builder: (context, constraints) {
          const cardWidth = 64.0;
          const cardHeight = 106.0;
          final count = _hand.length;
          final availableWidth = constraints.maxWidth;
          final step = count <= 1 ? cardWidth : ((availableWidth - cardWidth) / (count - 1)).clamp(22.0, cardWidth).toDouble();
          final handWidth = cardWidth + (count - 1) * step;
          final contentWidth = handWidth < availableWidth ? availableWidth : handWidth;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: contentWidth, height: cardHeight,
              child: Stack(clipBehavior: Clip.none, children: List.generate(count, (layerIndex) {
                // Draw left-side cards first, then overlay toward the right so every index remains visible.
                final index = count - 1 - layerIndex;
                final raw = _hand[index];
                final card = _cardModel(raw);
                final code = card.code;
                final legal = _isLegalCard(raw);
                final canPlay = _myTurn && _phase == 'playing' && legal;
                final selected = _selectedCardCode == code;
                final face = PlayingCardWidget(
                  card: card,
                  isHand: true,
                  isSelected: selected,
                  isLegal: legal,
                  isPlayable: canPlay,
                  onTap: canPlay ? () => _onHandCardTap(raw) : null,
                );
                return Positioned(
                  right: index * step,
                  top: 5,
                  child: Draggable<Map<String, dynamic>>(
                    data: Map<String, dynamic>.from(raw as Map),
                    maxSimultaneousDrags: canPlay ? 1 : 0,
                    feedback: Material(
                      color: Colors.transparent,
                      child: PlayingCardWidget(card: card, isHand: true, isSelected: true, isPlayable: false),
                    ),
                    childWhenDragging: Opacity(opacity: .35, child: face),
                    child: face,
                  ),
                );
              })),
            ),
          );
        }),
      ]),
    );
  }

  Widget _cutChoice(String label, int cutAt) => OutlinedButton(
    onPressed: () => _cutDeck(cutAt),
    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white30), padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7)),
    child: Text(label, style: const TextStyle(fontSize: 10)),
  );

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
          const SizedBox(height: 10),
          if (_isHost) ...[
            const Text('اختر شريكك', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [1, 2, 3].map((seat) => ChoiceChip(
              label: Text(_playerName(seat), style: const TextStyle(fontSize: 11)),
              selected: _partnerSeat == seat,
              onSelected: _players.length > seat && _players[seat] != null ? (_) => _selectPartner(seat) : null,
              selectedColor: kGold,
              backgroundColor: Colors.black26,
              labelStyle: TextStyle(color: _partnerSeat == seat ? kInk : Colors.white70),
            )).toList()),
            const SizedBox(height: 9),
            const Text('طريقة التوزيع', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Wrap(spacing: 7, children: [
              ChoiceChip(label: const Text('عشوائي نزيه'), selected: _dealMode == 'random', selectedColor: kGold, onSelected: (_) => _selectDealMode('random')),
              ChoiceChip(label: const Text('قصّ الشدّة'), selected: _dealMode == 'cut', selectedColor: kGold, onSelected: (_) => _selectDealMode('cut')),
              ChoiceChip(label: const Text('دفعات 4-3-3-3'), selected: _dealMode == 'batch_4333', selectedColor: kGold, onSelected: (_) => _selectDealMode('batch_4333')),
            ]),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: count == 4 && _partnerSeat != null ? _startGame : null,
              style: ElevatedButton.styleFrom(backgroundColor: kGold, foregroundColor: kInk),
              child: const Text('ابدأ اللعب'),
            ),
          ] else
            Text(_partnerSeat == null ? 'بانتظار صاحب الطاولة لاختيار الشريك وطريقة التوزيع' : 'شريك صاحب الطاولة: ${_playerName(_partnerSeat!)}',
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ]),
      );
    }
    if (_phase == 'cutting' && _status == 'playing') {
      final cutSeat = (_state['cutSeat'] as num?)?.toInt() ?? -1;
      final isMyCut = cutSeat == _mySeat;
      return Container(
        margin: const EdgeInsets.all(10), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(16), border: Border.all(color: kGold.withOpacity(.35))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('قصّ الشدّة قبل التوزيع', style: TextStyle(color: kGold, fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text(isMyCut ? 'دورك تقصّ الشدّة — اختر مكان القص' : 'بانتظار ${_playerName(cutSeat)} ليقصّ الشدّة', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: List.generate(4, (i) => Column(children: [
            Container(width: 42, height: 58, decoration: BoxDecoration(color: const Color(0xFF173D32), border: Border.all(color: kGold, width: 1.2), borderRadius: BorderRadius.circular(6)), child: const Center(child: Icon(Icons.style, color: Colors.white70, size: 22))),
            const SizedBox(height: 3), Text('13 ورقة', style: TextStyle(color: Colors.white54, fontSize: 9)),
          ]))),
          if (isMyCut) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
              _cutChoice('أول مجموعة', 13),
              _cutChoice('وسط الشدّة', 26),
              _cutChoice('آخر مجموعة', 39),
            ]),
            const SizedBox(height: 8),
            Text('أو اختر رقم القص: $_customCutAt', style: const TextStyle(color: Colors.white70, fontSize: 11)),
            const Text('بعد القص يبدأ التوزيع من يمين الموزّع', style: TextStyle(color: Colors.white54, fontSize: 10)),
            Slider(value: _customCutAt.toDouble(), min: 1, max: 51, divisions: 50, activeColor: kGold, label: '$_customCutAt', onChanged: (v) => setState(() => _customCutAt = v.round())),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => _cutDeck(_customCutAt), style: ElevatedButton.styleFrom(backgroundColor: kGold, foregroundColor: kInk), child: const Text('تأكيد القص والتوزيع'))),
          ] else
            const Padding(padding: EdgeInsets.only(top: 10), child: Text('سيبدأ التوزيع تلقائيًا بعد القص', style: TextStyle(color: Colors.white54, fontSize: 11))),
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
      final text = winner == null ? 'تعادل!' : (winner == _myTeam ? 'مبروك! فريقك فاز 🏆' : 'انتهت المباراة، الفريق الآخر فاز');
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
                IconButton(onPressed: _openCardTracker, tooltip: 'حافظ الورق', icon: const Icon(Icons.style_outlined, color: kGold)),
                IconButton(onPressed: _openReportDialog, tooltip: 'إبلاغ', icon: const Icon(Icons.flag_outlined, color: Colors.white70)),
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
                  Text('لنا: ${_tricks[_myTeam]}', style: const TextStyle(color: kGold, fontSize: 11)),
                  const Spacer(),
                  Text(bid == null ? 'الطلب' : 'الطلب ${bid['amount']} ${bid['symbol']}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  const Spacer(),
                  Text('لهم: ${_tricks[1 - _myTeam]}', style: const TextStyle(color: kGold, fontSize: 11)),
                ]),
              ),
            _biddingPanel(),
            _handArea(),
            _reactionButton(),
            if (_phase == 'playing' && _status == 'playing' && _myTurn)
              const Padding(padding: EdgeInsets.only(bottom: 3), child: Text('دورك الآن — اضغط مرتين أو اسحب الورقة إلى الوسط', style: TextStyle(color: kGold, fontSize: 10, fontWeight: FontWeight.bold))),
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
