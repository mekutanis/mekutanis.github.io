import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:async';
import 'dart:convert';
import 'firebase_options.dart';
import 'package:provider/provider.dart';
import 'auth_service.dart';
import 'auth_screen.dart';
import 'game_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scrabble Online',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const AuthScreen(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user = Provider.of<User?>(context);

    if (user == null) {
      return AuthScreen();
    } else {
      return ScrabbleGame();
    }
  }
}

class ScrabbleGame extends StatefulWidget {
  @override
  _ScrabbleGameState createState() => _ScrabbleGameState();
}

class _ScrabbleGameState extends State<ScrabbleGame> {
  final GameService _gameService = GameService();
  String? _currentRoomId;
  bool _isHost = false;
  List<List<String>> grid = List.generate(15, (_) => List.filled(15, ''));
  int currentPlayer = 1;
  int player1Score = 0;
  int player2Score = 0;
  List<String> validWords = [];
  List<String> letterPool = [];
  List<String> player1Rack = [];
  List<String> player2Rack = [];
  List<Offset> placedPositions = [];
  bool isFirstMove = true;
  int consecutivePasses = 0;
  bool gameEnded = false;
  List<String> lastAcceptedWords = [];
  String player1Name = "Oyuncu 1";
  String player2Name = "Oyuncu 2";

  // Geçici olarak yerleştirilen harfler: {Offset: harf}
  Map<Offset, String> pendingTiles = {};

  // JOKER dönüşümlerini saklamak için map
  Map<Offset, String> jokerTransforms = {};

  // Harf dağılım ve puanları
  final Map<String, int> letterDistribution = {
    'A': 12,
    'B': 2,
    'C': 2,
    'Ç': 2,
    'D': 2,
    'E': 8,
    'F': 1,
    'G': 1,
    'Ğ': 1,
    'H': 1,
    'I': 4,
    'İ': 7,
    'J': 1,
    'K': 7,
    'L': 7,
    'M': 4,
    'N': 5,
    'O': 3,
    'Ö': 1,
    'P': 1,
    'R': 6,
    'S': 3,
    'Ş': 2,
    'T': 5,
    'U': 3,
    'Ü': 2,
    'V': 1,
    'Y': 2,
    'Z': 2,
    'JOKER': 2,
  };

  final Map<String, int> letterPoints = {
    'A': 1,
    'B': 3,
    'C': 4,
    'Ç': 4,
    'D': 3,
    'E': 1,
    'F': 7,
    'G': 5,
    'Ğ': 8,
    'H': 5,
    'I': 2,
    'İ': 1,
    'J': 10,
    'K': 1,
    'L': 1,
    'M': 2,
    'N': 1,
    'O': 2,
    'Ö': 7,
    'P': 5,
    'R': 1,
    'S': 2,
    'Ş': 4,
    'T': 1,
    'U': 2,
    'Ü': 3,
    'V': 7,
    'Y': 3,
    'Z': 4,
    'JOKER': 0,
  };

  // JOKER harfi yerine geçebilecek tüm harfler
  final List<String> possibleLetters = [
    'A',
    'B',
    'C',
    'Ç',
    'D',
    'E',
    'F',
    'G',
    'Ğ',
    'H',
    'I',
    'İ',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'Ö',
    'P',
    'R',
    'S',
    'Ş',
    'T',
    'U',
    'Ü',
    'V',
    'Y',
    'Z',
  ];

  // Bonus karelerin matrisini tanımla
  final List<List<String>> bonusMatrix = List.generate(
    15,
    (i) => List.generate(15, (j) => ''),
  );

  // Kelime pozisyonlarını saklamak için map
  Map<String, List<Offset>> wordPositionsMap = {};

  // Socket bağlantısı için gerekli değişkenler
  late IO.Socket socket;

  @override
  void initState() {
    super.initState();
    _initializeGame();
    loadWords();
    _initializeBonusMatrix();
    WidgetsBinding.instance.addPostFrameCallback((_) => _askPlayerNames());
  }

