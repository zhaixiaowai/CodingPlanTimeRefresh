import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/utils/sse.dart';

void main() {
  test('isDone 识别结束标记', () {
    expect(SseParser.isDone('data: [DONE]'), isTrue);
    expect(SseParser.isDone('data: {"x":1}'), isFalse);
  });

  test('extractDeltaContent 提取 delta.content', () {
    const line = 'data: {"choices":[{"delta":{"content":"你好"}}]}';
    expect(SseParser.extractDeltaContent(line), '你好');
  });

  test('无 content 字段返回 null', () {
    const line = 'data: {"choices":[{"delta":{"role":"assistant"}}]}';
    expect(SseParser.extractDeltaContent(line), isNull);
  });

  test('坏 JSON 返回 null（不抛异常）', () {
    expect(SseParser.extractDeltaContent('data: {坏json'), isNull);
  });

  test('非 data: 前缀返回 null', () {
    expect(SseParser.extractDeltaContent(': keepalive'), isNull);
    expect(SseParser.extractDeltaContent(''), isNull);
  });

  test('[DONE] 行也返回 null content', () {
    expect(SseParser.extractDeltaContent('data: [DONE]'), isNull);
  });
}
