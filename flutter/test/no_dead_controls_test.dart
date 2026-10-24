// Phase 3 Task 0 guard (audit-remediation): a control either does something
// real or it is removed. "Looks live, does nothing" is banned tree-wide under
// `lib/`, in every shape it can take:
//
//   onPressed: () {}                     onTap: () => {}
//   onPressed: () {\n}                   onChanged: (v) => null,
//   onPressed: () {\n  // TODO\n}         onSubmitted: (t) async {}
//   onPressed: onAction ?? () {}         ?? () async {}
//
// The guard reads the source rather than the widget tree because a dead
// control is invisible to a widget test until someone thinks to tap that one
// button — which is exactly how the ones found in the 2026-10-24 report
// survived. Reading every file makes the omission impossible to forget.
//
// It scans the whole file as one string, after blanking comments, so an empty
// body spread over three lines and a body holding nothing but a TODO comment
// are both visible. Line-regex matching missed both.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Any `on<Callback>:` argument — whatever its parameter names — whose body is
/// empty: a block `{}` (whitespace or a comment only, since comments are
/// blanked first), an arrow `=> {}`, or an arrow `=> null`. Plus the `?? () {}`
/// default that resurrects a dead callback when the caller passes none.
///
/// Deliberately NOT matched, because these are legitimate:
///   `onPressed: null`   — the button renders disabled, by design
///   `onPressed: _save`  — a real method tear-off
///   `onPressed: () => Navigator.pop(context)` — a real arrow body
final RegExp deadCallbackPattern = RegExp(
  r'\bon[A-Z]\w*\s*:\s*\([^()]*\)\s*(?:async\s*)?'
  r'(?:=>\s*(?:\{\s*\}|null\b)|\{\s*\})'
  r'|\?\?\s*\(\s*\)\s*(?:async\s*)?\{\s*\}',
);

/// Every dead control in [source] as `<label> — <original line>`, plus the
/// 1-based line it starts on. `[]` when clean.
List<ScanHit> findDeadControlsInText(String source) {
  final code = stripDartComments(source);
  final originalLines = source.split('\n');
  final hits = <ScanHit>[];

  for (final match in deadCallbackPattern.allMatches(code)) {
    final line = '\n'.allMatches(code.substring(0, match.start)).length + 1;
    final originalLine = line <= originalLines.length
        ? originalLines[line - 1].trim()
        : '';
    final shape = match.group(0)!.replaceAll(RegExp(r'\s+'), ' ');
    hits.add(ScanHit(line: line, label: '$shape — $originalLine'));
  }
  return hits;
}

/// One dead control, reported at its line.
class ScanHit {
  const ScanHit({required this.line, required this.label});

  final int line;
  final String label;

  @override
  String toString() => 'line $line: $label';
}

/// `path:line: <label>`, one entry per dead control found under [root].
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
    for (final hit in findDeadControlsInText(file.readAsStringSync())) {
      violations.add('${file.path}:${hit.line}: ${hit.label}');
    }
  }
  return violations;
}

/// Blanks every `//` and `/* */` comment in [source], replacing each character
/// with a space and keeping newlines — so offsets and line numbers stay exactly
/// where they were. Comments only ever become whitespace, which is what lets an
/// empty body and a comment-only body look the same to the matcher.
///
/// String literals are copied verbatim, so `'http://example.com'` is not a
/// comment, `${...}` interpolation is not parsed as code, and a commented-out
/// `onPressed: () {}` never counts as a control.
String stripDartComments(String source) {
  final out = StringBuffer();
  var index = 0;

  while (index < source.length) {
    final char = source[index];
    final next = index + 1 < source.length ? source[index + 1] : '';

    if (char == '/' && next == '/') {
      while (index < source.length && source[index] != '\n') {
        out.write(' ');
        index++;
      }
      continue;
    }

    // Dart block comments nest; track it so `/* a /* b */ c */` is one comment.
    if (char == '/' && next == '*') {
      var depth = 1;
      out.write('  ');
      index += 2;
      while (index < source.length && depth > 0) {
        final inner = source[index];
        final innerNext = index + 1 < source.length ? source[index + 1] : '';
        if (inner == '/' && innerNext == '*') {
          depth++;
          out.write('  ');
          index += 2;
          continue;
        }
        if (inner == '*' && innerNext == '/') {
          depth--;
          out.write('  ');
          index += 2;
          continue;
        }
        out.write(inner == '\n' ? '\n' : ' ');
        index++;
      }
      continue;
    }

    if (char == "'" || char == '"') {
      index = _copyString(source, out, index);
      continue;
    }

    out.write(char);
    index++;
  }
  return out.toString();
}

