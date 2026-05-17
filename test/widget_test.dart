import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_voice_recg_app/main.dart';
import 'package:flutter_voice_recg_app/widgets/mic_button.dart';

void main() {
  testWidgets('App boots and shows the mic button', (tester) async {
    await tester.pumpWidget(const VoiceRecgApp());
    // First frame: bootstrap is in flight, mic button should already be in the
    // tree.
    expect(find.byType(MicButton), findsOneWidget);
    expect(find.text('On-device Voice Notes'), findsOneWidget);
  });
}
