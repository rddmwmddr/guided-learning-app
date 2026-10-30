import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manmanxiang/app/settings_store.dart';
import 'package:manmanxiang/ui/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('语音选项在 $width 宽的手机上不溢出', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = (await tester.runAsync(SettingsStore.load))!;
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(home: SettingsPage(settings: settings)),
      );
      await tester.scrollUntilVisible(
        find.text('内置离线'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('内置离线'));
      await tester.pumpAndSettle();
      expect(settings.asrMode, AsrMode.local);
      await tester.scrollUntilVisible(
        find.text('测试识别'),
        100,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('试听朗读'), findsOneWidget);
      expect(find.text('测试识别'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
