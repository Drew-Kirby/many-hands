import 'package:flutter_test/flutter_test.dart';
import 'package:many_hands/util.dart';

void main() {
  test('phone numbers always come out as (555) 123-4567', () {
    for (final input in ['5551234567', '555-123-4567', '+1 555 123 4567', '(555)123-4567']) {
      expect(formatPhone(input), '(555) 123-4567');
    }
    expect(formatPhone('5551'), '(555) 1');
    expect(formatPhone('555123456789'), '(555) 123-4567');
    expect(isValidPhone('(555) 123-4567'), isTrue);
    expect(isValidPhone('(555) 123-456'), isFalse);
  });

  test('due dates round-trip as calendar days', () {
    expect(toISODate(DateTime(2026, 3, 7)), '2026-03-07');
    expect(parseISO('2026-03-07'), DateTime(2026, 3, 7));
    expect(formatDue(todayISO()), 'Today');
  });

  test('keyword search needs every word', () {
    expect(matchesWords('Food drive at the park', 'park food'), isTrue);
    expect(matchesWords('Food drive at the park', 'park coats'), isFalse);
    expect(matchesWords('anything', '   '), isTrue);
  });

  test('initials and first names', () {
    expect(initials('Maya Thompson'), 'MT');
    expect(initials('Cher'), 'C');
    expect(firstName('  Drew Kirby '), 'Drew');
  });
}
