import 'dart:convert';

import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/rng.dart';

/// Blok Kaydırma: her blok kendi sırasında yana kayar. Hamleden sonra
/// bloklar düşer, dolan sıralar silinir ve alttan yeni bir sıra yükselir.
/// y = 0 en alt sıradır.

const int kSlideCols = 8;
const int kSlideRows = 10;

class SBlock {
  int x, y;
  final int w;
  final int color;
  SBlock(this.x, this.y, this.w, this.color);
  SBlock copy() => SBlock(x, y, w, color);
  List<int> toJson() => [x, y, w, color];
}

class SlideLevel {
  final List<List<int>> start; // [x, y, w, renk]
  final int target; // silinecek sıra; 0 = hedefsiz
  final int seed;
  final int difficulty;
  final bool zen;
  final int timeLimit;
  final int aiMoves;
  final int moveLimit;

  const SlideLevel({
    required this.start,
    required this.target,
    required this.seed,
    required this.difficulty,
    required this.zen,
    required this.timeLimit,
    this.aiMoves = 0,
    this.moveLimit = 0,
  });

  SlideLevel withAi(int ai, int limit) => SlideLevel(
        start: start,
        target: target,
        seed: seed,
        difficulty: difficulty,
        zen: zen,
        timeLimit: timeLimit,
        aiMoves: ai,
        moveLimit: limit,
      );
}

/// Bir sıra üretir: en az bir boşluk ve en az iki blok.
List<SBlock> makeRow(SeededRandom r, int difficulty, int y) {
  for (var tries = 0; tries < 50; tries++) {
    final out = <SBlock>[];
    var x = 0;
    var gaps = 0;
    final gapChance = (0.32 - difficulty * 0.015).clamp(0.14, 0.32);
    while (x < kSlideCols) {
      if (r.chance(gapChance)) {
        x++;
        gaps++;
        continue;
      }
      final maxW = (kSlideCols - x).clamp(1, 4);
      final w = 1 + r.nextInt(maxW);
      out.add(SBlock(x, y, w, 1 + r.nextInt(8)));
      x += w;
    }
    final used = out.fold<int>(0, (a, b) => a + b.w);
    if (gaps >= 1 && used < kSlideCols && out.length >= 2) return out;
  }
  return [SBlock(0, y, 2, 1), SBlock(3, y, 3, 2), SBlock(7, y, 1, 3)];
}

SlideLevel generateSlideLevel(LevelSpec spec) {
  final r = SeededRandom(mixSeed([spec.seed, 3131]));
  final d = spec.difficulty.clamp(1, 10);
  final zen = spec.mode == GameModeId.zen;
  final endless = zen || spec.mode == GameModeId.endless || spec.mode == GameModeId.timeAttack;
  final rows = endless ? 3 : (3 + d ~/ 3).clamp(3, 6);
  final g = SlideGame.empty(seed: spec.seed, difficulty: d);
  for (var y = 0; y < rows; y++) {
    g.blocks.addAll(makeRow(r, d, y));
  }
  g.settle(scoreIt: false);
  return SlideLevel(
    start: [for (final b in g.blocks) b.toJson()],
    target: endless ? 0 : 3 + d * 2,
    seed: spec.seed,
    difficulty: d,
    zen: zen,
    timeLimit: spec.mode == GameModeId.timeAttack ? 120 : (spec.has('timer') ? 150 + (10 - d) * 15 : 0),
  );
}

class SlideStep {
  final int lines;
  final int points;
  const SlideStep(this.lines, this.points);
}

class SlideGame {
  final SlideLevel? level;
  final int seed;
  final int difficulty;
  List<SBlock> blocks = [];
  List<SBlock> next = [];
  late SeededRandom _rng;
  int _rowsMade = 0;
  int score = 0, lines = 0, moves = 0, combo = 0, bestCombo = 0;
  bool lost = false;

  /// Son hamlede silinen sıralar (boyama için).
  List<int> lastCleared = const [];