/// Copies the string literal starting at [start] into [out] and returns the
/// index just past its closing quote.
int _copyString(String source, StringBuffer out, int start) {
  final quote = source[start];
  final raw = _isRawPrefix(source, start);
  final triple = source.startsWith(quote * 3, start);
  final delimiter = triple ? quote * 3 : quote;

  out.write(delimiter);
  var index = start + delimiter.length;

  while (index < source.length) {
    final char = source[index];

    if (!raw && char == r'\' && index + 1 < source.length) {
      out.write(source.substring(index, index + 2));
      index += 2;
      continue;
    }

    // `${expr}`` may hold quotes and slashes of its own; copy it whole.
    if (!raw &&
        char == r'$' &&
        index + 1 < source.length &&
        source[index + 1] == '{') {
      index = _copyInterpolation(source, out, index);
      continue;
    }

    if (source.startsWith(delimiter, index)) {
      out.write(delimiter);
      return index + delimiter.length;
    }

    // An unterminated single-line string must not swallow the rest of the file.
    if (!triple && char == '\n') {
      out.write(char);
      return index + 1;
    }

    out.write(char);
    index++;
  }
  return index;
}

/// Copies a `${...}` interpolation, nested braces and nested strings included.
int _copyInterpolation(String source, StringBuffer out, int start) {
  out.write(r'${');
  var index = start + 2;
  var depth = 1;

  while (index < source.length) {
    final char = source[index];
    if (char == "'" || char == '"') {
      index = _copyString(source, out, index);
      continue;
    }
    if (char == '{') {
      depth++;
    } else if (char == '}') {
      depth--;
      out.write(char);
      index++;
      if (depth == 0) return index;
      continue;
    }
    out.write(char);
    index++;
  }
  return index;
}

/// `r'...'` / `R"..."` — no escapes and no interpolation inside.
bool _isRawPrefix(String source, int quoteIndex) {
  if (quoteIndex == 0) return false;
  final prefix = source[quoteIndex - 1];
  if (prefix != 'r' && prefix != 'R') return false;
  if (quoteIndex < 2) return true;
  return !RegExp(r'[\w$]').hasMatch(source[quoteIndex - 2]);
}