  void _initializeGame() {
    letterPool = _generateLetterPool();
    player1Rack = _drawLetters(7);
    player2Rack = _drawLetters(7);
  }

  void _initializeBonusMatrix() {
    // K3 (Kahverengi) - Kelime x3
    var k3Positions = [
      [0, 0],
      [0, 7],
      [0, 14],
      [7, 0],
      [7, 14],
      [14, 0],
      [14, 7],
      [14, 14],
    ];

    // K2 (Yeşil) - Kelime x2
    var k2Positions = [
      [1, 1],
      [2, 2],
      [3, 3],
      [4, 4],
      [1, 13],
      [2, 12],
      [3, 11],
      [4, 10],
      [13, 1],
      [12, 2],
      [11, 3],
      [10, 4],
      [13, 13],
      [12, 12],
      [11, 11],
      [10, 10],
    ];

    // H3 (Pembe) - Harf x3
    var h3Positions = [
      [1, 5],
      [1, 9],
      [5, 1],
      [5, 5],
      [5, 9],
      [5, 13],
      [9, 1],
      [9, 5],
      [9, 9],
      [9, 13],
      [13, 5],
      [13, 9],
    ];

    // H2 (Mavi) - Harf x2
    var h2Positions = [
      [0, 3],
      [0, 11],
      [2, 6],
      [2, 8],
      [3, 7],
      [6, 2],
      [6, 6],
      [6, 8],
      [6, 12],
      [7, 3],
      [7, 11],
      [8, 2],
      [8, 6],
      [8, 8],
      [8, 12],
      [11, 7],
      [12, 6],
      [12, 8],
      [14, 3],
      [14, 11],
    ];

    // Pozisyonları matrise yerleştir
    for (var pos in k3Positions) {
      bonusMatrix[pos[0]][pos[1]] = 'K3';
    }
    for (var pos in k2Positions) {
      bonusMatrix[pos[0]][pos[1]] = 'K2';
    }
    for (var pos in h3Positions) {
      bonusMatrix[pos[0]][pos[1]] = 'H3';
    }
    for (var pos in h2Positions) {
      bonusMatrix[pos[0]][pos[1]] = 'H2';
    }

    // Merkez yıldız
    bonusMatrix[7][7] = 'STAR';
  }

  List<String> _generateLetterPool() {
    List<String> pool = [];
    letterDistribution.forEach((letter, count) {
      pool.addAll(List.filled(count, letter));
    });
    pool.shuffle();
    return pool;
  }

  List<String> _drawLetters(int count) {
    List<String> drawn = [];
    for (int i = 0; i < count; i++) {
      if (letterPool.isNotEmpty) {
        drawn.add(letterPool.removeLast());
      }
    }
    return drawn;
  }

  Future<void> loadWords() async {
    final String response = await rootBundle.loadString('../lib/kelimeler.txt');
    validWords =
        response.split('\n').map((word) => word.trim().toUpperCase()).toList();
  }

  bool _cellHasLetter(int x, int y) {
    return pendingTiles.containsKey(Offset(x.toDouble(), y.toDouble())) ||
        grid[x][y].isNotEmpty;
  }

