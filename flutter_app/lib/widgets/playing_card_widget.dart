import 'package:flutter/material.dart';
import '../models/game_models.dart';

class PlayingCardWidget extends StatelessWidget {
  final PlayingCardModel card;
  final bool isMini;
  final bool isCompact;
  final bool isHand;
  final bool isSelected;
  final bool isRecommended;
  final bool isPlayable;
  final bool isLegal;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final double? cardWidth;
  final double? cardHeight;

  const PlayingCardWidget({
    super.key,
    required this.card,
    this.isMini = false,
    this.isCompact = false,
    this.isHand = false,
    this.isSelected = false,
    this.isRecommended = false,
    this.isPlayable = true,
    this.isLegal = true,
    this.onTap,
    this.onDoubleTap,
    this.cardWidth,
    this.cardHeight,
  });

  @override
  Widget build(BuildContext context) {
    final Color suitColor = card.suit.isRed
        ? const Color(0xFFC51E2B)
        : const Color(0xFF17191D);

    final double width = cardWidth ?? (isMini ? 29 : (isCompact ? 42 : (isHand ? 64 : 62)));
    final double height = cardHeight ?? (isMini ? 41 : (isCompact ? 64 : (isHand ? 102 : 90)));
    final double baseWidth = isMini ? 29 : (isCompact ? 42 : (isHand ? 64 : 62));
    final double scale = width / baseWidth;
    final double rankFont = (isMini ? 8 : (isCompact ? 10 : (isHand ? 17 : 15))) * scale;
    final double suitFont = (isMini ? 8 : (isCompact ? 10 : (isHand ? 15 : 13))) * scale;
    final double centerFont = (isMini ? 14 : (isCompact ? 18 : (isHand ? 34 : 30))) * scale;

    Widget corner() => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          card.rankLabel,
          style: TextStyle(
            color: suitColor,
            fontSize: rankFont,
            fontWeight: FontWeight.w900,
            height: .92,
          ),
        ),
        Text(
          card.suit.symbol,
          style: TextStyle(
            color: suitColor,
            fontSize: suitFont,
            fontWeight: FontWeight.w800,
            height: .95,
          ),
        ),
      ],
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isPlayable && isLegal ? onTap : null,
      onDoubleTap: isPlayable && isLegal ? onDoubleTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: !isLegal ? .56 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: const Color(0xFFFFFEFC),
            borderRadius: BorderRadius.circular(isMini ? 4 : width * .095),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFFE2B94C)
                  : isRecommended ? const Color(0xFF10B981) : const Color(0xFFC9C9C9),
              width: (isSelected || isRecommended) ? 2 : .75,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity((isSelected || isRecommended) ? .38 : .24),
                blurRadius: (isSelected || isRecommended) ? 7 : 3,
                offset: Offset(0, (isSelected || isRecommended) ? 4 : 2),
              ),
              if (isSelected)
                const BoxShadow(color: Color(0x55E2B94C), blurRadius: 5),
              if (isRecommended)
                const BoxShadow(color: Color(0x5534D399), blurRadius: 7),
            ],
          ),
          child: Stack(
            children: [
              if (isRecommended && !isMini)
                Positioned(
                  top: -1,
                  left: 0,
                  right: 0,
                  child: Center(child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(color: const Color(0xFF10B981), borderRadius: BorderRadius.circular(5)),
                    child: const Text('★ اقتراح', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                  )),
                ),
              Positioned(left: width * .07, top: height * .045, child: corner()),
              Positioned(
                right: width * .07,
                bottom: height * .045,
                child: RotatedBox(quarterTurns: 2, child: corner()),
              ),
              Center(
                child: isMini
                    ? Text(
                        card.suit.symbol,
                        style: TextStyle(
                          color: suitColor,
                          fontSize: centerFont,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : Container(
                        width: width * .60,
                        height: height * .46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: suitColor.withOpacity(.035),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          card.suit.symbol,
                          style: TextStyle(
                            color: suitColor,
                            fontSize: centerFont,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
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
