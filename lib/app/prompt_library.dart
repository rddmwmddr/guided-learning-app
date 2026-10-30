import 'package:flutter/services.dart';

/// 内置的提示词，来自提示词库 guided-learning-prompts，用 tool/sync_prompts.sh 同步。
class PromptEntry {
  const PromptEntry({
    required this.file,
    required this.title,
    required this.audience,
    required this.example,
    required this.preschool,
  });

  final String file;
  final String title;
  final String audience;

  /// 给家长看的材料示例。
  final String example;
  final bool preschool;

  Future<String> load() => rootBundle.loadString('assets/prompts/$file');
}

const promptLibrary = [
  PromptEntry(
    file: '小学-数学.md',
    title: '小学数学',
    audience: '一到六年级 · 题目、概念',
    example: '小明有35张贴纸，送给同学18张，又买来12张，现在有多少张？',
    preschool: false,
  ),
  PromptEntry(
    file: '小学-语文.md',
    title: '小学语文',
    audience: '阅读理解、字词、写话习作',
    example: '把短文和题目打进来，或者拍照识别。',
    preschool: false,
  ),
  PromptEntry(
    file: '小学-科学.md',
    title: '小学科学',
    audience: '科学课问题、生活中的现象',
    example: '把冰块放进玻璃杯，过一会儿杯子外面出现了小水珠。小水珠是从哪里来的？',
    preschool: false,
  ),
  PromptEntry(
    file: '学前-生活中的科学与数学.md',
    title: '学前 · 科学与数学',
    audience: '3–6 岁 · 数数、比较、分类、身边的现象',
    example: '桌上有5个苹果和3个橘子，想让孩子比一比哪种多、多几个。',
    preschool: true,
  ),
  PromptEntry(
    file: '学前-绘本与语言.md',
    title: '学前 · 绘本与语言',
    audience: '3–6 岁 · 看绘本、聊故事',
    example: '拍下绘本这一页，或者写下画面和文字。',
    preschool: true,
  ),
];