  bool _validatePlacement() {
    if (placedPositions.isEmpty) return false;

    // İlk hamlede merkez kontrolü
    if (isFirstMove) {
      bool usesCenterTile = placedPositions.any(
        (pos) => pos.dx == 7 && pos.dy == 7,
      );
      if (!usesCenterTile) {
        return false;
      }
    } else {
      // İlk hamle değilse, en az bir mevcut harfe bağlantı olmalı
      bool hasConnection = false;
      for (var pos in placedPositions) {
        int x = pos.dx.toInt();
        int y = pos.dy.toInt();

        // Üst
        if (x > 0 &&
            grid[x - 1][y].isNotEmpty &&
            !pendingTiles.containsKey(
              Offset((x - 1).toDouble(), y.toDouble()),
            )) {
          hasConnection = true;
          break;
        }
        // Alt
        if (x < 14 &&
            grid[x + 1][y].isNotEmpty &&
            !pendingTiles.containsKey(
              Offset((x + 1).toDouble(), y.toDouble()),
            )) {
          hasConnection = true;
          break;
        }
        // Sol
        if (y > 0 &&
            grid[x][y - 1].isNotEmpty &&
            !pendingTiles.containsKey(
              Offset(x.toDouble(), (y - 1).toDouble()),
            )) {
          hasConnection = true;
          break;
        }
        // Sağ
        if (y < 14 &&
            grid[x][y + 1].isNotEmpty &&
            !pendingTiles.containsKey(
              Offset(x.toDouble(), (y + 1).toDouble()),
            )) {
          hasConnection = true;
          break;
        }
      }
      if (!hasConnection) return false;
    }

    // Harfler aynı satır veya sütunda olmalı
    bool sameRow = placedPositions.every(
      (pos) => pos.dx == placedPositions[0].dx,
    );
    bool sameCol = placedPositions.every(
      (pos) => pos.dy == placedPositions[0].dy,
    );

    if (!sameRow && !sameCol) return false;

    // Harfler arasında boşluk olmamalı
    if (sameRow) {
      int row = placedPositions[0].dx.toInt();
      List<int> cols = placedPositions.map((pos) => pos.dy.toInt()).toList();
      int minCol = cols.reduce((a, b) => a < b ? a : b);
      int maxCol = cols.reduce((a, b) => a > b ? a : b);

      for (int col = minCol; col <= maxCol; col++) {
        if (!_cellHasLetter(row, col)) return false;
      }
    } else {
      int col = placedPositions[0].dy.toInt();
      List<int> rows = placedPositions.map((pos) => pos.dx.toInt()).toList();
      int minRow = rows.reduce((a, b) => a < b ? a : b);
      int maxRow = rows.reduce((a, b) => a > b ? a : b);

      for (int row = minRow; row <= maxRow; row++) {
        if (!_cellHasLetter(row, col)) return false;
      }
    }

    return true;
  }

  bool _isPartOfValidWord(int x, int y) {
    if (grid[x][y].isEmpty) return false;

    // Yatay kelime kontrolü
    String horizontal = '';
    for (int col = 0; col < 15; col++) {
      if (grid[x][col].isNotEmpty) {
        horizontal += grid[x][col];
      } else if (horizontal.length > 1) {
        if (validWords.contains(horizontal)) return true;
        horizontal = '';
      } else {
        horizontal = '';
      }
    }
    if (horizontal.length > 1 && validWords.contains(horizontal)) return true;

    // Dikey kelime kontrolü
    String vertical = '';
    for (int row = 0; row < 15; row++) {
      if (grid[row][y].isNotEmpty) {
        vertical += grid[row][y];
      } else if (vertical.length > 1) {
        if (validWords.contains(vertical)) return true;
        vertical = '';
      } else {
        vertical = '';
      }
    }
    if (vertical.length > 1 && validWords.contains(vertical)) return true;

    return false;
  }

