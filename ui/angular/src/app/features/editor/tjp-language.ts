import { LanguageSupport, StreamLanguage } from '@codemirror/language';

/**
 * Basic TJP/TJI syntax highlighting for CodeMirror 6.
 * Covers keywords, comments, strings, numbers with units, dates, macros.
 * TODO: Replace with full Lezer grammar for better parsing.
 */

const tjpKeywords = new Set([
  'project', 'task', 'resource', 'account', 'shift', 'scenario',
  'supplement', 'include', 'macro', 'leave', 'booking', 'vacation',
  'taskreport', 'resourcereport', 'textreport', 'tracereport',
  'accountreport', 'navigator', 'export', 'tagfile', 'statussheet',
  'timesheet', 'projectid', 'projectids',
]);

const tjpAttributes = new Set([
  'start', 'end', 'effort', 'duration', 'length', 'depends', 'precedes',
  'allocate', 'complete', 'note', 'priority', 'flags', 'milestone',
  'responsible', 'scheduling', 'limits', 'period', 'charge', 'journalentry',
  'purge', 'adopt', 'timezone', 'currency', 'rate', 'efficiency',
  'workinghours', 'dailyworkinghours', 'yearlyworkingdays', 'now',
  'extend', 'columns', 'formats', 'headline', 'caption', 'header',
  'footer', 'left', 'center', 'right', 'hideresource', 'hidetask',
  'hideaccount', 'sortresources', 'sorttasks', 'sortaccounts',
  'rollupresource', 'rolluptask', 'rollupaccount', 'loadunit',
  'timeformat', 'numberformat', 'currencyformat',
  'stdev', 'stdevincomplete', 'stdevleft',
  'effortdone', 'effortleft',
]);

const tjpStreamParser = {
  token(stream: any): string | null {
    // Skip whitespace
    if (stream.eatSpace()) return null;

    // Line comment
    if (stream.match('#')) {
      stream.skipToEnd();
      return 'comment';
    }

    // Block comment
    if (stream.match('/*')) {
      while (!stream.match('*/') && !stream.eol()) {
        stream.next();
      }
      return 'comment';
    }

    // Strings
    if (stream.match('"')) {
      while (!stream.eol()) {
        const ch = stream.next();
        if (ch === '"') break;
        if (ch === '\\') stream.next();
      }
      return 'string';
    }
    if (stream.match("'")) {
      while (!stream.eol()) {
        const ch = stream.next();
        if (ch === "'") break;
      }
      return 'string';
    }

    // Rich text (single-quoted with -8<- markers)
    if (stream.match('-8<-')) {
      stream.skipToEnd();
      return 'string';
    }

    // Macro reference ${...}
    if (stream.match('${')) {
      while (!stream.eol() && !stream.match('}')) {
        stream.next();
      }
      return 'variableName';
    }

    // Date (YYYY-MM-DD)
    if (stream.match(/\d{4}-\d{2}-\d{2}(-\d{2}:\d{2}(:\d{2})?)?/)) {
      return 'number';
    }

    // Number with unit
    if (stream.match(/\d+(\.\d+)?\s*[dwmyhmin]+/)) {
      return 'number';
    }

    // Plain number
    if (stream.match(/\d+(\.\d+)?/)) {
      return 'number';
    }

    // Identifiers and keywords
    if (stream.match(/[a-zA-Z_]\w*(\.[a-zA-Z_]\w*)*/)) {
      const word = stream.current().split('.')[0];
      if (tjpKeywords.has(word)) return 'keyword';
      if (tjpAttributes.has(word)) return 'propertyName';
      return 'variableName.definition';
    }

    // Braces
    if (stream.match(/[{}]/)) return 'brace';
    if (stream.match(/[[\]]/)) return 'squareBracket';
    if (stream.match(/[()]/)) return 'paren';

    // Operators
    if (stream.match(/[&|!=<>~]+/)) return 'operator';

    stream.next();
    return null;
  },
};

export function tjpLanguage(): LanguageSupport {
  return new LanguageSupport(StreamLanguage.define(tjpStreamParser));
}
