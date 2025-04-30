import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class GameService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Oda oluştur
  Future<String> createRoom() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Kullanıcı girişi yapılmamış');

    final roomRef = await _firestore.collection('rooms').add({
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': user.uid,
      'status': 'waiting',
      'players': [user.uid],
      'currentPlayer': user.uid,
      'grid': List.generate(15, (_) => List.filled(15, '')),
      'player1Rack': [],
      'player2Rack': [],
      'player1Score': 0,
      'player2Score': 0,
      'lastMove': null,
    });

    return roomRef.id;
  }

  // Odaya katıl
  Future<bool> joinRoom(String roomId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Kullanıcı girişi yapılmamış');

    try {
      await _firestore.collection('rooms').doc(roomId).update({
        'players': FieldValue.arrayUnion([user.uid]),
        'status': 'playing',
      });
      return true;
    } catch (e) {
      print('Odaya katılma hatası: $e');
      return false;
    }
  }

  // Hamle gönder
  Future<void> sendMove(String roomId, Map<String, dynamic> move) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Kullanıcı girişi yapılmamış');

    await _firestore.collection('rooms').doc(roomId).update({
      'lastMove': move,
      'grid': move['grid'],
      'player1Score': move['player1Score'],
      'player2Score': move['player2Score'],
      'currentPlayer': move['currentPlayer'],
      'player1Rack': move['player1Rack'],
      'player2Rack': move['player2Rack'],
    });
  }

  // Oyun durumunu dinle
  Stream<DocumentSnapshot> listenGameState(String roomId) {
    return _firestore.collection('rooms').doc(roomId).snapshots();
  }

  // Oyunu sonlandır
  Future<void> endGame(String roomId) async {
    await _firestore.collection('rooms').doc(roomId).update({
      'status': 'ended',
    });
  }
}
