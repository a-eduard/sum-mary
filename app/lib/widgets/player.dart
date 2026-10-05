import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// Плеер локального файла. Внешний код может перемотать через [PlayerController.seek].
class PlayerController {
  final player = AudioPlayer();
  Future<void> seek(int ms) async {
    await player.seek(Duration(milliseconds: ms));
    await player.resume();
  }
}

class AudioPlayerBar extends StatefulWidget {
  final String path;
  final PlayerController controller;
  const AudioPlayerBar({super.key, required this.path, required this.controller});
  @override
  State<AudioPlayerBar> createState() => _AudioPlayerBarState();
}

class _AudioPlayerBarState extends State<AudioPlayerBar> {
  AudioPlayer get _p => widget.controller.player;
  Duration _pos = Duration.zero, _dur = Duration.zero;
  PlayerState _state = PlayerState.stopped;
  double _rate = 1;

  @override
  void initState() {
    super.initState();
    _p.setSource(DeviceFileSource(widget.path));
    _p.onPositionChanged.listen((d) => mounted ? setState(() => _pos = d) : null);
    _p.onDurationChanged.listen((d) => mounted ? setState(() => _dur = d) : null);
    _p.onPlayerStateChanged.listen((s) => mounted ? setState(() => _state = s) : null);
  }

  @override
  void dispose() {
    _p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final max = _dur.inMilliseconds.toDouble();
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: SafeArea(
        top: false,
        child: Row(children: [
          IconButton.filled(
            onPressed: () => _state == PlayerState.playing ? _p.pause() : _p.resume(),
            icon: Icon(_state == PlayerState.playing ? Icons.pause : Icons.play_arrow),
          ),
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Slider(
                value: _pos.inMilliseconds.clamp(0, max <= 0 ? 0 : max).toDouble(),
                max: max <= 0 ? 1 : max,
                onChanged: (v) => _p.seek(Duration(milliseconds: v.round())),
              ),
              Text('${fmtMs(_pos.inMilliseconds)} / ${fmtMs(_dur.inMilliseconds)}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ]),
          ),
          TextButton(
            onPressed: () {
              _rate = _rate == 1 ? 1.5 : (_rate == 1.5 ? 2 : 1);
              _p.setPlaybackRate(_rate);
              setState(() {});
            },
            child: Text('${_rate == _rate.roundToDouble() ? _rate.toInt() : _rate}×'),
          ),
        ]),
      ),
    );
  }
}
