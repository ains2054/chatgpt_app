import 'dart:convert';

import 'package:chatgpt_app/models/response.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ChatgptScreen extends StatefulWidget {
  const ChatgptScreen({super.key});

  @override
  State<ChatgptScreen> createState() => _ChatgptScreenState();
}

class _ChatgptScreenState extends State<ChatgptScreen> {
  final TextEditingController _promptController = TextEditingController();
  String responseTxt = "";
  late ResponseModel _responseModel;
  bool inputEnabled = true;
  Future<void> completionFun() async {
    final dio = Dio();
    setState(() {
      responseTxt = 'Nag huna huna pa...';
      inputEnabled = false;
    });
    String prompt = _promptController.text;
    _promptController.clear();
    
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (apiKey.isEmpty) {
      setState(() {
        inputEnabled = true;
        responseTxt = "Error: API key not found. Please check your .env file.";
      });
      return;
    }
    
    try {
      final response = await dio.post(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey',
        options: Options(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
          contentType: "application/json",
          headers: {
            'Content-Type': 'application/json',
          },
        ),
        data: jsonEncode({
          "contents": [
            {
              "parts": [
                {
                  "text": prompt
                }
              ]
            }
          ],
        }),
      );
      setState(() {
        FocusManager.instance.primaryFocus?.unfocus();
        inputEnabled = true;
        try {
          Map<String, dynamic>? responseJson = Map.from(response.data);
          _responseModel = ResponseModel.fromJson(responseJson);
          responseTxt = _responseModel.choices?.content ?? "No response received.";
          debugPrint(responseTxt);
        } catch (e) {
          debugPrint("Error parsing response: $e");
          responseTxt = "Error parsing response: $e";
        }
      });
    } catch (e) {
      setState(() {
        inputEnabled = true;
        debugPrint("API Error: $e");
        if (e.toString().contains('401') || e.toString().contains('403')) {
          responseTxt = "Error: Invalid API key. Please check your .env file.";
        } else {
          responseTxt = "Error: Unable to connect. ${e.toString()}";
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 3), () {
      setState(() {
        responseTxt = "Pag ask na Kang Oblong";
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff343541),
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text(
          'Gemini Chat',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xff343541),
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.center,
              child: !inputEnabled
                  ? const CircularProgressIndicator(color: Colors.purple)
                  : const SizedBox.shrink(),
            ),
          ),
          Positioned.fill(
            child: Column(
              children: [
                Expanded(
                  flex: 2,
                  child:
                      Center(child: PromptBuilder(responseText: responseTxt)),
                ),
                Expanded(
                  child: TextFormFieldBuilder(
                    promptController: _promptController,
                    btnFunc: completionFun,
                    enabled: inputEnabled,
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PromptBuilder extends StatelessWidget {
  const PromptBuilder({super.key, required this.responseText});
  final String responseText;
  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height / 1.35,
      child: Align(
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: SingleChildScrollView(
            child: Text(
              responseText,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 25.0, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class TextFormFieldBuilder extends StatelessWidget {
  TextFormFieldBuilder({
    super.key,
    required this.promptController,
    required this.btnFunc,
    required this.enabled,
  });
  final TextEditingController promptController;
  final Function btnFunc;
  final bool enabled;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(left: 10, right: 10, bottom: 20),
        child: Row(
          children: [
            Flexible(
              child: Form(
                key: _formKey,
                child: TextFormField(
                  cursorColor: Colors.white,
                  enabled: enabled,
                  controller: promptController,
                  autofocus: false,
                  validator: (String? value) {
                    if (value == null || value.isEmpty) {
                      return "Please enter something";
                    }
                    return null;
                  },
                  style: const TextStyle(color: Colors.white, fontSize: 20.0),
                  decoration: InputDecoration(
                    focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(
                          color: Color(0xff444653),
                        ),
                        borderRadius: BorderRadius.circular(8)),
                    enabledBorder: const OutlineInputBorder(
                        borderSide: BorderSide(
                      color: Color(0xff444653),
                    )),
                    filled: true,
                    fillColor: const Color(0xff444653),
                    errorStyle: const TextStyle(
                      fontSize: 20.0,
                      fontWeight: FontWeight.bold,
                    ),
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                    hintText: "Please ask Something...",
                  ),
                ),
              ),
            ),
            Container(
              color: const Color(0xff19bc99),
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: IgnorePointer(
                  ignoring: !enabled,
                  child: Opacity(
                    opacity: !enabled ? 0.5 : 1.0,
                    child: IconButton(
                      onPressed: () {
                        if (_formKey.currentState?.validate() ?? false) {
                          _formKey.currentState?.save();
                          btnFunc();
                        }
                      },
                      icon: const Icon(
                        Icons.send,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
