import 'package:flutter_test/flutter_test.dart';
import 'package:zev_app/main.dart';

void main() {
  testWidgets('ZEV smoke test', (WidgetTester tester) async {
    expect(ZevApp, isNotNull);
  });
}
