import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'strategy_colors.dart';

/// Browser tabs cannot always lock rotation. Offer a dismissible hint without
/// shrinking the game viewport, rotating its controls, or blocking interaction.
class LandscapePlayHint extends StatefulWidget {
  const LandscapePlayHint({
    super.key,
    required this.child,
    this.enabled = kIsWeb,
  });

  final Widget child;
  final bool enabled;

  @override
  State<LandscapePlayHint> createState() => _LandscapePlayHintState();
}

class _LandscapePlayHintState extends State<LandscapePlayHint> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final show = widget.enabled && size.height > size.width && !_dismissed;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (show)
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Material(
                    key: const Key('landscape-play-hint'),
                    color: strategyPanel,
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: strategyLine),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                      child: Row(
                        children: [
                          const ExcludeSemantics(
                            child: Icon(
                              Icons.screen_rotation_outlined,
                              color: strategyBlue,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Semantics(
                              liveRegion: true,
                              child: const Text(
                                '横向きで遊ぶと見やすくなります',
                                style: TextStyle(
                                  color: strategyText,
                                  fontSize: 14,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ),
                          Semantics(
                            container: true,
                            label: '横向きの案内を閉じる',
                            child: IconButton(
                              key: const Key('dismiss-landscape-hint'),
                              onPressed: () =>
                                  setState(() => _dismissed = true),
                              icon: const Icon(
                                Icons.close,
                                color: strategyMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
