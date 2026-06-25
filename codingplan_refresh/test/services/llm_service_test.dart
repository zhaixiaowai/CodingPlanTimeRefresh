import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/services/llm_service.dart';

void main() {
  test('processSseLines 累积 delta.content 并在 [DONE] 停止', () {
    final lines = [
      'data: {"choices":[{"delta":{"content":"你"}}]}',
      'data: {"choices":[{"delta":{"content":"好"}}]}',
      'data: {"choices":[{"delta":{"role":"assistant"}}]}', // 无 content，跳过
      'data: {坏',                                       // 坏 chunk，跳过
      'data: [DONE]',
      'data: {"choices":[{"delta":{"content":"不应出现"}}]}', // DONE 后忽略
    ];
    final chunks = <String>[];
    final full = processSseLines(lines, chunks.add);
    expect(full, '你好');
    expect(chunks, ['你', '好']);
  });

  test('processSseLines 无 DONE 时消费全部行', () {
    final lines = ['data: {"choices":[{"delta":{"content":"abc"}}]}'];
    expect(processSseLines(lines, (_) {}), 'abc');
  });
}
