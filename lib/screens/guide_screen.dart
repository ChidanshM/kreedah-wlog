import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../theme.dart';

/// Renders the bundled user guide.
///
/// The guide ships inside the app rather than as a link, because the app
/// makes no network requests and requests no permissions (sub-app principle
/// 3). It reads the same `docs/USER-GUIDE.md` that lives in the repository,
/// so there is one copy and it cannot drift.
///
/// The renderer below handles the small subset of Markdown the guide uses.
/// A package would handle more, but every dependency is another way for the
/// build to break on a machine nobody can inspect.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User guide')),
      body: FutureBuilder<String>(
        future: rootBundle.loadString('docs/USER-GUIDE.md'),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(Bv.s5),
                child: Text('The guide could not be loaded.'),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(Bv.s4, Bv.s4, Bv.s4, Bv.s6),
            children: _render(context, snap.data!),
          );
        },
      ),
    );
  }
}

TextSpan _inline(String s, TextStyle base) {
  final spans = <TextSpan>[];
  final re = RegExp(r'\*\*(.+?)\*\*|`(.+?)`');
  var idx = 0;
  for (final m in re.allMatches(s)) {
    if (m.start > idx) spans.add(TextSpan(text: s.substring(idx, m.start)));
    if (m.group(1) != null) {
      spans.add(TextSpan(
          text: m.group(1),
          style: const TextStyle(fontWeight: FontWeight.w600)));
    } else {
      spans.add(TextSpan(
          text: m.group(2),
          style: const TextStyle(
              fontFamily: 'monospace', color: Bv.forest700, fontSize: 14)));
    }
    idx = m.end;
  }
  if (idx < s.length) spans.add(TextSpan(text: s.substring(idx)));
  return TextSpan(style: base, children: spans);
}

List<Widget> _render(BuildContext context, String md) {
  final out = <Widget>[];
  final lines = md.split('\n');
  final para = <String>[];
  var i = 0;

  void flush() {
    if (para.isEmpty) return;
    out.add(Padding(
      padding: const EdgeInsets.only(bottom: Bv.s3),
      child: RichText(text: _inline(para.join(' '), BvType.bodyMd)),
    ));
    para.clear();
  }

  Widget heading(String text, TextStyle style, double top) => Padding(
        padding: EdgeInsets.only(top: top, bottom: Bv.s2),
        child: Text(text, style: style),
      );

  while (i < lines.length) {
    final raw = lines[i];
    final t = raw.trim();

    if (t.isEmpty) {
      flush();
      i++;
      continue;
    }

    if (t.startsWith('```')) {
      flush();
      i++;
      final buf = <String>[];
      while (i < lines.length && !lines[i].trim().startsWith('```')) {
        buf.add(lines[i]);
        i++;
      }
      i++;
      out.add(Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: Bv.s3),
        padding: const EdgeInsets.all(Bv.s3),
        decoration: BoxDecoration(
          color: Bv.cream200,
          borderRadius: BorderRadius.circular(Bv.rMd),
          border: Border.all(color: Bv.cream400),
        ),
        child: Text(buf.join('\n'),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
      ));
      continue;
    }

    if (t == '---') {
      flush();
      out.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: Bv.s4),
        child: Divider(),
      ));
      i++;
      continue;
    }

    if (t.startsWith('### ')) {
      flush();
      out.add(heading(t.substring(4), BvType.bodyMd.copyWith(
          fontWeight: FontWeight.w600, color: Bv.textPrimary, fontSize: 16),
          Bv.s3));
      i++;
      continue;
    }
    if (t.startsWith('## ')) {
      flush();
      out.add(heading(t.substring(3), BvType.headlineSm, Bv.s4));
      i++;
      continue;
    }
    if (t.startsWith('# ')) {
      flush();
      out.add(heading(t.substring(2), BvType.headlineMd, 0));
      i++;
      continue;
    }

    if (t.startsWith('> ')) {
      flush();
      final buf = <String>[];
      while (i < lines.length && lines[i].trim().startsWith('>')) {
        buf.add(lines[i].trim().replaceFirst(RegExp(r'^>\s?'), ''));
        i++;
      }
      out.add(Container(
        margin: const EdgeInsets.only(bottom: Bv.s3),
        padding: const EdgeInsets.fromLTRB(Bv.s3, Bv.s3, Bv.s3, Bv.s3),
        decoration: BoxDecoration(
          color: Bv.blush200,
          borderRadius: BorderRadius.circular(Bv.rMd),
          border: const Border(left: BorderSide(color: Bv.sage600, width: 3)),
        ),
        child: RichText(
            text: _inline(buf.where((e) => e.isNotEmpty).join(' '),
                BvType.bodySm.copyWith(color: Bv.textPrimary))),
      ));
      continue;
    }

    if (t.startsWith('- ')) {
      flush();
      while (i < lines.length && lines[i].trim().startsWith('- ')) {
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: Bv.s2, left: Bv.s2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 7, right: Bv.s2),
                child: Icon(Icons.circle, size: 6, color: Bv.sage600),
              ),
              Expanded(
                child: RichText(
                    text: _inline(lines[i].trim().substring(2), BvType.bodyMd)),
              ),
            ],
          ),
        ));
        i++;
      }
      continue;
    }

    if (t.startsWith('|')) {
      flush();
      final rows = <List<String>>[];
      while (i < lines.length && lines[i].trim().startsWith('|')) {
        final cells = lines[i]
            .trim()
            .split('|')
            .map((e) => e.trim())
            .toList();
        cells.removeWhere((e) => e.isEmpty && cells.indexOf(e) == 0);
        final clean =
            cells.where((e) => true).toList()..removeWhere((e) => e.isEmpty);
        if (clean.isNotEmpty &&
            !clean.every((e) => RegExp(r'^:?-{2,}:?$').hasMatch(e))) {
          rows.add(clean);
        }
        i++;
      }
      if (rows.isNotEmpty) {
        final cols = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
        out.add(Container(
          margin: const EdgeInsets.only(bottom: Bv.s3),
          decoration: BoxDecoration(
            border: Border.all(color: Bv.cream400),
            borderRadius: BorderRadius.circular(Bv.rMd),
          ),
          child: Table(
            border: TableBorder.symmetric(
                inside: const BorderSide(color: Bv.cream400)),
            children: [
              for (var r = 0; r < rows.length; r++)
                TableRow(
                  decoration: r == 0
                      ? const BoxDecoration(color: Bv.cream100)
                      : null,
                  children: [
                    for (var c = 0; c < cols; c++)
                      Padding(
                        padding: const EdgeInsets.all(Bv.s2),
                        child: RichText(
                          text: _inline(
                            c < rows[r].length ? rows[r][c] : '',
                            r == 0
                                ? BvType.bodySm.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: Bv.textPrimary)
                                : BvType.bodySm,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ));
      }
      continue;
    }

    para.add(t);
    i++;
  }

  flush();
  return out;
}
