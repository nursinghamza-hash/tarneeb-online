import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../audio/game_audio.dart';
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
  static const List<String> _suits = ['HEARTS', 'SPADES', 'DIAMONDS', 'CLUBS'];
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
  final Map<String, Tween<double>> _cardDealTweens = {};
  String _selectedSuit = 'HEARTS';
  int _secondsLeft = 15;
  int _customCutAt = 18;
  String? _selectedCardCode;
  String? _recommendedCardCode;
  String? _firstTappedCardCode;
  Timer? _cardTapTimer;
  bool _disconnected = false;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _debugHandsVisible = false;
  List<dynamic> _debugHands = [];
  Timer? _clock;

  int get _mySeat => widget.mySeat;
  int? get _partnerSeat => (_state['partnerSeat'] as num?)?.toInt();
  String get _dealMode => (_state['dealMode'] ?? 'random').toString();
  int get _myTeam => _teamForSeat(_mySeat);
  int _teamForSeat(int seat) => (seat == 0 || seat == _partnerSeat) ? 0 : 1;

  int _partnerOfSeat(int seat) {
    final hostPartner = _partnerSeat ?? 2;
    if (seat == 0) return hostPartner;
    if (seat == hostPartner) return 0;
    return [0, 1, 2, 3].firstWhere(
      (candidate) => candidate != seat && candidate != 0 && candidate != hostPartner,
    );
  }
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
    s.on('debug_hint_card', _onDebugHintCard);
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
    unawaited(_audioPlayer.dispose());
    final s = widget.socket;
    s.off('room_update');
    s.off('game_state');
    s.off('notice');
    s.off('room_error');
    s.off('reaction');
    s.off('rematch_votes');
    s.off('report_debug_result');
    s.off('debug_hint_card');
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
      _state['aiPractice'] = map['aiPractice'] == true;
    });
  }

  void _onGameState(dynamic data) {
    if (!mounted) return;
    final incoming = Map<String, dynamic>.from(data as Map);
    final previousRoundNumber = (_state['roundNumber'] as num?)?.toInt();
    final incomingRoundNumber = (incoming['roundNumber'] as num?)?.toInt();
    if (incomingRoundNumber != null && incomingRoundNumber != previousRoundNumber) {
      _cardDealTweens.clear();
    }
    final oldTrick = (_state['currentTrick'] as List?) ?? const [];
    final newTrick = (incoming['currentTrick'] as List?) ?? const [];
    final hasNewPlayedCard = newTrick.length > oldTrick.length;
    final lastPlayed = newTrick.isNotEmpty ? newTrick.last : null;
    final playedByOther = hasNewPlayedCard && lastPlayed is Map &&
        (lastPlayed['seat'] as num?)?.toInt() != _mySeat;
    final previousTricks = (_state['tricks'] as List?) ?? const [0, 0];
    final incomingTricks = (incoming['tricks'] as List?) ?? previousTricks;
    final trickWasWon = incomingTricks.length >= 2 && previousTricks.length >= 2 &&
        List.generate(2, (i) => (incomingTricks[i] as num).toInt() > (previousTricks[i] as num).toInt()).any((v) => v);
    final previousPhase = _phase;
    final previousTurn = _turnSeat;
    final incomingPhase = (incoming['phase'] ?? 'waiting').toString();
    final incomingTurn = (incoming['turnSeat'] as num?)?.toInt() ?? -1;
    final previousBid = _state['bid'] as Map?;
    final incomingBid = incoming['bid'] as Map?;
    final newContractBid = incomingBid != null &&
        (previousBid == null ||
            previousBid['amount'] != incomingBid['amount'] ||
            previousBid['seat'] != incomingBid['seat']);
    if (incomingPhase == 'round_result' && previousPhase != 'round_result') {
      final lastRound = incoming['lastRound'] as Map?;
      _playSound(lastRound?['bidMet'] == true ? GameSound.success : GameSound.fail);
    } else if (trickWasWon) {
      _playSound(GameSound.trick);
    } else if (playedByOther) {
      _playSound(GameSound.card);
    } else if (newContractBid && (incomingBid['seat'] as num?)?.toInt() != _mySeat) {
      _playSound(GameSound.bid);
    } else if (incomingPhase == 'trump_selection' && previousPhase != 'trump_selection') {
      _playSound(GameSound.bid);
    } else if ((previousRoundNumber == null && incomingPhase == 'bidding') ||
        (incomingRoundNumber != null && previousRoundNumber != incomingRoundNumber)) {
      _playSound(GameSound.deal);
    }
    setState(() {
      if (incomingPhase == 'trump_selection' && previousPhase != 'trump_selection') {
        _selectedSuit = 'HEARTS';
      }
      if (previousTurn != incomingTurn) _recommendedCardCode = null;
      _state = incoming;
      _players = (_state['players'] as List?) ?? _players;
      _debugHandsVisible = incoming['debugMode'] == true;
      _debugHands = _debugHandsVisible ? ((incoming['debugHands'] as List?) ?? const []) : [];
      final handCodes = _hand.map((card) => (card as Map)['code'].toString()).toSet();
      if (_selectedCardCode != null && !handCodes.contains(_selectedCardCode)) {
        _selectedCardCode = null;
        _firstTappedCardCode = null;
        _cardTapTimer?.cancel();
      }
      if (_recommendedCardCode != null && !handCodes.contains(_recommendedCardCode)) {
        _recommendedCardCode = null;
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

  void _onDebugHintCard(dynamic data) {
    if (!mounted || data is! Map) return;
    final code = data['cardCode']?.toString();
    if (code == null || !_hand.any((raw) => (raw as Map)['code'].toString() == code)) {
      _onNotice('تعذر عرض الاقتراح؛ ربما تغير الدور');
      return;
    }
    setState(() => _recommendedCardCode = code);
    _onNotice('تم تمييز الورقة المقترحة باللون الأخضر');
  }

  void _onDebugHands(dynamic data) {
    if (!mounted || data is! Map) return;
    final enabled = data['enabled'] == true;
    setState(() {
      _debugHandsVisible = enabled;
      _debugHands = enabled ? ((data['hands'] as List?) ?? const []) : [];
    });
  }

  void _openReportDialog() {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: kPanel,
          title: const Text('إبلاغ / وضع الفحص 0099', style: TextStyle(color: kGold, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            maxLength: 500,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'اكتب مشكلتك أو أدخل 0099 لإظهار / إخفاء أوراق اللاعبين',
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

  void _startGame() => widget.socket.emit('start_game');
  void _selectPartner(int seat) {
    if (!_isHost || _status != 'waiting' || seat < 1 || seat > 3 || seat >= _players.length || _players[seat] == null) return;
    _feedback();
    widget.socket.emit('select_partner', {'roomCode': widget.roomCode, 'partnerSeat': seat});
  }
  void _selectDealMode(String mode) => widget.socket.emit('select_deal_mode', {'roomCode': widget.roomCode, 'mode': mode});
  void _cutDeck(int cutAt) {
    if (_phase != 'cutting' || (_state['cutSeat'] as num?)?.toInt() != _mySeat) return;
    _feedback(GameSound.deal);
    widget.socket.emit('cut_deck', {'roomCode': widget.roomCode, 'cutAt': cutAt});
  }
  void _playSound(GameSound sound) {
    if (!_soundEnabled) return;
    unawaited(GameAudio.play(_audioPlayer, sound));
  }

  void _feedback([GameSound sound = GameSound.tap]) {
    _playSound(sound);
    if (_vibrationEnabled) HapticFeedback.selectionClick();
  }

  void _submitBid(int amount) {
    if (!_myTurn || _phase != 'bidding') return;
    _feedback(GameSound.bid);
    widget.socket.emit('submit_bid', {
      'roomCode': widget.roomCode, 'amount': amount,
    });
  }

  void _confirmTrumpSuit() {
    if (!_myTurn || _phase != 'trump_selection') return;
    _feedback(GameSound.trump);
    widget.socket.emit('select_trump', {
      'roomCode': widget.roomCode, 'suit': _selectedSuit,
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
    _playSound(GameSound.card);
    if (_vibrationEnabled) HapticFeedback.mediumImpact();
    setState(() => _selectedCardCode = null);
    widget.socket.emit('play_card', {
      'roomCode': widget.roomCode, 'cardCode': card['code'].toString(),
    });
  }
  void _sendEmoji(String emoji) {
    _feedback(GameSound.reaction);
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

  String _playerAvatar(int seat) {
    if (seat >= 0 && seat < _players.length && _players[seat] is Map) {
      final value = (_players[seat]['avatar'] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return seat == _mySeat ? '😎' : '🙂';
  }

  Widget _bidAmountBadge(int seat) {
    final bid = _state['bid'] as Map?;
    final bidderSeat = (bid?['seat'] as num?)?.toInt() ?? -1;
    if (bid == null || bidderSeat != seat) return const SizedBox.shrink();

    final amount = (bid['amount'] as num?)?.toInt() ?? 0;
    final lastRound = _state['lastRound'] as Map?;
    final roundNumber = (_state['roundNumber'] as num?)?.toInt();
    final completedThisRound = lastRound != null &&
        (lastRound['roundNumber'] as num?)?.toInt() == roundNumber &&
        lastRound['bid'] is Map;
    final bidMet = completedThisRound ? lastRound['bidMet'] == true : null;
    final bidderTeam = _teamForSeat(seat);
    final currentTricks = _tricks.length > bidderTeam ? (_tricks[bidderTeam] as num).toInt() : 0;
    final contractColor = bidMet == true
        ? const Color(0xFF22C55E)
        : bidMet == false
            ? const Color(0xFFE53935)
            : currentTricks >= amount
                ? const Color(0xFF22C55E)
                : const Color(0xFFFFC928);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: contractColor,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white.withOpacity(.75), width: .8),
        boxShadow: [BoxShadow(color: contractColor.withOpacity(.35), blurRadius: 5)],
      ),
      child: Text('طلب $amount',
        style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w900)),
    );
  }

  Widget _playerBadge(int seat, String fallback) {
    final active = _turnSeat == seat && _status == 'playing';
    final name = _playerName(seat);
    final avatar = _playerAvatar(seat);
    final count = seat < _counts.length ? _counts[seat] : 0;
    final cardBackCount = (count is num ? count.toInt() : 0).clamp(0, 13);
    return SizedBox(
      width: 70,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
          if (seat != _mySeat && cardBackCount > 0)
            for (var i = 0; i < cardBackCount; i++)
              Positioned(
                left: -8.0 + i * 4.7,
                top: 8.0 + (i - (cardBackCount - 1) / 2).abs() * 1.3,
                child: Transform.rotate(
                  angle: (i - (cardBackCount - 1) / 2) * .035,
                  child: Container(
                    width: 16, height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF9E1C2D),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: const Color(0xFF4A1018), width: 1),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(.35), blurRadius: 3, offset: const Offset(1, 2))],
                    ),
                    child: const Center(child: Icon(Icons.style_rounded, color: Color(0x55FFFFFF), size: 9)),
                  ),
                ),
              ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 50,
            height: 50,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF202020),
              border: Border.all(color: active ? const Color(0xFFFFC928) : Colors.white70, width: active ? 3 : 1.5),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(.4), blurRadius: 8, offset: const Offset(0, 3)),
                if (active) const BoxShadow(color: Color(0x66FFC928), blurRadius: 12),
              ],
            ),
            child: CircleAvatar(
              backgroundColor: const Color(0xFF34443B),
              child: Text(avatar.isEmpty ? fallback : avatar, style: const TextStyle(fontSize: 25)),
            ),
          ),
          if (!_connected(seat))
            const Positioned(right: -3, top: -2, child: Icon(Icons.wifi_off, color: Colors.orangeAccent, size: 14)),
          if (_reactions.containsKey(seat))
            Positioned(top: -35, child: _ReactionBubble(emoji: _reactions[seat]!)),
          Positioned(bottom: -8, left: -9, child: _bidAmountBadge(seat)),
        ]),
        const SizedBox(height: 15),
        Container(
          constraints: const BoxConstraints(minWidth: 64, maxWidth: 70),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(.48),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: active ? const Color(0xFFFFD34F) : Colors.white54, width: active ? 1.4 : .8),
          ),
          child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: active ? FontWeight.bold : FontWeight.w500)),
        ),
        if (_status == 'playing' && _phase != 'bidding' && _phase != 'trump_selection')
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(color: Colors.black.withOpacity(.8), borderRadius: BorderRadius.circular(7)),
              child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
            ),
          ),
      ]),
    );
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

  Widget _lastTrickPreview() {
    final cards = (_state['lastTrick'] as List?) ?? const [];
    if (cards.isEmpty) return const SizedBox.shrink();

    Widget miniAt(int index) {
      if (index >= cards.length) return const SizedBox.shrink();
      final item = Map<String, dynamic>.from(cards[index] as Map);
      return PlayingCardWidget(
        card: _cardModel(item['card']),
        cardWidth: 25,
        cardHeight: 37,
        isPlayable: false,
      );
    }

    return Container(
      width: 78,
      height: 77,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.26),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(.07)),
      ),
      child: Stack(children: [
        Positioned(top: 0, left: 26, child: miniAt(0)),
        Positioned(left: 1, top: 20, child: miniAt(1)),
        Positioned(right: 1, top: 20, child: miniAt(2)),
        Positioned(bottom: 0, left: 26, child: miniAt(3)),
      ]),
    );
  }

  Widget _footerInfoBar({required String label, required String value}) {
    return Container(
      height: 29,
      decoration: BoxDecoration(
        color: const Color(0xFF050505),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white.withOpacity(.08)),
      ),
      child: Row(children: [
        Expanded(
          child: Center(child: Text(value,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))),
        ),
        Container(width: 1, height: 19, color: Colors.white.withOpacity(.08)),
        SizedBox(
          width: 72,
          child: Center(child: Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600))),
        ),
      ]),
    );
  }

  Widget _scoreboard() {
    final partnerSeat = _partnerOfSeat(_mySeat);
    final sideSeats = [1, 2, 3, 0]
        .map((offset) => (_mySeat + offset) % 4)
        .where((seat) => seat != _mySeat && seat != partnerSeat)
        .toList();
    final rightSeat = sideSeats.isNotEmpty ? sideSeats.first : (_mySeat + 1) % 4;
    final leftSeat = sideSeats.length > 1 ? sideSeats.last : (_mySeat + 3) % 4;

    int scoreForSeat(int seat) {
      final team = _teamForSeat(seat);
      return _scores.length > team ? (_scores[team] as num).toInt() : 0;
    }

    Widget pill(int value) => Container(
      constraints: const BoxConstraints(minWidth: 31, minHeight: 25),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.92),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withOpacity(.08)),
      ),
      alignment: Alignment.center,
      child: Text('$value', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
    );

    return SizedBox(
      width: 88, height: 78,
      child: Stack(alignment: Alignment.center, children: [
        Container(width: 60, height: 60, decoration: BoxDecoration(
          border: Border.all(color: Colors.white24, width: 1.2), borderRadius: BorderRadius.circular(13))),
        Text('$_target', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
        // Bottom and top are partners: both show the same team score.
        Positioned(top: 0, child: pill(scoreForSeat(partnerSeat))),
        Positioned(bottom: 0, child: pill(scoreForSeat(_mySeat))),
        // Left and right are the opposing partnership: both show their shared score.
        Positioned(left: 0, child: pill(scoreForSeat(leftSeat))),
        Positioned(right: 0, child: pill(scoreForSeat(rightSeat))),
      ]),
    );
  }

  Widget _centerTable() {
    final southSeat = _mySeat;
    final northSeat = _partnerOfSeat(southSeat);
    final sideSeats = [1, 2, 3, 0]
        .map((offset) => (southSeat + offset) % 4)
        .where((seat) => seat != southSeat && seat != northSeat)
        .toList();
    final eastSeat = sideSeats.isNotEmpty ? sideSeats.first : ((southSeat + 1) % 4);
    final westSeat = sideSeats.length > 1 ? sideSeats.last : ((southSeat + 3) % 4);

    Widget trickCardForSeat(int seat) {
      final raw = _trick.cast<dynamic>().firstWhere(
        (item) => (item as Map)['seat'] == seat,
        orElse: () => null,
      );
      if (raw == null) return const SizedBox.shrink();
      final item = Map<String, dynamic>.from(raw as Map);
      return PlayingCardWidget(
        card: _cardModel(item['card']),
        cardWidth: 51,
        cardHeight: 76,
        isPlayable: false,
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      final maxWidth = constraints.maxWidth;
      final maxHeight = constraints.maxHeight;
      final boardWidth = math.min(maxWidth * .72, maxHeight * .84).clamp(230.0, 560.0).toDouble();
      final boardHeight = math.min(maxHeight * .91, boardWidth * 1.30).toDouble();
      final boardLeft = (maxWidth - boardWidth) / 2;
      final boardTop = (maxHeight - boardHeight - 8).clamp(8.0, maxHeight).toDouble();
      final centerWidth = math.min(boardWidth * .50, 185.0).toDouble();
      final centerHeight = math.min(boardHeight * .43, 194.0).toDouble();

      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF222222), Color(0xFF171717), Color(0xFF101010)],
          ),
        ),
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(left: 9, top: 4, child: _scoreboard()),
          Positioned(right: 9, top: 4, child: _lastTrickPreview()),
          Positioned(
            left: boardLeft, top: boardTop, width: boardWidth, height: boardHeight,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(38),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF20B94B), Color(0xFF0C9B38), Color(0xFF08732F)],
                  stops: [0, .48, 1],
                ),
                border: Border.all(color: const Color(0xFFBFC8BD), width: 4),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(.68), blurRadius: 20, offset: const Offset(0, 13)),
                  const BoxShadow(color: Color(0x5597A39A), blurRadius: 5, spreadRadius: 1),
                  const BoxShadow(color: Color(0x3300E64D), blurRadius: 20, spreadRadius: -5),
                ],
              ),
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(child: IgnorePointer(child: Center(
                  child: Container(
                    width: boardWidth * .43, height: boardWidth * .43,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(.035), width: 1.5),
                    ),
                  ),
                ))),
                Positioned(top: 8, left: 0, right: 0, child: Center(child: _playerBadge(northSeat, '👑'))),
                Positioned(left: 1, top: 0, bottom: 0, child: Center(child: _playerBadge(westSeat, '🙂'))),
                Positioned(right: 1, top: 0, bottom: 0, child: Center(child: _playerBadge(eastSeat, '🙂'))),
                Center(
                  child: DragTarget<Map<String, dynamic>>(
                    onWillAcceptWithDetails: (details) => _myTurn && _phase == 'playing' && _isLegalCard(details.data),
                    onAcceptWithDetails: (details) => _playCard(details.data),
                    builder: (context, candidateData, rejectedData) {
                      final hovering = candidateData.isNotEmpty;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        width: centerWidth,
                        height: centerHeight,
                        decoration: BoxDecoration(
                          color: hovering ? const Color(0x33FFF0A8) : Colors.black.withOpacity(.035),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: hovering ? const Color(0xFFFFD34F) : Colors.white.withOpacity(.055), width: hovering ? 2 : 1),
                        ),
                        child: Stack(children: [
                          Positioned(top: 1, left: 0, right: 0, height: 78,
                            child: Center(child: trickCardForSeat(northSeat))),
                          Positioned(bottom: 1, left: 0, right: 0, height: 78,
                            child: Center(child: trickCardForSeat(southSeat))),
                          Positioned(left: 1, top: 0, bottom: 0, width: 54,
                            child: Center(child: trickCardForSeat(westSeat))),
                          Positioned(right: 1, top: 0, bottom: 0, width: 54,
                            child: Center(child: trickCardForSeat(eastSeat))),
                          if (_trick.isEmpty && _myTurn && _phase == 'playing')
                            const Center(child: Icon(Icons.touch_app_rounded, color: Color(0x55FFFFFF), size: 25)),
                          if (_phase == 'trick_resolving')
                            const Positioned(bottom: 3, left: 0, right: 0,
                              child: Center(child: Text('تحديد الفائز بالأكلة…',
                                style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)))),
                        ]),
                      );
                    },
                  ),
                ),
                Positioned(bottom: 9, left: 0, right: 0, child: Center(
                  child: Text(
                    _phase == 'bidding' ? 'مرحلة الطلب'
                      : _phase == 'trump_selection' ? 'اختيار الحكم'
                      : _phase == 'playing' || _phase == 'trick_resolving' ? 'الأكلة الحالية'
                      : _phase == 'round_result' ? 'نتيجة الجولة' : 'بانتظار اللاعبين',
                    style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                )),
              ]),
            ),
          ),
        ]),
      );
    });
  }

  Widget _biddingPanel() {
    if (_phase != 'bidding' || _status != 'playing') return const SizedBox.shrink();
    final bid = _state['bid'] as Map?;
    final minBid = bid == null ? 7 : ((bid['amount'] as num).toInt() + 1);
    final passed = (_state['passed'] as List?)?.map((e) => (e as num).toInt()).toSet() ?? <int>{};
    final dealer = (_state['dealerSeat'] as num?)?.toInt() ?? -1;
    final forcedOpen = bid == null && _myTurn && _mySeat == dealer &&
        [0, 1, 2, 3].where((seat) => seat != dealer).every(passed.contains);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xF0181918),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x55FFFFFF)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.55), blurRadius: 16, offset: const Offset(0, 7))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('اختر الطلب', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
        const SizedBox(height: 5),
        Text(bid == null ? 'أول طلب يبدأ من 7' : 'أعلى طلب: ' + bid['amount'].toString(),
          style: const TextStyle(color: Colors.white60, fontSize: 10)),
        const SizedBox(height: 12),
        Wrap(alignment: WrapAlignment.center, spacing: 7, runSpacing: 7, children: List.generate(7, (i) {
          final amount = i + 7;
          final enabled = _myTurn && amount >= minBid;
          return SizedBox(
            width: 39, height: 39,
            child: ElevatedButton(
              onPressed: enabled ? () => _submitBid(amount) : null,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: const Color(0xFFFFC928),
                foregroundColor: const Color(0xFF201806),
                disabledBackgroundColor: Colors.white10,
                disabledForegroundColor: Colors.white24,
                elevation: enabled ? 3 : 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(amount.toString(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            ),
          );
        })),
        const SizedBox(height: 5),
        TextButton(
          onPressed: _myTurn && !forcedOpen ? _passBid : null,
          child: Text(forcedOpen ? 'طلب إجباري عليك: 7' : 'تمرير',
            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }

  Widget _trumpSelectionPanel() {
    if (_phase != 'trump_selection' || _status != 'playing') return const SizedBox.shrink();
    final bid = _state['bid'] as Map?;
    final bidderSeat = (bid?['seat'] as num?)?.toInt() ?? -1;
    final isMyChoice = _myTurn && bidderSeat == _mySeat;
    final amount = bid?['amount']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      padding: const EdgeInsets.fromLTRB(12, 13, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xF0181918),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFD34F), width: 1.3),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.55), blurRadius: 16, offset: const Offset(0, 7))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          isMyChoice ? 'رسا عليك الطلب ' + amount + ' — اختر لون الطرنيب'
            : 'رسا الطلب ' + amount + ' على ' + _playerName(bidderSeat),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFFFD34F), fontSize: 13, fontWeight: FontWeight.w900),
        ),
        if (isMyChoice) ...[
          const SizedBox(height: 12),
          Row(children: _suits.map((suit) {
            final selected = _selectedSuit == suit;
            final red = suit == 'HEARTS' || suit == 'DIAMONDS';
            final color = red ? const Color(0xFFE34848) : const Color(0xFFF3F3F3);
            return Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: InkWell(
                onTap: () { _feedback(); setState(() => _selectedSuit = suit); },
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFFFFC928) : const Color(0xFF2B2C2A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: selected ? const Color(0xFFFFE68A) : Colors.white24, width: selected ? 2 : 1),
                    boxShadow: selected ? [const BoxShadow(color: Color(0x55FFC928), blurRadius: 9)] : const [],
                  ),
                  child: Column(children: [
                    Text(_symbols[suit]!, style: TextStyle(fontSize: 26, color: selected ? const Color(0xFF211A08) : color, fontWeight: FontWeight.w900)),
                    Text(_suitNames[suit]!, style: TextStyle(fontSize: 9, color: selected ? const Color(0xFF211A08) : Colors.white70)),
                  ]),
                ),
              ),
            ));
          }).toList()),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _confirmTrumpSuit,
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFC928), foregroundColor: const Color(0xFF211A08)),
            child: const Text('تأكيد الحكم وبدء اللعب', style: TextStyle(fontWeight: FontWeight.bold)),
          )),
        ] else
          const Padding(padding: EdgeInsets.only(top: 8), child: Text('بانتظار اختيار لون الطرنيب', style: TextStyle(color: Colors.white60, fontSize: 11))),
      ]),
    );
  }

  Widget _handArea() {
    if (_hand.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      const suitOrder = {
        CardSuit.clubs: 0,
        CardSuit.diamonds: 1,
        CardSuit.spades: 2,
        CardSuit.hearts: 3,
      };
      final cards = _hand.map((raw) => <String, dynamic>{
        'raw': raw,
        'card': _cardModel(raw),
      }).toList();
      cards.sort((a, b) {
        final first = a['card'] as PlayingCardModel;
        final second = b['card'] as PlayingCardModel;
        final bySuit = suitOrder[first.suit]!.compareTo(suitOrder[second.suit]!);
        if (bySuit != 0) return bySuit;
        return second.rank.compareTo(first.rank);
      });

      final availableWidth = constraints.maxWidth - 18;
      final cardWidth = (availableWidth / 6.0).clamp(45.0, 59.0).toDouble();
      final cardHeight = cardWidth * 1.82;
      final count = cards.length;
      final step = count <= 1
        ? cardWidth
        : ((availableWidth - cardWidth) / (count - 1)).clamp(16.0, cardWidth).toDouble();
      final handWidth = cardWidth + (count - 1) * step;

      return Container(
        margin: const EdgeInsets.fromLTRB(7, 0, 7, 2),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
        decoration: BoxDecoration(
          color: const Color(0xE9101110),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(15), bottom: Radius.circular(8)),
          border: Border.all(color: Colors.white.withOpacity(.07)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Text('أوراقك', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text(count.toString() + ' ورقة', style: const TextStyle(color: Color(0xFFFFD34F), fontSize: 10, fontWeight: FontWeight.bold)),
            if (_phase == 'playing' && _myTurn) ...[
              const SizedBox(width: 8),
              const Icon(Icons.touch_app_rounded, size: 13, color: Color(0xFFFFD34F)),
            ],
          ]),
          const SizedBox(height: 5),
          SizedBox(
            height: cardHeight + 5,
            width: double.infinity,
            child: Center(
              child: SizedBox(
                width: handWidth,
                height: cardHeight + 3,
                child: Stack(clipBehavior: Clip.none, children: List.generate(count, (layerIndex) {
                  // Index zero is placed at the far right. Reverse suit order here so
                  // the visible left-to-right hand order is: hearts, spades, diamonds, clubs.
                  final index = count - 1 - layerIndex;
                  final raw = cards[index]['raw'];
                  final card = cards[index]['card'] as PlayingCardModel;
                  final legal = _isLegalCard(raw);
                  final canPlay = _myTurn && _phase == 'playing' && legal;
                  final selected = _selectedCardCode == card.code;
                  final face = PlayingCardWidget(
                    card: card,
                    isHand: true,
                    cardWidth: cardWidth,
                    cardHeight: cardHeight,
                    isSelected: selected,
                    isRecommended: _recommendedCardCode == card.code,
                    isLegal: legal,
                    isPlayable: canPlay,
                    onTap: canPlay ? () => _onHandCardTap(raw) : null,
                  );
                  final roundNumber = (_state['roundNumber'] as num?)?.toInt() ?? 0;
                  return Positioned(
                    key: ValueKey('$roundNumber-${card.code}'),
                    right: index * step,
                    top: selected ? 0 : 3,
                    child: TweenAnimationBuilder<double>(
                      tween: _cardDealTweens.putIfAbsent('$roundNumber-${card.code}', () => Tween<double>(begin: 0, end: 1)),
                      duration: Duration(milliseconds: 260 + layerIndex * 24),
                      curve: Curves.easeOutCubic,
                      builder: (context, progress, child) => Opacity(
                        opacity: progress,
                        child: Transform.translate(
                          offset: Offset(0, (1 - progress) * 34),
                          child: Transform.scale(scale: .9 + .1 * progress, child: child),
                        ),
                      ),
                      child: Draggable<Map<String, dynamic>>(
                        data: Map<String, dynamic>.from(raw as Map),
                        maxSimultaneousDrags: canPlay ? 1 : 0,
                        feedback: Material(
                          color: Colors.transparent,
                          child: PlayingCardWidget(
                            card: card, isHand: true,
                            cardWidth: cardWidth, cardHeight: cardHeight,
                            isSelected: true, isPlayable: false,
                          ),
                        ),
                        childWhenDragging: Opacity(opacity: .28, child: face),
                        child: face,
                      ),
                    ),
                  );
                })),
              ),
            ),
          ),
        ]),
      );
    });
  }

  Widget _cutChoice(String label, int cutAt) => OutlinedButton(
    onPressed: () => _cutDeck(cutAt),
    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white30), padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7)),
    child: Text(label, style: const TextStyle(fontSize: 10)),
  );

  Widget _debugHandsOverlay() {
    return LayoutBuilder(builder: (context, constraints) {
      final rows = _debugHands;
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        constraints: BoxConstraints(maxWidth: math.min(constraints.maxWidth - 20, 440), maxHeight: constraints.maxHeight - 24),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
        decoration: BoxDecoration(
          color: const Color(0xF20A0B0A),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: const Color(0xFFFFC928), width: 1.4),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.65), blurRadius: 22, offset: const Offset(0, 8))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Icon(Icons.visibility_rounded, color: Color(0xFFFFC928), size: 18),
            const SizedBox(width: 6),
            const Expanded(child: Text('وضع 0099 • أوراق اللاعبين الأربعة',
              style: TextStyle(color: Color(0xFFFFD34F), fontWeight: FontWeight.w900, fontSize: 12))),
            TextButton(
              onPressed: _openReportDialog,
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 5), minimumSize: const Size(0, 28)),
              child: const Text('0099 للإخفاء', style: TextStyle(color: Colors.white70, fontSize: 9)),
            ),
          ]),
          const Divider(height: 8, color: Colors.white24),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('لا توجد أوراق موزعة حالياً', style: TextStyle(color: Colors.white70, fontSize: 11)),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: rows.map((raw) {
                  final item = Map<String, dynamic>.from(raw as Map);
                  final seat = (item['seat'] as num?)?.toInt() ?? 0;
                  final cards = ((item['cards'] as List?) ?? const []).toList();
                  const order = {'HEARTS': 0, 'SPADES': 1, 'DIAMONDS': 2, 'CLUBS': 3};
                  cards.sort((a, b) {
                    final first = Map<String, dynamic>.from(a as Map);
                    final second = Map<String, dynamic>.from(b as Map);
                    final suitCompare = (order[first['suit'].toString().toUpperCase()] ?? 9)
                        .compareTo(order[second['suit'].toString().toUpperCase()] ?? 9);
                    return suitCompare != 0
                        ? suitCompare
                        : (second['rank'] as num).compareTo(first['rank'] as num);
                  });
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      SizedBox(
                        width: 62,
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(_playerAvatar(seat), style: const TextStyle(fontSize: 18)),
                          Text(item['name']?.toString() ?? _playerName(seat),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 8)),
                        ]),
                      ),
                      Expanded(
                        child: SizedBox(
                          height: 38,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(children: cards.map((card) => Padding(
                              padding: const EdgeInsets.only(right: 2),
                              child: PlayingCardWidget(
                                card: _cardModel(card),
                                cardWidth: 23,
                                cardHeight: 35,
                                isPlayable: false,
                              ),
                            )).toList()),
                          ),
                        ),
                      ),
                    ]),
                  );
                }).toList()),
              ),
            ),
          const SizedBox(height: 3),
          const Text('أدخل 0099 من زر الإبلاغ مرة أخرى لإرجاع الطاولة للوضع الطبيعي',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 8)),
        ]),
      );
    });
  }

  Widget _waitingOrResult() {
    if (_status == 'waiting') {
      final count = _players.where((p) => p != null).length;
      final connectedCount = _players.where((p) => p != null && (p['connected'] == true || p['isBot'] == true)).length;
      final chosenPartner = _partnerSeat;
      Widget partnerOption(int seat) {
        final selected = chosenPartner == seat;
        final candidate = seat < _players.length ? _players[seat] : null;
        final available = candidate is Map && (candidate['connected'] == true || candidate['isBot'] == true);
        return Expanded(
          child: InkWell(
            onTap: _isHost && count == 4 && connectedCount == 4 && available ? () => _selectPartner(seat) : null,
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.fromLTRB(3, 7, 3, 6),
              decoration: BoxDecoration(
                color: selected ? const Color(0x3329C85B) : Colors.white.withOpacity(.035),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? const Color(0xFF48D879) : Colors.white.withOpacity(.12),
                  width: selected ? 2 : 1,
                ),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 51, height: 51,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? const Color(0xFF0E7D3A) : const Color(0xFF242424),
                    border: Border.all(color: selected ? const Color(0xFF7DE99E) : Colors.white24, width: selected ? 2 : 1),
                  ),
                  alignment: Alignment.center,
                  child: Text(available ? _playerAvatar(seat) : '…', style: const TextStyle(fontSize: 27)),
                ),
                const SizedBox(height: 5),
                Text(
                  available ? _playerName(seat) : 'مقعد فارغ',
                  maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                  style: TextStyle(color: selected ? const Color(0xFF8FF0AE) : Colors.white70, fontSize: 10, fontWeight: selected ? FontWeight.bold : FontWeight.normal),
                ),
                if (selected)
                  const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.check_circle, color: Color(0xFF6FE18C), size: 15)),
              ]),
            ),
          ),
        );
      }

      return Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(13, 15, 13, 13),
        decoration: BoxDecoration(
          color: const Color(0xF2080909),
          borderRadius: BorderRadius.circular(23),
          border: Border.all(color: Colors.white.withOpacity(.16)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(.65), blurRadius: 22, offset: const Offset(0, 10)),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'الرجاء اختيار شريكك',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            'طاولة ${widget.roomCode} • اللاعبون $count / 4',
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
          const SizedBox(height: 11),
          Container(height: 1, color: Colors.white.withOpacity(.12)),
          const SizedBox(height: 11),
          Row(children: [partnerOption(1), const SizedBox(width: 7), partnerOption(2), const SizedBox(width: 7), partnerOption(3)]),
          const SizedBox(height: 9),
          if (_isHost) ...[
            Text(
              count == 4
                ? (chosenPartner == null ? 'اختر أحد اللاعبين الثلاثة ليكون شريكك' : 'شريكك: ${_playerName(chosenPartner)}')
                : 'بانتظار اتصال جميع اللاعبين قبل اختيار الشريك',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
            const SizedBox(height: 9),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton(
                onPressed: count == 4 && connectedCount == 4 && chosenPartner != null ? _startGame : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC928),
                  foregroundColor: const Color(0xFF1B1608),
                  disabledBackgroundColor: Colors.white12,
                  disabledForegroundColor: Colors.white38,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('ابدأ اللعب', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
            const SizedBox(height: 8),
            const Text('الفريق الآخر: اللاعبان المتبقيان', style: TextStyle(color: Colors.white54, fontSize: 9)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              ChoiceChip(label: const Text('عشوائي'), selected: _dealMode == 'random', selectedColor: const Color(0xFFFFC928), onSelected: (_) => _selectDealMode('random')),
              ChoiceChip(label: const Text('قصّ الشدّة'), selected: _dealMode == 'cut', selectedColor: const Color(0xFFFFC928), onSelected: (_) => _selectDealMode('cut')),
              ChoiceChip(label: const Text('دفعات 4-3-3-3'), selected: _dealMode == 'batch_4333', selectedColor: const Color(0xFFFFC928), onSelected: (_) => _selectDealMode('batch_4333')),
            ]),
          ] else ...[
            Text(
              chosenPartner == null
                ? 'بانتظار صاحب الطاولة لاختيار شريكه'
                : 'شريك صاحب الطاولة: ${_playerName(chosenPartner)}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
            const SizedBox(height: 5),
            const Text('سيبدأ اللعب عندما يضغط صاحب الطاولة على ابدأ اللعب', textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 9)),
          ],
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
        backgroundColor: const Color(0xFF151515),
        body: SafeArea(
          child: Column(children: [
            Container(
              height: 51,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              decoration: BoxDecoration(
                color: const Color(0xEE111111),
                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(.10))),
              ),
              child: Row(children: [
                IconButton(
                  onPressed: _openSettings,
                  icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 25),
                  tooltip: 'القائمة',
                ),
                IconButton(
                  onPressed: _openReportDialog,
                  icon: const Icon(Icons.flag_outlined, color: Colors.white70, size: 21),
                  tooltip: 'إبلاغ',
                ),
                Expanded(child: InkWell(
                  onTap: _copyCode,
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('طرنيب • ' + widget.roomCode,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                    Text('الهدف ' + _target.toString() + ' • ' + _scores[0].toString() + ' - ' + _scores[1].toString(),
                      style: const TextStyle(color: Colors.white54, fontSize: 10)),
                  ]),
                )),
                if (_status == 'playing' && ['playing', 'bidding', 'trump_selection'].contains(_phase))
                  Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: _secondsLeft <= 5 ? const Color(0x553D1010) : const Color(0x332A2412),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: _secondsLeft <= 5 ? Colors.redAccent : const Color(0x66FFD34F)),
                    ),
                    child: Text(_secondsLeft.toString() + ' ث',
                      style: TextStyle(color: _secondsLeft <= 5 ? Colors.redAccent : const Color(0xFFFFD34F), fontWeight: FontWeight.w900)),
                  ),
                IconButton(onPressed: _copyCode, icon: const Icon(Icons.copy_rounded, color: Color(0xFFFFD34F), size: 19)),
              ]),
            ),
            if (_disconnected)
              Container(
                width: double.infinity,
                color: Colors.orange.shade900,
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: const Text('الاتصال منقطع — نحاول إعادة الاتصال بالطاولة...',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 10)),
              ),
            Expanded(
              child: Stack(children: [
                Positioned.fill(child: _centerTable()),
                if (_debugHandsVisible)
                  Align(alignment: Alignment.center, child: _debugHandsOverlay()),
                if (_status == 'waiting' || _phase == 'cutting' || _phase == 'round_result' || _status == 'finished')
                  Align(
                    alignment: Alignment.center,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: _waitingOrResult(),
                    ),
                  )
                else if (_phase == 'bidding')
                  Align(
                    alignment: Alignment.center,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 305),
                      child: _biddingPanel(),
                    ),
                  )
                else if (_phase == 'trump_selection')
                  Align(
                    alignment: Alignment.center,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: _trumpSelectionPanel(),
                    ),
                  ),
              ]),
            ),
            if (_hand.isNotEmpty && _status == 'playing') _handArea(),
            Container(
              height: 104,
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
              decoration: BoxDecoration(
                color: const Color(0xF0101110),
                border: Border(top: BorderSide(color: Colors.white.withOpacity(.09))),
              ),
              child: Row(
                textDirection: TextDirection.ltr,
                children: [
                  SizedBox(
                    width: 116,
                    child: Row(children: [
                      Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF252525),
                            border: Border.all(color: const Color(0xFFFFC928), width: 2.5),
                            boxShadow: const [BoxShadow(color: Color(0x55FFC928), blurRadius: 9)],
                          ),
                          alignment: Alignment.center,
                          child: Text(_playerAvatar(_mySeat), style: const TextStyle(fontSize: 27)),
                        ),
                        const SizedBox(height: 2),
                        SizedBox(
                          width: 72,
                          child: Text(widget.playerName, maxLines: 1, overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70, fontSize: 9)),
                        ),
                      ]),
                      const SizedBox(width: 5),
                      InkWell(
                        onTap: _openReactions,
                        borderRadius: BorderRadius.circular(9),
                        child: const Padding(
                          padding: EdgeInsets.all(5),
                          child: Icon(Icons.chat_bubble_rounded, color: Colors.white70, size: 25),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Directionality(
                      textDirection: TextDirection.rtl,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _footerInfoBar(
                            label: 'أكلات',
                            value: _tricks.length > _myTeam ? _tricks[_myTeam].toString() : '0',
                          ),
                          const SizedBox(height: 5),
                          _footerInfoBar(
                            label: 'طلب',
                            value: bid == null ? '—' : bid['amount'].toString() + (bid['symbol'] == null ? '' : ' ' + bid['symbol'].toString()),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
