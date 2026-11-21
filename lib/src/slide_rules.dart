import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';

import 'slide_engine.dart';

const blokKaydirmaId = 'oyun-blok-kaydirma';

class SlideRules extends GameRules<SlideLevel> {
  @override
  String get gameId => blokKaydirmaId;

  @override
  List<String> get optionalMechanics => const ['timer'];

  @override
  List<GameModeId> get modes => const [
        GameModeId.campaign,
        GameModeId.endless,
        GameModeId.timeAttack,
        GameModeId.zen,
        GameModeId.daily,
        GameModeId.weekly,
        GameModeId.challenge,
      ];

  @override
  List<GameStat> get gameStats => const [
        GameStat('lines_cleared', 'Silinen sıra', 'Lines cleared', scale: 10),
        GameStat('combos', 'Zincir', 'Chains', scale: 3),
        GameStat('slides', 'Kaydırma', 'Slides', scale: 50),
      ];

  @override
  List<MissionTemplate> get missionTemplates => const [
        MissionTemplate('lines', 'lines_cleared', [8, 20, 40]),
        MissionTemplate('combos', 'combos', [2, 4, 6]),
        MissionTemplate('slides', 'slides', [30, 80, 150]),
      ];

  @override
  SlideLevel generate(LevelSpec spec) => generateSlideLevel(spec);

  @override
  Validation validate(SlideLevel level, LevelSpec spec) {
    final g = SlideGame(level);
    final occ = <int>{};
    for (final b in g.blocks) {
      if (b.x < 0 || b.x + b.w > kSlideCols || b.y < 0 || b.y >= kSlideRows) {
        return const Validation.fail('block out of board');
      }
      for (var k = 0; k < b.w; k++) {
        if (!occ.add(b.y * kSlideCols + b.x + k)) return const Validation.fail('overlap');
      }
    }
    if (g.legalMoves().isEmpty) return const Validation.fail('no move');
    if (level.target == 0) return const Validation.ok();
    final m = simulateSlideLevel(level);
    if (m < 0) return const Validation.fail('AI could not solve');
    return Validation.ok(m);
  }

  SlideLevel finalize(GeneratedLevel<SlideLevel> g) {
    final l = g.puzzle;
    if (l.target == 0) return l;
    final ai = g.validation.metric;
    final slack = 2.4 - l.difficulty * 0.1;
    final limit = l.difficulty >= 4 ? (ai * slack).ceil() + 4 : 0;
    return l.withAi(ai, limit);
  }

  static int stars(SlideGame g) {
    if (!g.won) return 0;
    final ai = g.level!.aiMoves;
    if (ai <= 0 || g.moves <= ai + 2) return 3;
    if (g.moves <= (ai * 1.5).ceil() + 2) return 2;
    return 1;
  }
}