  List<String> _getAllWords() {
    Set<String> words = {};
    Map<String, List<Offset>> wordPositions = {};

    // Yatay kelimeleri bul
    for (int x = 0; x < 15; x++) {
      String currentWord = '';
      List<Offset> positions = [];
      bool containsNewLetter = false;

      for (int y = 0; y < 15; y++) {
        String letter =
            pendingTiles[Offset(x.toDouble(), y.toDouble())] ?? grid[x][y];

        if (letter.isNotEmpty) {
          currentWord += letter;
          Offset currentPos = Offset(x.toDouble(), y.toDouble());
          positions.add(currentPos);
          if (pendingTiles.containsKey(currentPos)) {
            containsNewLetter = true;
          }
        } else {
          if (currentWord.length > 1 && containsNewLetter) {
            words.add(currentWord);
            wordPositions[currentWord] = List.from(positions);
          }
          currentWord = '';
          positions = [];
          containsNewLetter = false;
        }
      }
      if (currentWord.length > 1 && containsNewLetter) {
        words.add(currentWord);
        wordPositions[currentWord] = List.from(positions);
      }
    }

    // Dikey kelimeleri bul
    for (int y = 0; y < 15; y++) {
      String currentWord = '';
      List<Offset> positions = [];
      bool containsNewLetter = false;

      for (int x = 0; x < 15; x++) {
        String letter =
            pendingTiles[Offset(x.toDouble(), y.toDouble())] ?? grid[x][y];

        if (letter.isNotEmpty) {
          currentWord += letter;
          Offset currentPos = Offset(x.toDouble(), y.toDouble());
          positions.add(currentPos);
          if (pendingTiles.containsKey(currentPos)) {
            containsNewLetter = true;
          }
        } else {
          if (currentWord.length > 1 && containsNewLetter) {
            words.add(currentWord);
            wordPositions[currentWord] = List.from(positions);
          }
          currentWord = '';
          positions = [];
          containsNewLetter = false;
        }
      }
      if (currentWord.length > 1 && containsNewLetter) {
        words.add(currentWord);
        wordPositions[currentWord] = List.from(positions);
      }
    }

    // Kelime pozisyonlarını sakla
    wordPositionsMap = wordPositions;

    // Debug için kelimeleri yazdır
    print('Bulunan kelimeler:');
    words.forEach((word) {
      print('- $word');
      print('  Pozisyonlar: ${wordPositions[word]}');
    });

    return words.toList();
  }

  bool _isValidWithJoker(String word) {
    // JOKER içermeyen normal kelime kontrolü
    if (!word.contains('JOKER')) {
      // Yıldızları kaldır
      String cleanWord = word.replaceAll('*', '');
      return validWords.contains(cleanWord);
    }

    // JOKER içeren kelime için tüm olası harfleri dene
    String baseWord = word;
    int jokerIndex = baseWord.indexOf('JOKER');

    // Her harf için dene
    for (String letter in possibleLetters) {
      // JOKER'i harfle değiştir
      String testWord =
          baseWord.substring(0, jokerIndex) +
          letter +
          baseWord.substring(jokerIndex + 5);

      // Eğer kelime geçerliyse JOKER dönüşümünü kaydet
      if (validWords.contains(testWord)) {
        // JOKER'in pozisyonunu bul ve dönüşümü kaydet
        List<Offset>? positions = wordPositionsMap[word];
        if (positions != null) {
          for (Offset pos in positions) {
            String currentLetter =
                pendingTiles[pos] ?? grid[pos.dx.toInt()][pos.dy.toInt()];
            if (currentLetter == 'JOKER') {
              jokerTransforms[pos] = letter;
              print('JOKER dönüşümü: $letter');
              break;
            }
          }
        }
        return true;
      }
    }
    return false;
  }

  // Bonus kareyi döndüren fonksiyon
  String getBonus(int x, int y) {
    return bonusMatrix[x][y];
  }

  int calculateWordScore(String word) {
    List<Offset>? positions = wordPositionsMap[word];
    if (positions == null) {
      print('Pozisyon bulunamadı: $word');
      return 0;
    }

    print('Kelime puanı hesaplanıyor: $word');
    print('Pozisyonlar: $positions');

    int wordMultiplier = 1;
    int total = 0;

    for (Offset pos in positions) {
      String letter = pendingTiles[pos] ?? grid[pos.dx.toInt()][pos.dy.toInt()];
      String bonus = getBonus(pos.dx.toInt(), pos.dy.toInt());

      // Harf puanını hesapla
      int letterScore = 0;
      if (letter == 'JOKER') {
        letterScore = 0;
      } else {
        letterScore = letterPoints[letter] ?? 0;
      }

      print('Harf: $letter, Temel Puan: $letterScore, Bonus: $bonus');

      // Bonus hesaplama (sadece yeni yerleştirilen harfler için)
      if (pendingTiles.containsKey(pos)) {
        switch (bonus) {
          case 'H2':
            letterScore *= 2;
            print('H2 bonus uygulandı: $letterScore');
            break;
          case 'H3':
            letterScore *= 3;
            print('H3 bonus uygulandı: $letterScore');
            break;
          case 'K2':
            wordMultiplier *= 2;
            print('K2 bonus uygulandı');
            break;
          case 'K3':
            wordMultiplier *= 3;
            print('K3 bonus uygulandı');
            break;
        }
      }

      total += letterScore;
    }

    int finalScore = total * wordMultiplier;
    print(
      'Kelime: $word, Toplam: $total, Çarpan: $wordMultiplier, Son Puan: $finalScore',
    );
    return finalScore;
  }

