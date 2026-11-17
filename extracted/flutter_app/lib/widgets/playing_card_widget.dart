import 'package:flutter/material.dart';
import '../models/game_models.dart';

class PlayingCardWidget extends StatelessWidget {
  final PlayingCardModel card;
  final bool isMini;
  final bool isPlayable;
  final VoidCallback? onTap;

  const PlayingCardWidget({
    super.key,
    required this.card,
    this.isMini = false,
    this.isPlayable = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color suitColor =
        card.suit.isRed ? const Color(0xFFD32F2F) : const Color(0xFF1B1B1B);
    final double width = isMini ? 28.0 : 60.0;
    final double height = isMini ? 40.0 : 88.0;

    return GestureDetector(
      onTap: isPlayable ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isPlayable ? 1.0 : 0.55,
        child: Container(
          width: width,
          height: height,
          margin: EdgeInsets.symmetric(horizontal: isMini ? 1.2 : 2.5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(isMini ? 4.0 : 8.0),
            border: Border.all(
              color: Colors.grey.shade400,
              width: isMini ? 0.6 : 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
                blurRadius: isMini ? 2 : 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: isMini
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      card.rankLabel,
                      style: TextStyle(
                        color: suitColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                      ),
                    ),
                    Text(
                      card.suit.symbol,
                      style: TextStyle(
                        color: suitColor,
                        fontSize: 11,
                        height: 1.0,
                      ),
                    ),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.all(5.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${card.rankLabel}\n${card.suit.symbol}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: suitColor,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          height: 1.05,
                        ),
                      ),
                      Center(
                        child: Text(
                          card.suit.symbol,
                          style: TextStyle(color: suitColor, fontSize: 22),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Text(
                          card.rankLabel,
                          style: TextStyle(
                            color: suitColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
