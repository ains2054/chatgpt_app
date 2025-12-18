import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Save chat message to Firebase
  Future<void> saveChatMessage({
    required String prompt,
    required String response,
    required DateTime timestamp,
  }) async {
    try {
      await _db.collection('chat_messages').add({
        'prompt': prompt,
        'response': response,
        'timestamp': timestamp,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error saving to Firebase: $e');
      rethrow;
    }
  }

  // Get all chat messages (optional - for viewing history)
  Stream<QuerySnapshot> getChatMessages() {
    return _db
        .collection('chat_messages')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  // Delete a specific message (optional)
  Future<void> deleteMessage(String docId) async {
    await _db.collection('chat_messages').doc(docId).delete();
  }

  // Clear all chat history (optional)
  Future<void> clearAllMessages() async {
    final snapshot = await _db.collection('chat_messages').get();
    for (var doc in snapshot.docs) {
      await doc.reference.delete();
    }
  }
}