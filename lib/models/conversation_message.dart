/// Plain in-memory message row for a chat conversation.
/// Not a Firestore [QueryDocumentSnapshot] — survives screen disposal.
class ConversationMessage {
  final String id;
  final Map<String, dynamic> data;

  const ConversationMessage({required this.id, required this.data});

  ConversationMessage copyWith({String? id, Map<String, dynamic>? data}) {
    return ConversationMessage(
      id: id ?? this.id,
      data: data ?? this.data,
    );
  }
}