/// Runs [sources] (`filename` -> source text) through the real guard on a
/// throwaway tree, so the pinned samples exercise the same code path `lib/`
/// does — including the `file:line` it reports.
List<String> scanSamples(Map<String, String> sources) {
  final root = Directory.systemTemp.createTempSync('dead_control_samples');
  try {
    sources.forEach((name, source) {
      File('${root.path}/$name.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync(source);
    });
    return findDeadControls(root);
  } finally {
    root.deleteSync(recursive: true);
  }
}

/// One pinned sample per banned shape. Every one of these must be flagged.
const Map<String, String> bannedSamples = {
  'pressed_empty': 'onPressed: () {},',
  'pressed_arrow_empty': 'onPressed: () => {},',
  'tap_empty': 'onTap: () {},',
  'changed_empty': 'onChanged: (_) {},',
  'default_empty': 'onPressed: onAction ?? () {},',
  'default_async_empty': 'onPressed: onAction ?? () async {},',
  'pressed_multiline': 'onPressed: () {\n  },',
  'pressed_comment_only': 'onPressed: () {\n  // TODO: wire this up\n},',
  'pressed_block_comment_only': 'onPressed: () {\n  /* nothing yet */\n},',
  'pressed_async': 'onPressed: () async {},',
  'pressed_async_multiline': 'onPressed: () async {\n  },',
  'tap_arrow_empty': 'onTap: () => {},',
  'changed_arrow_null': 'onChanged: (value) => null,',
  'longpress_arrow_empty': 'onLongPress: () => {},',
  'submitted_arrow_empty': 'onSubmitted: (text) => {},',
  'typed_param_empty': 'onChanged: (String? value) {},',
  'many_params_empty': 'onChanged: (_, __) {},',
};

/// Legitimate shapes. None of these may ever be flagged.
const Map<String, String> allowedSamples = {
  'disabled_null': 'onPressed: null,',
  'named_callback': 'onPressed: _save,',
  'arrow_with_body': 'onPressed: () => Navigator.pop(context),',
  'multiline_with_body': 'onPressed: () {\n  _save();\n},',
  'arrow_with_call': 'onPressed: () => _save(),',
  'ternary_disable': 'onPressed: canSave ? _save : null,',
  'nested_callback':
      'onPressed: () => showDialog<void>(context: context, builder: (_) => ok),',
  'async_with_body': 'onTap: () async {\n  await _load();\n},',
  'url_string': "final url = 'http://example.com';\nvoid f() {}",
  'commented_out_pressed': '// onPressed: () {},\nonPressed: _save,',
  'block_commented_pressed': '/* onPressed: () {}, */\nonPressed: _save,',
};

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

  test('every banned shape is flagged by the real scan', () {
    final missed = bannedSamples.entries
        .where((entry) => scanSamples({entry.key: entry.value}).isEmpty)
        .map((entry) => '"${entry.key}" missed in `${entry.value}`')
        .toList();

    expect(
      missed,
      isEmpty,
      reason:
          'These dead-control shapes got past the guard:\n${missed.join('\n')}',
    );
  });

  test('legitimate shapes are never flagged', () {
    final flagged = allowedSamples.entries
        .where((entry) => scanSamples({entry.key: entry.value}).isNotEmpty)
        .map((entry) => '"${entry.key}" flagged in `${entry.value}`')
        .toList();

    expect(
      flagged,
      isEmpty,
      reason:
          'False positives make the guard untrustworthy:\n'
          '${flagged.join('\n')}',
    );
  });

  test('violations are reported with the line they are on', () {
    const source =
        "class W extends Widget {\n"
        "  final button = TextButton(\n"
        "    onPressed: () {\n"
        "      // TODO\n"
        "    },\n"
        "  );\n"
        "}\n";

    final hits = findDeadControlsInText(source);

    expect(hits, hasLength(1));
    expect(hits.single.line, 3);
  });

  test('comment stripping keeps every offset and every string intact', () {
    const source =
        "// a\n"
        "final a = 'http://x//y';\n"
        "final b = \"/* not a comment */\";\n"
        'final c = r"\\d+ // raw";\n'
        'final d = "\${map["k"]}";\n'
        'final e = 1; // real comment\n'
        '/* block\n   spanning */\n';

    final stripped = stripDartComments(source);

    expect(
      stripped.length,
      source.length,
      reason: 'offsets must survive stripping',
    );
    expect(stripped.split('\n').length, source.split('\n').length);
    expect(stripped, contains("'http://x//y'"));
    expect(stripped, contains('/* not a comment */'));
    expect(stripped, contains('// raw'));
    expect(stripped, contains('"\${map["k"]}"'));
    expect(stripped, isNot(contains('// a')));
    expect(stripped, isNot(contains('real comment')));
    expect(stripped, isNot(contains('spanning')));
  });
}
