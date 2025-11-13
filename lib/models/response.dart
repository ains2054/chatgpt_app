import 'package:chatgpt_app/models/choices.dart';
import 'package:chatgpt_app/models/usage.dart';

class ResponseModel {
  ResponseModel({this.choices, this.usage});
  final Choices? choices;
  final Usage? usage;
  
  factory ResponseModel.fromJson(Map<String, dynamic>? json) {
    if (json == null) return ResponseModel();
    
    return ResponseModel(
      choices: Choices.fromJson(json),
      usage: Usage.fromJson(json),
    );
  }
  
  Map<String, dynamic>? toJson() => {
        "choices": this.choices?.toJson(),
        "usage": this.usage?.toJson(),
      };
}
