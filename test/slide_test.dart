import 'package:flutter_test/flutter_test.dart';
import 'package:oyun_blok_kaydirma/oyun_blok_kaydirma.dart';
import 'package:studio_core/core/level_plan.dart';

void main() {
  final rules = SlideRules();
  final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: rules.optionalMechanics);

  test('kaydırma, düşme ve sıra silme', () {
    final l = rules.build(planner.spec(1)).puzzle;
    final g = SlideGame(l);
    g.blocks = [SBlock(0, 0, 4, 1), SBlock(5, 0, 3, 2), SBlock(4, 1, 1, 3)];
    // 1 karelik blok zaten boşluğun üstünde: düşünce sıra dolar.
    final n = g.settle();
    expect(n, 1);
    expect(g.blocks, isEmpty);
    g.blocks = [SBlock(0, 0, 2, 1), SBlock(4, 0, 2, 2)];
    expect(g.range(0), (0, 2));
    expect(g.range(1), (2, 6));
  });

  test('kampanya bölümleri doğrulanır, hamle sınırı botun hamlesini kapsar', () {
    for (final lv in [1, 12, 50, 99, 230, 777, 2500, 9999, 33333, 49999]) {
      final gl = rules.build(planner.spec(lv));
      expect(gl.validation.ok, isTrue, reason: 'bölüm $lv: ${gl.validation.reason}');
      final l = rules.finalize(gl);
      final m = simulateSlideLevel(l);
      expect(m, greaterThan(0), reason: 'bölüm $lv');
      if (l.moveLimit > 0) expect(m, lessThanOrEqualTo(l.moveLimit));
    }
  });

  test('kayıt geri yüklenince oyun aynı devam eder', () {
    final l = rules.build(planner.spec(88)).puzzle;
    final g = SlideGame(l);
    for (var k = 0; k < 5; k++) {
      final m = g.bestMove();
      if (m == null) break;
      g.move(m.$1, m.$2);
    }
    final r = SlideGame.restore(l, g.serialize());
    expect(r.serialize(), g.serialize());
    final m = g.bestMove()!;
    g.move(m.$1, m.$2);
    r.move(m.$1, m.$2);
    expect(r.serialize(), g.serialize());
  });

  test('her kip üretilir', () {
    for (final m in rules.modes) {
      expect(rules.build(planner.spec(44, mode: m)).validation.ok, isTrue);
    }
  });
}
