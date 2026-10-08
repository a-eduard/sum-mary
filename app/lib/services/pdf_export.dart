import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:http/http.dart' as http;

import '../models.dart';
import '../modes.dart';
import 'repo.dart';

/// Шаблоны PDF-конспекта.
enum PdfTemplate { notes, cheat, full }

extension PdfTemplateName on PdfTemplate {
  String get title => switch (this) {
        PdfTemplate.notes => 'Конспект',
        PdfTemplate.cheat => 'Шпаргалка',
        PdfTemplate.full => 'Полный — с расшифровкой',
      };
  String get hint => switch (this) {
        PdfTemplate.notes => 'Итог, главное в цвете, задачи и даты',
        PdfTemplate.cheat => 'Только определения, формулы и важное — мелко, на одну страницу',
        PdfTemplate.full => 'Конспект + текст записи по спикерам',
      };
}

/// Цветной PDF: определения синие, формулы в рамке, примеры курсивом,
/// «будет на контрольной» — красным, типичные ошибки — зелёным.
class PdfExport {
  static const _blue = PdfColor.fromInt(0xFF1F5BD6);
  static const _red = PdfColor.fromInt(0xFFC0263F);
  static const _green = PdfColor.fromInt(0xFF1F7A50);
  static const _violet = PdfColor.fromInt(0xFF5B4BDB);
  static const _muted = PdfColor.fromInt(0xFF5F6273);

