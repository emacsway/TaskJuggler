import { Diagnostic } from '@codemirror/lint';
import { EditorView } from '@codemirror/view';
import { DiagnosticMessage } from '../../core/models';

/**
 * Converts backend DiagnosticMessages for a specific file into
 * CodeMirror Diagnostic objects for inline squiggly-line display.
 */
export function mapDiagnostics(
  view: EditorView,
  messages: DiagnosticMessage[],
  filePath: string
): Diagnostic[] {
  const doc = view.state.doc;
  const diagnostics: Diagnostic[] = [];

  for (const msg of messages) {
    if (msg.file !== filePath || msg.line == null) continue;

    const lineNum = Math.min(msg.line, doc.lines);
    if (lineNum < 1) continue;

    const line = doc.line(lineNum);
    const from = line.from + (msg.column != null ? Math.min(msg.column, line.length) : 0);
    const to = line.to;

    diagnostics.push({
      from,
      to: Math.max(from + 1, to),
      severity: msg.type === 'error' || msg.type === 'fatal' ? 'error' : 'warning',
      message: msg.message,
      source: `tj3 [${msg.id}]`,
    });
  }

  return diagnostics;
}
