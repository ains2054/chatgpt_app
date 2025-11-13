class Choices {
  Choices({this.content, this.role, this.finishReason});
  final String? content;
  final String? role;
  final String? finishReason;
  
  factory Choices.fromJson(Map<String, dynamic>? json) {
    // Gemini API response structure
    if (json == null) return Choices();
    
    // Extract text from parts array
    String? text;
    if (json['candidates'] != null && 
        json['candidates'].isNotEmpty &&
        json['candidates'][0]['content'] != null &&
        json['candidates'][0]['content']['parts'] != null &&
        json['candidates'][0]['content']['parts'].isNotEmpty) {
      text = json['candidates'][0]['content']['parts'][0]['text'];
    }
    
    String? finishReason;
    if (json['candidates'] != null && 
        json['candidates'].isNotEmpty &&
        json['candidates'][0]['finishReason'] != null) {
      finishReason = json['candidates'][0]['finishReason'];
    }
    
    return Choices(
      content: text,
      role: json['candidates']?[0]?['content']?['role'] ?? 'model',
      finishReason: finishReason,
    );
  }
  
  Map<String, dynamic>? toJson() => {
        "content": this.content,
        "role": this.role,
        "finish_reason": this.finishReason,
      };
}