  static Future<Uint8List> build(Recording r, Summary s, List<Segment> segs, PdfTemplate t, {String? folderName}) async {
    final regular = await PdfGoogleFonts.manropeRegular();
    final bold = await PdfGoogleFonts.manropeBold();
    final italic = await PdfGoogleFonts.robotoItalic();
    final head = await PdfGoogleFonts.unboundedBold();
    final cheat = t == PdfTemplate.cheat;
    final base = cheat ? 8.5 : 11.0;
    final doc = pw.Document(title: r.title, author: 'СамМари');
    // Запасные шрифты: верхние индексы (10⁻¹⁹), ∫, ≈, λ и прочие символы, которых нет в Manrope.
    final fallback = [await PdfGoogleFonts.notoSansRegular(), await PdfGoogleFonts.notoSansMathRegular()];
    final theme = pw.ThemeData.withFont(base: regular, bold: bold, italic: italic, fontFallback: fallback);
    final mode = modeById(r.mode);
    final date = DateFormat('d MMMM y, HH:mm', 'ru').format(r.recordedAt);

    // Фото доски (в шпаргалку не кладём — она на одну страницу).
    final figImgs = <String, pw.MemoryImage>{};
    if (!cheat) {
      await Future.wait(s.figures.map((f) async {
        try {
          final u = await Repo.photoUrl(f.key!);
          if (u == null) return;
          final res = await http.get(Uri.parse(u)).timeout(const Duration(seconds: 20));
          if (res.statusCode == 200) figImgs[f.key!] = pw.MemoryImage(res.bodyBytes);
        } catch (_) {}
      }));
    }
    List<pw.Widget> figs(Iterable<Figure> list) => [
          for (final f in list)
            if (figImgs[f.key] != null)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 6, bottom: 8),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.ClipRRect(horizontalRadius: 6, verticalRadius: 6,
                      child: pw.Image(figImgs[f.key]!, height: 210, fit: pw.BoxFit.contain)),
                  if (f.caption.isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 4),
                      child: pw.Text('${f.caption}${f.tSec == null ? '' : '  ${fmtDuration(f.tSec)}'}', style: pw.TextStyle(color: _muted, fontSize: base - 1.5)),
                    ),
                ]),
              ),
        ];

    pw.Widget h(String text) => pw.Padding(
          padding: pw.EdgeInsets.only(top: cheat ? 6 : 14, bottom: cheat ? 3 : 6),
          child: pw.Text(text.toUpperCase(),
              style: pw.TextStyle(font: head, fontSize: cheat ? 8 : 10, color: _violet, letterSpacing: .6)),
        );
    String ts(int? sec) => sec == null ? '' : '  ${(sec ~/ 60).toString().padLeft(2, '0')}:${(sec % 60).toString().padLeft(2, '0')}';

    pw.Widget point(KeyPoint k) {
      final time = pw.TextSpan(text: ts(k.tSec), style: pw.TextStyle(color: _muted, fontSize: base - 2));
      switch (k.kind) {
        case 'definition':
          return pw.RichText(text: pw.TextSpan(children: [
            pw.TextSpan(text: k.text, style: pw.TextStyle(color: _blue, fontWeight: pw.FontWeight.bold, fontSize: base)),
            time,
          ]));
        case 'formula':
          return pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black, width: .8), borderRadius: pw.BorderRadius.circular(4)),
            child: pw.Text(k.text, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: base)),
          );
        case 'example':
          return pw.RichText(text: pw.TextSpan(children: [
            pw.TextSpan(text: k.text, style: pw.TextStyle(font: italic, color: _muted, fontSize: base)),
            time,
          ]));
        case 'important':
          return pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFFCE8EC), borderRadius: pw.BorderRadius.circular(4)),
            child: pw.RichText(text: pw.TextSpan(children: [
              pw.TextSpan(text: 'Важно: ${k.text}', style: pw.TextStyle(color: _red, fontWeight: pw.FontWeight.bold, fontSize: base)),
              time,
            ])),
          );
        case 'mistake':
          return pw.RichText(text: pw.TextSpan(children: [
            pw.TextSpan(text: 'Частая ошибка: ${k.text}', style: pw.TextStyle(color: _green, fontWeight: pw.FontWeight.bold, fontSize: base)),
            time,
          ]));
        default:
          return pw.RichText(text: pw.TextSpan(children: [pw.TextSpan(text: '• ${k.text}', style: pw.TextStyle(fontSize: base)), time]));
      }
    }

    pw.Widget bullets(List<String> items) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (final i in items)
              pw.Padding(padding: const pw.EdgeInsets.only(bottom: 3), child: pw.Text('• $i', style: pw.TextStyle(fontSize: base))),
          ],
        );

    final points = cheat
        ? s.keyPoints.where((k) => k.kind == 'definition' || k.kind == 'formula' || k.kind == 'important' || k.kind == 'mistake').toList()
        : s.keyPoints;

    final body = <pw.Widget>[
      pw.Text(r.title, style: pw.TextStyle(font: head, fontSize: cheat ? 13 : 20)),
      pw.SizedBox(height: 4),
      pw.Text([mode.label, if (folderName != null) folderName, date].join(' · '), style: pw.TextStyle(color: _muted, fontSize: base - 1)),
      if (!cheat && s.summary.isNotEmpty) ...[h('Кратко'), pw.Text(s.summary, style: pw.TextStyle(fontSize: base, lineSpacing: 2))],
      if (points.isNotEmpty) ...[
        h(cheat ? 'Главное' : 'Главное'),
        for (final k in points) pw.Padding(padding: pw.EdgeInsets.only(bottom: cheat ? 3 : 6), child: point(k)),
      ],
      if (!cheat && s.explanations.isNotEmpty) ...[
        h('Мари объясняет'),
        for (final x in s.explanations)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('${x['topic'] ?? ''}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: base)),
              pw.Text('${x['answer'] ?? ''}', style: pw.TextStyle(fontSize: base)),
            ]),
          ),
      ],
      for (final (title, items) in s.sections)
        if (!cheat || title.toLowerCase().contains('контрольн')) ...[
          h(title),
          bullets(items),
          ...figs(s.figures.where((f) => f.section == title)),
        ],
      if (s.figures.any((f) => !s.sections.any((x) => x.$1 == f.section)) && figImgs.isNotEmpty) ...[
        h('С доски'),
        ...figs(s.figures.where((f) => !s.sections.any((x) => x.$1 == f.section))),
      ],
      if (s.events.isNotEmpty) ...[
        h('Даты'),
        bullets([for (final e in s.events) '${e.title} — ${DateFormat('d MMMM', 'ru').format(e.date)}${e.time == null ? '' : ', ${e.time}'}']),
      ],
      if (!cheat && s.decisions.isNotEmpty) ...[h('Решения'), bullets(s.decisions)],
      if (!cheat && s.openQuestions.isNotEmpty) ...[h('Открытые вопросы'), bullets(s.openQuestions)],
    ];

    if (t == PdfTemplate.full && segs.isNotEmpty) {
      body.add(h('Расшифровка'));
      // Реплика лекции может длиться полчаса — режем на абзацы, которые переносятся между страницами.
      for (final turn in groupTurns(segs)) {
        body.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4, bottom: 2),
          child: pw.RichText(text: pw.TextSpan(children: [
            pw.TextSpan(text: '${r.speakerName(turn.speaker)}  ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _violet, fontSize: base - 1)),
            pw.TextSpan(text: fmtMs(turn.startMs), style: pw.TextStyle(color: _muted, fontSize: base - 2)),
          ])),
        ));
        for (final chunk in _chunks(turn.text)) {
          body.add(pw.Paragraph(text: chunk, style: pw.TextStyle(fontSize: base - .5, lineSpacing: 1.5),
              margin: const pw.EdgeInsets.only(bottom: 4)));
        }
      }
    }

    doc.addPage(pw.MultiPage(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.all(cheat ? 22 : 40),
      footer: (c) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('СамМари · sum-mary.ru', style: pw.TextStyle(color: _muted, fontSize: 8)),
        pw.Text('${c.pageNumber} / ${c.pagesCount}', style: pw.TextStyle(color: _muted, fontSize: 8)),
      ]),
      build: (_) => body,
    ));
    return doc.save();
  }

  /// Делит длинный текст на абзацы ~700 символов по границам предложений.
  static List<String> _chunks(String text, {int max = 700}) {
    final sentences = text.split(RegExp(r'(?<=[.!?…])\s+'));
    final out = <String>[];
    var cur = StringBuffer();
    for (final s in sentences) {
      if (cur.length > 0 && cur.length + s.length > max) {
        out.add(cur.toString().trim());
        cur = StringBuffer();
      }
      // одно «предложение» без точек длиннее лимита — режем по словам
      if (s.length > max) {
        for (final w in s.split(' ')) {
          if (cur.length + w.length > max) {
            out.add(cur.toString().trim());
            cur = StringBuffer();
          }
          cur.write('$w ');
        }
      } else {
        cur.write('$s ');
      }
    }
    if (cur.toString().trim().isNotEmpty) out.add(cur.toString().trim());
    return out;
  }

  static String fileName(Recording r, PdfTemplate t) {
    final safe = r.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
    return '${t == PdfTemplate.cheat ? 'Шпаргалка' : 'Конспект'} — ${safe.isEmpty ? 'запись' : safe}.pdf';
  }
}
