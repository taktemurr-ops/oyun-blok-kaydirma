/// Blok Kaydırma: blokları kendi sıralarında yana kaydır, sıraları tamamla.
/// Blok Oyunları merkez uygulamasının oyunu.
library;

import 'package:flutter/material.dart';
import 'package:studio_core/app/game_api.dart';

import 'src/slide_rules.dart';
import 'src/slide_view.dart';

export 'src/slide_engine.dart';
export 'src/slide_rules.dart';

final blokKaydirmaConfig = GameConfig(
  gameId: blokKaydirmaId,
  title: const ['Blok Kaydırma', 'Block Slide', 'Block-Schieben', 'Desliza Bloques', 'Glisse Blocs'],
  tagline: const [
    'Kaydır, düşür, sırayı tamamla!',
    'Slide, drop, complete the row!',
    'Schieben, fallen lassen, Reihe füllen!',
    '¡Desliza, deja caer y completa la fila!',
    'Glissez, laissez tomber, complétez la ligne !',
  ],
  seedColor: const Color(0xFF5E35B1),
  icon: Icons.swap_horiz_rounded,
  rules: SlideRules(),
  buildPlay: (ctx) => SlideView(ctx: ctx),
  tutorial: const [
    TutorialStep(Icons.swipe, [
      'Bir bloğu parmağınla sağa ya da sola kaydır. Boşluğa denk gelen bloklar aşağı düşer.',
      'Slide a block left or right. Blocks over a gap fall down.',
      'Schiebe einen Block nach links oder rechts. Blöcke über Lücken fallen.',
      'Desliza un bloque a los lados. Los bloques sobre huecos caen.',
      'Glissez un bloc à gauche ou à droite. Les blocs au-dessus d\'un vide tombent.',
    ]),
    TutorialStep(Icons.vertical_align_top, [
      'Her hamleden sonra alttan yeni bir sıra gelir. Dolan sıralar silinir; tepeye ulaşma!',
      'After each move a new row rises. Full rows clear; don\'t reach the top!',
      'Nach jedem Zug steigt eine Reihe auf. Volle Reihen verschwinden.',
      'Tras cada movimiento sube una fila. Las filas llenas desaparecen.',
      'Après chaque coup une ligne monte. Les lignes pleines disparaissent.',
    ]),
  ],
);
