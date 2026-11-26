import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/core/strings.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/app/studio_ui.dart';

import 'slide_engine.dart';
import 'slide_rules.dart';

final Map<StudioLook, ThemeData> _studioThemes = {};

/// Oyun ekranı: düğmeler, çipler, üst bilgi ve pencereler onaylı koyu
/// tasarımda (merkezin paleti, studio-core StudioLook); tahta çizimi kendi
/// renklerini korur.
class SlideView extends StatelessWidget {
  final PlayContext ctx;
  const SlideView({super.key, required this.ctx});

  @override
  Widget build(BuildContext context) {
    final look = StudioLook.of(context);
    return Theme(data: _studioThemes[look] ??= buildStudioTheme(look), child: SlideViewBody(ctx: ctx));
  }
}

class SlideViewBody extends StatefulWidget {
  final PlayContext ctx;
  const SlideViewBody({super.key, required this.ctx});

  @override
  State<SlideViewBody> createState() => _SlideViewState();
}

class _SlideViewState extends State<SlideViewBody> {
  late SlideLevel level;
  late SlideGame game;
  int? _drag;
  double _dx = 0;
  (int, int)? _hint;
  int _seconds = 0, _hints = 0;
  Timer? _timer;
  bool _ended = false;
  double _cell = 30;

  PlayContext get ctx => widget.ctx;

  @override
  void initState() {
    super.initState();
    level = SlideRules().finalize(ctx.generated as GeneratedLevel<SlideLevel>);
    final snap = ctx.resume['snap'];
    game = snap is String ? SlideGame.restore(level, snap) : SlideGame(level);
    _seconds = (ctx.resume['secs'] as num?)?.toInt() ?? 0;
    _hints = (ctx.resume['hints'] as num?)?.toInt() ?? 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_ended || !mounted) return;
      setState(() => _seconds++);
      if (level.timeLimit > 0 && _seconds >= level.timeLimit) _end();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _persist() => ctx.saveResume({'snap': game.serialize(), 'secs': _seconds, 'hints': _hints});

  void _move(int i, int nx) {
    final s = game.move(i, nx);
    if (s == null) return;
    ctx.sfx(s.lines > 1 ? Sfx.combo : (s.lines == 1 ? Sfx.clear : Sfx.place));
    setState(() => _hint = null);
    _persist();
    if (game.over || game.legalMoves().isEmpty) _end();
  }

  void _end() {
    if (_ended) return;
    _ended = true;
    _timer?.cancel();
    final goal = level.target > 0;
    final won = goal ? game.won : game.score > 0;
    ctx.sfx(won ? Sfx.win : Sfx.lose);
    final stars = goal
        ? SlideRules.stars(game)
        : (game.score >= 3000 ? 3 : game.score >= 1000 ? 2 : game.score > 0 ? 1 : 0);
    ctx.finish(RoundResult(
      won: won,
      score: game.score,
      stars: won ? stars : 0,
      seconds: _seconds,
      moves: game.moves,
      hintsUsed: _hints,
      undosUsed: 0,
      gameStats: {'lines_cleared': game.lines, 'combos': game.bestCombo, 'slides': game.moves},
    ));
  }

  Future<void> _useHint() async {
    if (!await ctx.requestHint()) return;
    _hints++;
    setState(() => _hint = game.bestMove());
    _persist();
  }

  int? _blockAtLocal(Offset p) {
    final x = (p.dx / _cell).floor();
    final y = kSlideRows - 1 - (p.dy / _cell).floor();
    if (x < 0 || x >= kSlideCols || y < 0 || y >= kSlideRows) return null;
    final i = game.blockAt(x, y);
    return i < 0 ? null : i;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      _cell = math.max(12.0, math.min((cons.maxWidth - 24) / kSlideCols, (cons.maxHeight * 0.72) / (kSlideRows + 1.4)));
      final w = _cell * kSlideCols, h = _cell * kSlideRows;
      return Column(children: [
        _hud(),
        const SizedBox(height: 6),
        Center(
          child: GestureDetector(
            onHorizontalDragStart: _ended
                ? null
                : (d) => setState(() {
                      _drag = _blockAtLocal(d.localPosition);
                      _dx = 0;
                    }),
            onHorizontalDragUpdate: (d) {
              if (_drag == null) return;
              setState(() => _dx += d.delta.dx);
            },
            onHorizontalDragEnd: (_) {
              final i = _drag;
              if (i == null) return;
              final b = game.blocks[i];
              final (lo, hi) = game.range(i);
              final nx = (b.x + (_dx / _cell).round()).clamp(lo, hi);
              setState(() {
                _drag = null;
                _dx = 0;
              });
              if (nx != b.x) {
                _move(i, nx);
              } else {
                ctx.sfx(Sfx.tap);
              }
            },
            child: Semantics(
              label: 'board',
              child: SizedBox(width: w, height: h, child: CustomPaint(painter: _Painter(this))),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(width: w, height: _cell * 0.9, child: CustomPaint(painter: _NextPainter(this))),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: IconButton.filledTonal(
              onPressed: _ended ? null : _useHint, icon: const Icon(Icons.lightbulb), tooltip: ctx.t('hint')),
        ),
      ]);
    });
  }

