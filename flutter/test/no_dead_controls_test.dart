// Phase 3 Task 0 guard (audit-remediation): a control either does something
// real or it is removed. Five shapes of "looks live, does nothing" are banned
// tree-wide under `lib/`:
//
//   onPressed: () {}       — a button that presses nothing
//   onPressed: () => {}    — the expression-bodied version of the same
//   onTap: () {}           — a tap target that swallows the tap
//   onChanged: (_) {}      — a field widget that accepts input and drops it
//   ?? () {}               — a widget default that resurrects a dead callback
//                            when the caller passes none
//
// The guard reads the source rather than the widget tree because a dead
// control is invisible to a widget test until someone thinks to tap that one
// button — which is exactly how the ones found in the 2026-10-24 report
// survived. Reading every file makes the omission impossible to forget.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Callback shapes with nothing inside. Whitespace-tolerant so formatting
/// cannot sneak one past.
class DeadControlPattern {
  const DeadControlPattern(this.label, this.pattern);

  /// What the pattern means, shown in the failure message.
  final String label;
  final RegExp pattern;
}

final List<DeadControlPattern> deadControlPatterns = [
  DeadControlPattern(
    'onPressed: () {}',
    RegExp(r'onPressed:\s*\(\s*\)\s*\{\s*\}'),
  ),
  DeadControlPattern(
    'onPressed: () => {}',
    RegExp(r'onPressed:\s*\(\s*\)\s*=>\s*\{\s*\}'),
  ),
  DeadControlPattern('onTap: () {}', RegExp(r'onTap:\s*\(\s*\)\s*\{\s*\}')),
  DeadControlPattern(
    'onChanged: (_) {}',
    RegExp(r'onChanged:\s*\(\s*\w*\s*\)\s*\{\s*\}'),
  ),
  DeadControlPattern('?? () {}', RegExp(r'\?\?\s*\(\s*\)\s*\{\s*\}')),
];

/// `path:line: <label> — <source line>`, one entry per dead control found.
List<String> findDeadControls(Directory root) {
  final violations = <String>[];
  final files =
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final lines = file.readAsLinesSync();
    for (var index = 0; index < lines.length; index++) {
      final raw = lines[index];
      // Comments are skipped: prose that QUOTES a banned shape (the doc comment
      // explaining why `onPressed ?? () {}` was removed) is not a control. Only
      // code can wire a button to nothing.
      final line = _isComment(raw) ? '' : raw;
      for (final pattern in deadControlPatterns) {
        if (pattern.pattern.hasMatch(line)) {
          violations.add(
            '${file.path}:${index + 1}: ${pattern.label} — ${raw.trim()}',
          );
        }
      }
    }
  }
  return violations;
}

/// `//`, `///` or a `*`-prefixed block-comment continuation.
bool _isComment(String line) {
  final trimmed = line.trimLeft();
  return trimmed.startsWith('//') || trimmed.startsWith('*');
}

void main() {
  test('no control under lib/ is wired to an empty callback', () {
    final violations = findDeadControls(Directory('lib'));

    expect(
      violations,
      isEmpty,
      reason:
          'A button either does something real or it is removed. Wire it, or '
          'delete it — and if the callback is optional, pass null through so '
          'the button renders disabled instead.\nFound:\n${violations.join('\n')}',
    );
  });

  test('the guard actually reads the tree', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .length;

    expect(
      files,
      greaterThan(100),
      reason: 'a guard that scans nothing always passes',
    );
  });

  test('each pattern is recognised in the shape it bans', () {
    // Pinned so a sloppy edit cannot neuter a pattern into never matching:
    // one sample per banned shape, written as a plain string so this test file
    // is not itself a violation.
    const samples = <String, String>{
      'onPressed: () {}': 'onPressed: () {},',
      'onPressed: () => {}': 'onPressed: () => {},',
      'onTap: () {}': 'onTap: () {},',
      'onChanged: (_) {}': 'onChanged: (_) {},',
      '?? () {}': 'onPressed: onAction ?? () {},',
    };

    for (final entry in samples.entries) {
      final pattern = deadControlPatterns.firstWhere(
        (candidate) => candidate.label == entry.key,
      );
      expect(
        pattern.pattern.hasMatch(entry.value),
        isTrue,
        reason: '"${entry.key}" must be caught in `${entry.value}`',
      );
    }
  });
}
