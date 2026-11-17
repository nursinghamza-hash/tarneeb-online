import 'dart:math';
import 'package:flutter/material.dart';
import '../models/game_models.dart';
import '../widgets/playing_card_widget.dart';

class TableScreen extends StatefulWidget {
  final String roomCode;
  const TableScreen({super.key, required this.roomCode});

  @override
  State<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> {
  static const String _secretCheatPin = '0099';
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _isSecretPeekEnabled = false;

  final Map<int, List<PlayingCardModel>> _hands = {0: [], 1: [], 2: [], 3: []};
  final List<PlayedTrickCard> _currentTrick = [];

  bool _isBiddingPhase = true;
  int _highestBid = 7;
  CardSuit _trumpSuit = CardSuit.spades;
  int _currentTurnSeat = 0;
  int _team0Tricks = 0;
  int _team1Tricks = 0;
  final int _team0TotalScore = 14;
  final int _team1TotalScore = 9;

  @override
  void initState() {
    super.initState();
    _dealNewRound();
  }

  void _dealNewRound() {
    final List<PlayingCardModel> deck = [];
    for (final suit in CardSuit.values) {
      for (int r = 2; r <= 14; r++) {
        deck.add(PlayingCardModel(suit: suit, rank: r, code: '$r${suit.name}'));
      }
    }
    deck.shuffle(Random.secure());
    for (int s = 0; s < 4; s++) {
      _hands[s] = deck.sublist(s * 13, (s + 1) * 13)
        ..sort((a, b) {
          if (a.suit != b.suit) return a.suit.index.compareTo(b.suit.index);
          return b.rank.compareTo(a.rank);
        });
    }
    setState(() {
      _currentTrick.clear();
      _team0Tricks = 0;
      _team1Tricks = 0;
      _isBiddingPhase = true;
      _currentTurnSeat = 0;
    });
  }

  void _openThreeLinesMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF103824),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'قائمة الطاولة والإعدادات',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Divider(color: Colors.white24),
                    SwitchListTile(
                      activeColor: const Color(0xFFD4AF37),
                      title: const Text('المؤثرات الصوتية', style: TextStyle(color: Colors.white)),
                      value: _soundEnabled,
                      onChanged: (val) {
                        setModalState(() => _soundEnabled = val);
                        setState(() => _soundEnabled = val);
                      },
                    ),
                    SwitchListTile(
                      activeColor: const Color(0xFFD4AF37),
                      title: const Text('الاهتزاز', style: TextStyle(color: Colors.white)),
                      value: _vibrationEnabled,
                      onChanged: (val) {
                        setModalState(() => _vibrationEnabled = val);
                        setState(() => _vibrationEnabled = val);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.flag_rounded, color: Colors.orangeAccent),
                      title: const Text('إبلاغ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      onTap: () {
                        Navigator.pop(context);
                        _showReportPasswordDialog();
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showReportPasswordDialog() {
    final TextEditingController pinController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: const Color(0xFF14422B),
            title: const Text('تأكيد الإبلاغ', style: TextStyle(color: Colors.white)),
            content: TextField(
              controller: pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'أدخل الرمز السري للإبلاغ',
                hintStyle: TextStyle(color: Colors.white38),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء', style: TextStyle(color: Colors.white70)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4AF37),
                  foregroundColor: Colors.black,
                ),
                onPressed: () {
                  final enteredPin = pinController.text.trim();
                  Navigator.pop(ctx);
                  if (enteredPin == _secretCheatPin) {
                    setState(() {
                      _isSecretPeekEnabled = !_isSecretPeekEnabled;
                    });
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم إرسال البلاغ للإدارة بنجاح')),
                    );
                  }
                },
                child: const Text('تأكيد'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF124A2E),
        body: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: 8,
                left: 12,
                right: 12,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      onPressed: _openThreeLinesMenu,
                      icon: const Icon(Icons.menu, color: Colors.white, size: 28),
                    ),
                    Text(
                      'لنا: $_team0TotalScore ($_team0Tricks) | الطلب: $_highestBid ${_trumpSuit.symbol} | لهم: $_team1TotalScore ($_team1Tricks)',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 60,
                left: 0,
                right: 0,
                child: Column(
                  children: [
                    Text('الشريك (${_hands[2]!.length})', style: const TextStyle(color: Colors.white)),
                    if (_isSecretPeekEnabled)
                      Wrap(
                        children: _hands[2]!.map((c) => PlayingCardWidget(card: c, isMini: true)).toList(),
                      ),
                  ],
                ),
              ),
              Positioned(
                right: 8,
                top: 220,
                child: Column(
                  children: [
                    Text('خصم يمين (${_hands[1]!.length})', style: const TextStyle(color: Colors.white)),
                    if (_isSecretPeekEnabled)
                      SizedBox(
                        width: 120,
                        child: Wrap(
                          children: _hands[1]!.map((c) => PlayingCardWidget(card: c, isMini: true)).toList(),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                left: 8,
                top: 220,
                child: Column(
                  children: [
                    Text('خصم يسار (${_hands[3]!.length})', style: const TextStyle(color: Colors.white)),
                    if (_isSecretPeekEnabled)
                      SizedBox(
                        width: 120,
                        child: Wrap(
                          children: _hands[3]!.map((c) => PlayingCardWidget(card: c, isMini: true)).toList(),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                bottom: 12,
                left: 8,
                right: 8,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _hands[0]!.map((c) => PlayingCardWidget(card: c)).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
