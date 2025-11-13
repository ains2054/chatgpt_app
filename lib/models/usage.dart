class Usage {
  Usage({
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
  });
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
  
  factory Usage.fromJson(Map<String, dynamic>? json) {
    if (json == null) return Usage();
    
    // Gemini API provides usage in usageMetadata
    int? promptTokens;
    int? completionTokens;
    int? totalTokens;
    
    if (json['usageMetadata'] != null) {
      promptTokens = json['usageMetadata']['promptTokenCount'];
      completionTokens = json['usageMetadata']['candidatesTokenCount'];
      totalTokens = json['usageMetadata']['totalTokenCount'];
    }
    
    return Usage(
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: totalTokens,
    );
  }
  
  Map<String, dynamic>? toJson() => {
        "prompt_tokens": this.promptTokens,
        "completion_tokens": this.completionTokens,
        "total_tokens": this.totalTokens,
      };
}
