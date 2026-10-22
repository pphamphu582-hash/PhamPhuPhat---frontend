
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:worktime_mobile/main.dart';

void main() {
  test('WorkTimeApp được khai báo thành công', () {
    final app = const WorkTimeApp();

    expect(app, isA<Widget>());
  });
}