  SlideGame(SlideLevel l)
      : level = l,
        seed = l.seed,
        difficulty = l.difficulty {
    blocks = [for (final b in l.start) SBlock(b[0], b[1], b[2], b[3])];
    _rng = SeededRandom(mixSeed([seed, 7171]));
    _nextRow();
  }

  SlideGame.empty({required this.seed, required this.difficulty}) : level = null {
    _rng = SeededRandom(mixSeed([seed, 7171]));
  }

  void _nextRow() {
    _rowsMade++;
    next = makeRow(_rng, difficulty, -1);
  }

  SlideGame clone() {
    final g = SlideGame.empty(seed: seed, difficulty: difficulty);
    g.blocks = [for (final b in blocks) b.copy()];
    g.next = [for (final b in next) b.copy()];
    g._rng = _rng.copy();
    g._rowsMade = _rowsMade;
    g.score = score;
    g.lines = lines;
    g.moves = moves;
    g.combo = combo;
    return g;
  }

  /// Hücre -> blok numarası, boşsa -1.
  List<int> occupancy() {
    final occ = List<int>.filled(kSlideCols * (kSlideRows + 2), -1);
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (b.y < 0 || b.y >= kSlideRows + 2) continue;
      for (var k = 0; k < b.w; k++) {
        occ[b.y * kSlideCols + b.x + k] = i;
      }
    }
    return occ;
  }

  int blockAt(int x, int y) {
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (b.y == y && x >= b.x && x < b.x + b.w) return i;
    }
    return -1;
  }

  /// Bloğun kendi sırasında kayabileceği en sol ve en sağ x.
  (int, int) range(int i) {
    final b = blocks[i];
    var lo = 0, hi = kSlideCols - b.w;
    for (final o in blocks) {
      if (identical(o, b) || o.y != b.y) continue;
      if (o.x + o.w <= b.x) {
        if (o.x + o.w > lo) lo = o.x + o.w;
      } else if (o.x >= b.x + b.w) {
        if (o.x - b.w < hi) hi = o.x - b.w;
      }
    }
    return (lo, hi);
  }

  bool get won => level != null && level!.target > 0 && lines >= level!.target;
  bool get outOfMoves => level != null && level!.moveLimit > 0 && moves >= level!.moveLimit;
  bool get over => lost || won || outOfMoves;

  int get height {
    var h = 0;
    for (final b in blocks) {
      if (b.y + 1 > h) h = b.y + 1;
    }
    return h;
  }

  bool _fall() {
    var moved = false;
    blocks.sort((a, b) => a.y - b.y);
    final occ = occupancy();
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      while (b.y > 0) {
        var free = true;
        for (var k = 0; k < b.w; k++) {
          if (occ[(b.y - 1) * kSlideCols + b.x + k] != -1) {
            free = false;
            break;
          }
        }
        if (!free) break;
        for (var k = 0; k < b.w; k++) {
          occ[b.y * kSlideCols + b.x + k] = -1;
          occ[(b.y - 1) * kSlideCols + b.x + k] = i;
        }
        b.y--;
        moved = true;
      }
    }
    return moved;
  }

  /// Düşür ve sil, kararlı olana dek. Silinen sıra sayısını döner.
  int settle({bool scoreIt = true}) {
    var total = 0;
    final cleared = <int>[];
    _fall();
    while (true) {
      final width = List<int>.filled(kSlideRows + 2, 0);
      for (final b in blocks) {
        if (b.y >= 0 && b.y < width.length) width[b.y] += b.w;
      }
      final full = [for (var y = 0; y < width.length; y++) if (width[y] == kSlideCols) y];
      if (full.isEmpty) break;
      blocks.removeWhere((b) => full.contains(b.y));
      total += full.length;
      cleared.addAll(full);
      if (scoreIt) {
        combo++;
        if (combo > bestCombo) bestCombo = combo;
        score += full.length * 100 * full.length + (combo - 1) * 40;
      }
      _fall();
    }
    if (scoreIt) lastCleared = cleared;
    return total;
  }

  /// Bir bloğu [nx] konumuna kaydırır; ardından düşme, silme ve yükselme.
  SlideStep? move(int i, int nx) {
    if (over || i < 0 || i >= blocks.length) return null;
    final (lo, hi) = range(i);
    if (nx == blocks[i].x || nx < lo || nx > hi) return null;
    blocks[i].x = nx;
    moves++;
    final before = score;
    combo = 0;
    var n = settle();
    // Alttan yeni sıra yükselir.
    for (final b in blocks) {
      b.y++;
    }
    for (final b in next) {
      b.y = 0;
      blocks.add(b);
    }
    _nextRow();
    n += settle();
    lines += n;
    if (blocks.any((b) => b.y >= kSlideRows)) {
      if (level?.zen ?? false) {
        blocks.removeWhere((b) => b.y >= kSlideRows ~/ 2);
      } else {
        lost = true;
      }
    }
    return SlideStep(n, score - before);
  }

  /// Bütün olası hamleler: (blok, yeni x).
  List<(int, int)> legalMoves() {
    final out = <(int, int)>[];
    for (var i = 0; i < blocks.length; i++) {
      final (lo, hi) = range(i);
      for (var x = lo; x <= hi; x++) {
        if (x != blocks[i].x) out.add((i, x));
      }
    }
    return out;
  }

  (int, int)? bestMove() {
    (int, int)? best;
    var bestV = -1e18;
    for (final m in legalMoves()) {
      final g = clone();
      final s = g.move(m.$1, m.$2);
      if (s == null) continue;
      final v = (g.lost ? -1e6 : 0) + s.lines * 1000.0 - g.height * 40 - _roughness(g) * 3 + _nearFull(g) * 12 - m.$1 * 0.001;
      if (v > bestV) {
        bestV = v;
        best = m;
      }
    }
    return best;
  }

  static double _roughness(SlideGame g) {
    final width = List<int>.filled(kSlideRows + 2, 0);
    for (final b in g.blocks) {
      if (b.y >= 0 && b.y < width.length) width[b.y] += b.w;
    }
    var gaps = 0;
    for (var y = 0; y < kSlideRows; y++) {
      if (width[y] > 0) gaps += kSlideCols - width[y];
    }
    return gaps.toDouble();
  }

  static double _nearFull(SlideGame g) {
    final width = List<int>.filled(kSlideRows + 2, 0);
    for (final b in g.blocks) {
      if (b.y >= 0 && b.y < width.length) width[b.y] += b.w;
    }
    var v = 0.0;
    for (final w in width) {
      if (w == kSlideCols - 1) v += 2;
      if (w == kSlideCols - 2) v += 1;
    }
    return v;
  }

  String serialize() => jsonEncode({
        'b': [for (final b in blocks) b.toJson()],
        'n': [for (final b in next) b.toJson()],
        'r': _rowsMade,
        's': [score, lines, moves, combo, bestCombo, lost ? 1 : 0],
      });

  static SlideGame restore(SlideLevel l, String snap) {
    final g = SlideGame(l);
    final j = jsonDecode(snap) as Map<String, dynamic>;
    List<SBlock> read(String k) => [
          for (final e in j[k] as List)
            SBlock((e[0] as num).toInt(), (e[1] as num).toInt(), (e[2] as num).toInt(), (e[3] as num).toInt())
        ];
    g.blocks = read('b');
    final made = (j['r'] as num).toInt();
    g._rng = SeededRandom(mixSeed([l.seed, 7171]));
    g._rowsMade = 0;
    while (g._rowsMade < made) {
      g._nextRow();
    }
    g.next = read('n');
    final s = [for (final v in j['s'] as List) (v as num).toInt()];
    g
      ..score = s[0]
      ..lines = s[1]
      ..moves = s[2]
      ..combo = s[3]
      ..bestCombo = s[4]
      ..lost = s[5] == 1;
    return g;
  }
}

int simulateSlideLevel(SlideLevel l, {int maxMoves = 150}) {
  final g = SlideGame(l);
  while (g.moves < maxMoves && !g.won && !g.lost) {
    final m = g.bestMove();
    if (m == null) return -1;
    g.move(m.$1, m.$2);
  }
  return g.won ? g.moves : -1;
}