  void _submitWord() async {
    if (!_validatePlacement()) {
      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text('Geçersiz Yerleşim'),
              content: Text('Harfler uygun şekilde yerleştirilmemiş!'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Tamam'),
                ),
              ],
            ),
      );
      return;
    }

    // JOKER dönüşümlerini temizle
    jokerTransforms.clear();

    List<String> allWords = _getAllWords();

    // Tüm kelimelerin anlamlı olması gerekiyor
    bool allValid = true;
    List<String> invalidWords = [];

    for (String word in allWords) {
      if (!_isValidWithJoker(word)) {
        allValid = false;
        invalidWords.add(word);
      }
    }

    if (!allValid) {
      // Hatalıysa harfleri geri ver ve grid'den sil
      pendingTiles.forEach((pos, letter) {
        if (currentPlayer == 1) {
          player1Rack.add(letter);
        } else {
          player2Rack.add(letter);
        }
        grid[pos.dx.toInt()][pos.dy.toInt()] = '';
      });
      setState(() {
        pendingTiles.clear();
        placedPositions.clear();
        jokerTransforms.clear();
      });
      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text('Geçersiz Kelime'),
              content: Text(
                'Tüm kelimeler anlamlı olmalı!\n\nAnlamsız kelimeler: ${invalidWords.join(", ")}',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Tamam'),
                ),
              ],
            ),
      );
      return;
    }

    // Geçerli kelime durumunda harfleri grid'e kalıcı olarak ekle
    pendingTiles.forEach((pos, letter) {
      if (letter == 'JOKER' && jokerTransforms.containsKey(pos)) {
        grid[pos.dx.toInt()][pos.dy.toInt()] = jokerTransforms[pos]!;
      } else {
        grid[pos.dx.toInt()][pos.dy.toInt()] = letter;
      }
    });

    // Puanları hesapla
    int totalScore = 0;
    print('\nPuan hesaplaması başlıyor...');
    for (String word in allWords) {
      int wordScore = calculateWordScore(word);
      totalScore += wordScore;
      print('$word: $wordScore puan');
    }
    print('Toplam puan: $totalScore\n');

    if (_currentRoomId != null) {
      final move = {
        'grid': grid,
        'player1Score': player1Score,
        'player2Score': player2Score,
        'currentPlayer': currentPlayer,
        'player1Rack': player1Rack,
        'player2Rack': player2Rack,
      };

      await _gameService.sendMove(_currentRoomId!, move);
    }

    setState(() {
      if (currentPlayer == 1) {
        player1Score += totalScore;
        print('Oyuncu 1 yeni skor: $player1Score');
      } else {
        player2Score += totalScore;
        print('Oyuncu 2 yeni skor: $player2Score');
      }
      lastAcceptedWords = allWords;
      pendingTiles.clear();
      placedPositions.clear();
      isFirstMove = false;
      currentPlayer = currentPlayer == 1 ? 2 : 1;
      consecutivePasses = 0;
    });

    _refillRack();
  }

  void _refillRack() {
    int needed =
        7 - (currentPlayer == 1 ? player1Rack.length : player2Rack.length);
    List<String> newLetters = _drawLetters(needed);

    setState(() {
      if (currentPlayer == 1) {
        player1Rack.addAll(newLetters);
      } else {
        player2Rack.addAll(newLetters);
      }
    });
  }

  Widget _buildLetterTile(String letter) {
    return Draggable<String>(
      data: letter,
      feedback: Material(
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.blue[700],
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: Offset(2, 2),
              ),
            ],
          ),
          child: Center(
            child: Text(
              letter,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
      childWhenDragging: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.blue[700],
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            letter,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }

  Color _getTileColor(int x, int y) {
    if (grid[x][y].isEmpty) {
      return isFirstMove && x == 7 && y == 7
          ? Colors.amber
          : Colors.green[100]!;
    }

    // Yatay kelime kontrolü
    String horizontal = '';
    for (int col = 0; col < 15; col++) {
      if (grid[x][col].isNotEmpty) {
        horizontal += grid[x][col];
      } else if (horizontal.length > 1) {
        if (validWords.contains(horizontal)) return Colors.blue[200]!;
        horizontal = '';
      } else {
        horizontal = '';
      }
    }
    if (horizontal.length > 1 && validWords.contains(horizontal))
      return Colors.blue[200]!;

    // Dikey kelime kontrolü
    String vertical = '';
    for (int row = 0; row < 15; row++) {
      if (grid[row][y].isNotEmpty) {
        vertical += grid[row][y];
      } else if (vertical.length > 1) {
        if (validWords.contains(vertical)) return Colors.purple[200]!;
        vertical = '';
      } else {
        vertical = '';
      }
    }
    if (vertical.length > 1 && validWords.contains(vertical))
      return Colors.purple[200]!;

    // Tek harf ekleyerek kelime oluşturma kontrolü
    if (placedPositions.any((pos) => pos.dx == x && pos.dy == y)) {
      // Yatay kontrol
      for (int col = 0; col < 15; col++) {
        if (col != y && grid[x][col].isNotEmpty) {
          String testWord = grid[x][y] + grid[x][col];
          if (validWords.contains(testWord)) return Colors.orange[100]!;
        }
      }
      // Dikey kontrol
      for (int row = 0; row < 15; row++) {
        if (row != x && grid[row][y].isNotEmpty) {
          String testWord = grid[x][y] + grid[row][y];
          if (validWords.contains(testWord)) return Colors.orange[100]!;
        }
      }
    }

    return Colors.green[100]!;
  }

  Widget _buildGridCell(int x, int y) {
    return DragTarget<String>(
      onAccept: (data) {
        setState(() {
          pendingTiles[Offset(x.toDouble(), y.toDouble())] = data;
          placedPositions.add(Offset(x.toDouble(), y.toDouble()));
          // Harfi rack'ten kaldır
          if (currentPlayer == 1) {
            player1Rack.remove(data);
          } else {
            player2Rack.remove(data);
          }
        });
      },
      builder: (context, _, __) {
        return GestureDetector(
          onTap: () {
            // Sadece bu tur içinde yerleştirilen harfler silinebilir
            if (pendingTiles.containsKey(Offset(x.toDouble(), y.toDouble()))) {
              setState(() {
                String letter =
                    pendingTiles[Offset(x.toDouble(), y.toDouble())]!;
                pendingTiles.remove(Offset(x.toDouble(), y.toDouble()));
                placedPositions.removeWhere(
                  (pos) => pos.dx == x && pos.dy == y,
                );
                if (currentPlayer == 1) {
                  player1Rack.add(letter);
                } else {
                  player2Rack.add(letter);
                }
              });
            }
          },
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              color: _getGridCellColor(x, y),
            ),
            child: Center(child: _buildGridCellContent(x, y)),
          ),
        );
      },
    );
  }

  // Bonus kareyi ve harfi birlikte gösteren widget
  Widget _buildGridCellContent(int x, int y) {
    String bonus = getBonus(x, y);
    String? letter =
        pendingTiles[Offset(x.toDouble(), y.toDouble())] ?? grid[x][y];

    if (letter != null && letter.isNotEmpty) {
      // JOKER dönüşümünü kontrol et
      bool isJoker = false;
      String displayLetter = letter;

      if (letter == 'JOKER') {
        String? transform = jokerTransforms[Offset(x.toDouble(), y.toDouble())];
        if (transform != null) {
          displayLetter = transform;
          isJoker = true;
        }
      } else {
        // Eğer bu pozisyonda önceden bir JOKER dönüşümü varsa
        Offset pos = Offset(x.toDouble(), y.toDouble());
        isJoker =
            pendingTiles[pos] == 'JOKER' || letter == jokerTransforms[pos];
      }

      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isJoker ? Colors.orange[700] : Colors.blue[700],
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            displayLetter,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      );
    }

    // Bonus işaretleri için stil
    TextStyle bonusStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 14);

    if (bonus == 'H2') {
      return Text('H²', style: bonusStyle.copyWith(color: Colors.blue[700]));
    } else if (bonus == 'H3') {
      return Text('H³', style: bonusStyle.copyWith(color: Colors.pink[700]));
    } else if (bonus == 'K2') {
      return Text('K²', style: bonusStyle.copyWith(color: Colors.green[700]));
    } else if (bonus == 'K3') {
      return Text('K³', style: bonusStyle.copyWith(color: Colors.brown[700]));
    } else if (bonus == 'STAR') {
      return Icon(Icons.star, color: Colors.amber[700], size: 24);
    }
    return SizedBox.shrink();
  }

  // Bonus karelerin arka plan rengini döndür
  Color _getGridCellColor(int x, int y) {
    String bonus = getBonus(x, y);
    if (bonus == 'H2') return Colors.blue[200]!; // Açık mavi
    if (bonus == 'H3') return Colors.pink[200]!; // Açık pembe
    if (bonus == 'K2') return Colors.green[200]!; // Açık yeşil
    if (bonus == 'K3') return Colors.brown[200]!; // Açık kahverengi
    if (bonus == 'STAR') return Colors.amber[200]!;
    return Colors.white; // Normal kareler beyaz olsun
  }

  void _passTurn() {
    // Geçici harfleri geri ver ve grid'den sil
    pendingTiles.forEach((pos, letter) {
      if (currentPlayer == 1) {
        player1Rack.add(letter);
      } else {
        player2Rack.add(letter);
      }
      grid[pos.dx.toInt()][pos.dy.toInt()] = '';
    });
    pendingTiles.clear();
    placedPositions.clear();
    setState(() {
      consecutivePasses++;
      if (consecutivePasses >= 4) {
        gameEnded = true;
        _showGameEndDialog();
      } else {
        currentPlayer = currentPlayer == 1 ? 2 : 1;
      }
    });
  }

  void _showGameEndDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: Text('Oyun Bitti'),
            content: Text(
              '4 kez üst üste pas geçildi.\n\nSkorlar:\nOyuncu 1: $player1Score\nOyuncu 2: $player2Score',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _restartGame();
                },
                child: Text('Yeniden Başlat'),
              ),
            ],
          ),
    );
  }

  void _restartGame() {
    setState(() {
      grid = List.generate(15, (_) => List.filled(15, ''));
      player1Score = 0;
      player2Score = 0;
      currentPlayer = 1;
      isFirstMove = true;
      consecutivePasses = 0;
      gameEnded = false;
      placedPositions.clear();
      _initializeGame();
    });
  }

  void _askPlayerNames() async {
    TextEditingController controller1 = TextEditingController();
    TextEditingController controller2 = TextEditingController();
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text('Oyuncu Adları'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller1,
                decoration: InputDecoration(labelText: '1. Oyuncu Adı'),
              ),
              TextField(
                controller: controller2,
                decoration: InputDecoration(labelText: '2. Oyuncu Adı'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  player1Name =
                      controller1.text.isNotEmpty
                          ? controller1.text
                          : "Oyuncu 1";
                  player2Name =
                      controller2.text.isNotEmpty
                          ? controller2.text
                          : "Oyuncu 2";
                });
                Navigator.of(context).pop();
              },
              child: Text('Başla'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Türkçe Scrabble'),
        actions: [
          if (_currentRoomId == null)
            IconButton(
              icon: Icon(Icons.add),
              onPressed: _createRoom,
              tooltip: 'Oda Oluştur',
            ),
        ],
      ),
      body: Column(
        children: [
          if (_currentRoomId == null)
            Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(labelText: 'Oda Kodu'),
                    onSubmitted: _joinRoom,
                  ),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => _createRoom(),
                    child: Text('Oda Oluştur'),
                  ),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildPlayerInfo(1),
                Column(
                  children: [
                    Text(
                      'Kalan Harf',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${letterPool.length}',
                      style: TextStyle(fontSize: 18, color: Colors.deepOrange),
                    ),
                  ],
                ),
                _buildPlayerInfo(2),
                Text(
                  'Pas: $consecutivePasses',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          if (lastAcceptedWords.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Kabul edilen kelime(ler): ' + lastAcceptedWords.join(", "),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green[800],
                ),
              ),
            ),
          Expanded(
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 15,
              ),
              itemBuilder:
                  (context, index) => _buildGridCell(index ~/ 15, index % 15),
              itemCount: 225,
            ),
          ),
          Container(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount:
                  currentPlayer == 1 ? player1Rack.length : player2Rack.length,
              separatorBuilder: (_, __) => SizedBox(width: 10),
              itemBuilder:
                  (context, index) => _buildLetterTile(
                    currentPlayer == 1
                        ? player1Rack[index]
                        : player2Rack[index],
                  ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: gameEnded ? null : _submitWord,
                  child: Text('Kelimeyi Onayla'),
                ),
                SizedBox(width: 16),
                ElevatedButton(
                  onPressed: gameEnded ? null : _passTurn,
                  child: Text('Pas'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerInfo(int player) {
    return Column(
      children: [
        Text(
          player == 1 ? player1Name : player2Name,
          style: TextStyle(
            fontWeight:
                currentPlayer == player ? FontWeight.bold : FontWeight.normal,
            color: currentPlayer == player ? Colors.blue : Colors.black,
          ),
        ),
        Text('${player == 1 ? player1Score : player2Score} Puan'),
      ],
    );
  }

  Future<void> _createRoom() async {
    try {
      final roomId = await _gameService.createRoom();
      setState(() {
        _currentRoomId = roomId;
        _isHost = true;
      });

      // Oyun durumunu dinle
      _gameService.listenGameState(roomId).listen((snapshot) {
        if (!_isHost) {
          final data = snapshot.data() as Map<String, dynamic>;
          setState(() {
            grid = List<List<String>>.from(
              data['grid'].map((row) => List<String>.from(row)),
            );
            player1Score = data['player1Score'];
            player2Score = data['player2Score'];
            currentPlayer = data['currentPlayer'];
            player1Rack = List<String>.from(data['player1Rack']);
            player2Rack = List<String>.from(data['player2Rack']);
          });
        }
      });
    } catch (e) {
      print('Oda oluşturma hatası: $e');
    }
  }

  Future<void> _joinRoom(String roomId) async {
    try {
      final success = await _gameService.joinRoom(roomId);
      if (success) {
        setState(() {
          _currentRoomId = roomId;
          _isHost = false;
        });

        // Oyun durumunu dinle
        _gameService.listenGameState(roomId).listen((snapshot) {
          final data = snapshot.data() as Map<String, dynamic>;
          setState(() {
            grid = List<List<String>>.from(
              data['grid'].map((row) => List<String>.from(row)),
            );
            player1Score = data['player1Score'];
            player2Score = data['player2Score'];
            currentPlayer = data['currentPlayer'];
            player1Rack = List<String>.from(data['player1Rack']);
            player2Rack = List<String>.from(data['player2Rack']);
          });
        });
      }
    } catch (e) {
      print('Odaya katılma hatası: $e');
    }
  }
}
