import 'package:flutter/material.dart';

class AppState extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.dark;

  String topImageText = 'SUBASTA';
  String bottomImageTextLine1 = 'PUJA MÍNIMA';
  String bottomImageTextLine2 = r'$5 PESO';

  String auctionPostTemplate = '''
SUBASTA DE \$5 PESO

INICIA
{diaHoy} de {mesHoy}

TERMINA
{diaManana} de {mesManana} a las 9:00 PM

Puja mínima \$5 Peso
Se puja por foto
Los ganadores serán notificados por inbox

En caso de no concretar se puede depositar para apartar la subasta para la próxima semana

Entregas:
Mundo Divertido
Domingo 10:00 AM - 11:00 AM

Game Hunters
Martes a Domingo
1:00 PM - 6:00 PM
''';

  void toggleTheme(bool isDark) {
    themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  void updateImageTexts({
    required String top,
    required String bottom1,
    required String bottom2,
  }) {
    topImageText = top.trim().isEmpty ? 'SUBASTA' : top.trim();
    bottomImageTextLine1 = bottom1.trim().isEmpty
        ? 'PUJA MÍNIMA'
        : bottom1.trim();
    bottomImageTextLine2 = bottom2.trim().isEmpty ? r'$5 PESO' : bottom2.trim();
    notifyListeners();
  }

  void updateAuctionTemplate(String value) {
    if (value.trim().isEmpty) return;
    auctionPostTemplate = value;
    notifyListeners();
  }
}
