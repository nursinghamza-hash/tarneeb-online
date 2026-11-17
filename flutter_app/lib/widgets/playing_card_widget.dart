import 'package:flutter/material.dart';
import '../models/game_models.dart';

class PlayingCardWidget extends StatelessWidget {
  final PlayingCardModel card;
  final bool isMini;
  final bool isCompact;
  final bool isPlayable;
  final bool isLegal;
  final VoidCallback? onTap;

  const PlayingCardWidget({
    super.key,
    required this.card,
    this.isMini = false,
    this.isCompact = false,
    this.isPlayable = true,
    this.isLegal = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color suitColor = card.suit.isRed
        ? const Color(0xFFD32F2F)
        : const Color(0xFF171717);
    final double width = isMini ? 29 : (isCompact ? 42 : 60);
    final double height = isMini ? 41 : (isCompact ? 64 : 88);
    final double cornerFont = isMini ? 9 : (isCompact ? 10 : 13);
    final double centerFont = isMini ? 13 : (isCompact ? 17 : 22);

    return GestureDetector(
      onTap: isPlayable && isLegal ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: !isLegal ? .28 : (isPlayable ? 1 : .62),
        child: Container(
          width: width,
          height: height,
          margin: EdgeInsets.symmetric(horizontal: isMini ? 1 : 0),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFEFA),
            borderRadius: BorderRadius.circular(isMini ? 4 : 6),
            border: Border.all(color: Colors.black26, width: .7),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(0, 2)),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(isMini ? 2 : 3),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${card.rankLabel}\n${card.suit.symbol}',
                  style: TextStyle(
                    color: suitColor,
                    fontSize: cornerFont,
                    fontWeight: FontWeight.w900,
                    height: .9,
                  ),
                ),
                Center(
                  child: Text(card.suit.symbol,
                    style: TextStyle(color: suitColor, fontSize: centerFont, height: 1)),
                ),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Text(card.rankLabel,
                    style: TextStyle(color: suitColor, fontSize: cornerFont - 1, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
