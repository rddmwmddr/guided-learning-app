import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manmanxiang/ui/transcript_scroller.dart';

void main() {
  Widget view(int count, {double height = 300}) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          height: height,
          width: 350,
          child: TranscriptScroller(
            children: [
              for (var i = 0; i < count; i++)
                SizedBox(
                  height: i == count - 1 ? 550 : 100,
                  child: Text('message $i'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  ScrollPosition position(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('transcriptScroll')),
          matching: find.byType(Scrollable),
        ),
      )
      .position;

  testWidgets('长消息完成排版后到达真实底部，视口缩小时仍跟随', (tester) async {
    await tester.pumpWidget(view(5));
    await tester.pumpAndSettle();
    expect(position(tester).extentAfter, lessThan(1));
    await tester.pumpWidget(view(8));
    await tester.pumpAndSettle();
    expect(position(tester).extentAfter, lessThan(1));
    await tester.pumpWidget(view(8, height: 180));
    await tester.pumpAndSettle();
    expect(position(tester).extentAfter, lessThan(1));
  });
  testWidgets('翻历史时不抢滚动位置，点击回到最新恢复跟随', (tester) async {
    await tester.pumpWidget(view(10));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('transcriptScroll')),
      const Offset(0, 250),
    );
    await tester.pumpAndSettle();
    final before = position(tester).pixels;
    await tester.pumpWidget(view(12));
    await tester.pumpAndSettle();
    expect(position(tester).pixels, closeTo(before, 1));
    await tester.tap(find.text('回到最新'));
    await tester.pumpAndSettle();
    expect(position(tester).extentAfter, lessThan(1));
  });
}
