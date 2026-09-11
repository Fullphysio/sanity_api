final RegExp _newline = RegExp('\\r\\n|[\\n\\r\\u2028\\u2029]');

class _Location {
  const _Location(this.line, this.column);
  final int line;
  final int column;
}

/// Renders [query] around [start]–[end] with a caret marker and [message],
/// in the style of a compiler diagnostic.
String codeFrame(String query, int start, int? end, [String? message]) {
  final lines = query.split(_newline);
  final startLoc = _columnToLine(start, lines);
  final endLoc = end == null ? startLoc : _columnToLine(end, lines);

  final frame = _markerLines(startLoc, endLoc, lines);
  final frameStart = frame.start;
  final frameEnd = frame.end;
  final markerLines = frame.markerLines;

  final numberMaxWidth = '$frameEnd'.length;
  final rendered = <String>[];
  final windowed = lines.take(frameEnd).skip(frameStart).toList();

  for (var index = 0; index < windowed.length; index++) {
    final line = windowed[index];
    final number = frameStart + 1 + index;
    final padded = ' $number';
    final paddedNumber = padded.substring(
      padded.length - numberMaxWidth < 0 ? 0 : padded.length - numberMaxWidth,
    );
    final gutter = ' $paddedNumber |';
    final hasMarker = markerLines[number];
    final lastMarkerLine = !markerLines.containsKey(number + 1);

    if (hasMarker == null) {
      rendered.add(' $gutter${line.isNotEmpty ? ' $line' : ''}');
      continue;
    }

    var markerLine = '';
    if (hasMarker is List<int>) {
      final cut = hasMarker[0] - 1 < 0 ? 0 : hasMarker[0] - 1;
      final markerSpacing = line
          .substring(0, cut > line.length ? line.length : cut)
          .replaceAll(RegExp(r'[^\t]'), ' ');
      final numberOfMarkers = hasMarker[1] == 0 ? 1 : hasMarker[1];
      markerLine = [
        '\n ',
        gutter.replaceAll(RegExp(r'\d'), ' '),
        ' ',
        markerSpacing,
        '^' * numberOfMarkers,
      ].join();
      if (lastMarkerLine && message != null) markerLine += ' $message';
    }
    rendered.add(
      ['>', gutter, line.isNotEmpty ? ' $line' : '', markerLine].join(),
    );
  }

  return rendered.join('\n');
}

class _Frame {
  const _Frame(this.start, this.end, this.markerLines);
  final int start;
  final int end;
  final Map<int, Object> markerLines;
}

_Frame _markerLines(_Location startLoc, _Location endLoc, List<String> source) {
  const linesAbove = 2;
  const linesBelow = 3;
  final startLine = startLoc.line;
  final startColumn = startLoc.column;
  final endLine = endLoc.line;
  final endColumn = endLoc.column;

  var start = startLine - (linesAbove + 1);
  if (start < 0) start = 0;
  var end = endLine + linesBelow;
  if (end > source.length) end = source.length;

  final lineDiff = endLine - startLine;
  final markerLines = <int, Object>{};

  if (lineDiff != 0) {
    for (var i = 0; i <= lineDiff; i++) {
      final lineNumber = i + startLine;
      if (startColumn == 0) {
        markerLines[lineNumber] = true;
      } else if (i == 0) {
        final sourceLength = source[lineNumber - 1].length;
        markerLines[lineNumber] = [startColumn, sourceLength - startColumn + 1];
      } else if (i == lineDiff) {
        markerLines[lineNumber] = [0, endColumn];
      } else {
        final sourceLength = source[lineNumber - i].length;
        markerLines[lineNumber] = [0, sourceLength];
      }
    }
  } else if (startColumn == endColumn) {
    markerLines[startLine] = startColumn != 0 ? [startColumn, 0] : true;
  } else {
    markerLines[startLine] = [startColumn, endColumn - startColumn];
  }

  return _Frame(start, end, markerLines);
}

_Location _columnToLine(int column, List<String> lines) {
  var offset = 0;
  for (var i = 0; i < lines.length; i++) {
    final lineLength = lines[i].length + 1;
    if (offset + lineLength > column) {
      return _Location(i + 1, column - offset);
    }
    offset += lineLength;
  }
  return _Location(lines.length, lines.isEmpty ? 0 : lines.last.length);
}
