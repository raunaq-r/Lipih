import 'package:flutter_test/flutter_test.dart';

import 'package:lipih/main.dart';

void main() {
  testWidgets('Lipih opens the notes workspace', (tester) async {
    await tester.pumpWidget(const LipihApp());

    expect(find.byType(LipihApp), findsOneWidget);
  });
}