  Widget _hud() {
    final goal = level.target;
    final label = goal == 0
        ? (Strings.tx(ctx.lang, 'Puan: {0}', 'Score: {0}', [game.score]))
        : (Strings.tx(ctx.lang, 'Sıra: {0} / {1}', 'Lines: {0} / {1}', [game.lines, goal]));
    final left = level.moveLimit > 0 ? level.moveLimit - game.moves : null;
    final secs = level.timeLimit > 0 ? (level.timeLimit - _seconds).clamp(0, 9999) : _seconds;
    String two(int x) => x.toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            if (goal > 0) ...[
              const SizedBox(height: 4),
              LinearProgressIndicator(value: (game.lines / goal).clamp(0, 1).toDouble()),
            ],
          ]),
        ),
        if (left != null) ...[const SizedBox(width: 10), const Icon(Icons.swap_horiz, size: 18), Text(' $left')],
        const SizedBox(width: 10),
        const Icon(Icons.timer_outlined, size: 18),
        Text(' ${secs ~/ 60}:${two(secs % 60)}'),
      ]),
    );
  }

  Color colorOf(int c) => ctx.pieceColors[(c - 1) % ctx.pieceColors.length];
}

void _block(Canvas c, Rect r, Color col, {double alpha = 1, String? mark, double cell = 30}) {
  final rr = RRect.fromRectAndRadius(r.deflate(2.5), Radius.circular(cell * 0.28));
  c.drawRRect(rr, Paint()..color = col.withValues(alpha: alpha));
  c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(r.left + 6, r.top + 5, r.width - 12, r.height * 0.26), Radius.circular(cell * 0.14)),
      Paint()..color = Colors.white.withValues(alpha: 0.2 * alpha));
  if (mark != null) {
    final tp = TextPainter(
      text: TextSpan(text: mark, style: TextStyle(fontSize: cell * 0.45, color: Colors.black.withValues(alpha: 0.45))),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, r.center - Offset(tp.width / 2, tp.height / 2));
  }
}

class _Painter extends CustomPainter {
  final _SlideViewState v;
  _Painter(this.v);

  @override
  void paint(Canvas canvas, Size size) {
    final cell = v._cell;
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)),
        Paint()..color = Colors.black.withValues(alpha: 0.12));
    final line = Paint()..color = Colors.white.withValues(alpha: 0.05);
    for (var x = 1; x < kSlideCols; x++) {
      canvas.drawLine(Offset(x * cell, 0), Offset(x * cell, size.height), line);
    }
    // Tehlike çizgisi: en üst iki sıra.
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, cell * 2), Paint()..color = Colors.red.withValues(alpha: 0.06));
    final g = v.game;
    for (var i = 0; i < g.blocks.length; i++) {
      final b = g.blocks[i];
      var left = b.x * cell;
      if (v._drag == i) {
        final (lo, hi) = g.range(i);
        left = (left + v._dx).clamp(lo * cell, hi * cell);
      }
      final r = Rect.fromLTWH(left, (kSlideRows - 1 - b.y) * cell, b.w * cell, cell);
      _block(canvas, r, v.colorOf(b.color),
          mark: v.ctx.colorBlind ? v.ctx.symbol(b.color - 1) : null, cell: cell, alpha: v._drag == i ? 0.85 : 1);
    }
    final h = v._hint;
    if (h != null && h.$1 < g.blocks.length) {
      final b = g.blocks[h.$1];
      final r = Rect.fromLTWH(h.$2 * cell, (kSlideRows - 1 - b.y) * cell, b.w * cell, cell);
      canvas.drawRRect(
          RRect.fromRectAndRadius(r.deflate(2), Radius.circular(cell * 0.28)),
          Paint()
            ..color = Colors.amber
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _NextPainter extends CustomPainter {
  final _SlideViewState v;
  _NextPainter(this.v);

  @override
  void paint(Canvas canvas, Size size) {
    final cell = v._cell;
    for (final b in v.game.next) {
      _block(canvas, Rect.fromLTWH(b.x * cell, 0, b.w * cell, size.height), v.colorOf(b.color), alpha: 0.35, cell: cell);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
