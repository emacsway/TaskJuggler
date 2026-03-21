import { CompletionContext, CompletionResult, autocompletion, Completion } from '@codemirror/autocomplete';
import { Extension } from '@codemirror/state';

export interface NamedId {
  id: string;
  name: string;
}

export interface AutocompleteContext {
  tasks: NamedId[];
  resources: NamedId[];
  /** context name -> valid child keywords */
  contextMap: Record<string, string[]>;
  /** keyword -> valid enum values */
  valueMap: Record<string, string[]>;
}

export function tjpAutocomplete(
  getData: () => AutocompleteContext,
  onPertRequest?: () => void
): Extension {
  return autocompletion({
    override: [
      (ctx: CompletionContext): CompletionResult | null => {
        const word = ctx.matchBefore(/[\w./"]+/);
        if (!word && !ctx.explicit) return null;

        const from = word?.from ?? ctx.pos;
        const data = getData();
        const context = detectContext(ctx);
        const options = buildOptions(context, data, onPertRequest);

        return { from, options, validFor: /^[\w./"]*$/ };
      },
    ],
  });
}

type ContextType =
  | { kind: 'block'; name: string }
  | { kind: 'after_keyword'; name: string };

function detectContext(ctx: CompletionContext): ContextType {
  const doc = ctx.state.doc;
  const pos = ctx.pos;
  const textBefore = doc.sliceString(0, pos);

  const line = doc.lineAt(pos);
  const lineText = line.text.substring(0, pos - line.from);
  const trimmed = lineText.trimStart();

  // After a keyword on the same line (e.g. "select |", "depends |", "allocate |")
  const afterMatch = trimmed.match(/\b(\w+)\s/);
  if (afterMatch) {
    const kw = afterMatch[1].toLowerCase();
    return { kind: 'after_keyword', name: kw };
  }

  // Find enclosing block
  const BLOCK_KEYWORDS = new Set([
    'task', 'resource', 'account', 'shift', 'scenario', 'project',
    'supplement', 'taskreport', 'resourcereport', 'textreport',
    'tracereport', 'accountreport', 'icalreport', 'nikureport', 'export',
    'allocate', 'limits', 'navigator', 'columns', 'booking',
  ]);

  let depth = 0;
  let enclosingKeyword = '';

  for (let i = pos - 1; i >= 0; i--) {
    const ch = textBefore[i];
    if (ch === '}') depth++;
    if (ch === '{') {
      if (depth > 0) {
        depth--;
      } else {
        // Look at just the line containing this '{' to find the block keyword
        const before = textBefore.substring(0, i);
        const lastNewline = before.lastIndexOf('\n');
        const braceLine = before.substring(lastNewline + 1).trim();

        // Find block keyword on this line
        const words = braceLine.split(/\s+/);
        for (const w of words) {
          if (BLOCK_KEYWORDS.has(w.toLowerCase())) {
            enclosingKeyword = w.toLowerCase();
            break;
          }
        }

        // If nothing found on brace line (e.g. lone '{' on its own line),
        // check the previous non-empty line
        if (!enclosingKeyword && braceLine === '') {
          const prevLines = before.trimEnd();
          const prevNewline = prevLines.lastIndexOf('\n');
          const prevLine = prevLines.substring(prevNewline + 1).trim();
          for (const w of prevLine.split(/\s+/)) {
            if (BLOCK_KEYWORDS.has(w.toLowerCase())) {
              enclosingKeyword = w.toLowerCase();
              break;
            }
          }
        }
        // Handle "supplement task" / "supplement resource"
        if (enclosingKeyword === 'supplement') {
          const supMatch = braceLine.match(/\bsupplement\s+(task|resource|account)\b/i);
          if (supMatch) enclosingKeyword = supMatch[1].toLowerCase();
        }
        break;
      }
    }
  }

  return { kind: 'block', name: enclosingKeyword || 'top' };
}

function buildOptions(
  context: ContextType,
  data: AutocompleteContext,
  onPertRequest?: () => void
): Completion[] {
  const options: Completion[] = [];

  if (context.kind === 'after_keyword') {
    const kw = context.name;

    // Keywords that expect task IDs — filterable by both id and name
    if (['depends', 'precedes'].includes(kw)) {
      options.push(...data.tasks.map(t => ({
        label: `${t.id} ${t.name}`,   // used for filtering (matches id OR name)
        displayLabel: `${t.id}  —  ${t.name}`,
        type: 'variable' as const,
        detail: 'task',
        boost: -t.id.length,
        apply: t.id,                   // only insert the id
      })));
      return options;
    }

    // Keywords that expect resource IDs — filterable by both id and name
    if (['allocate', 'alternative', 'responsible'].includes(kw)) {
      options.push(...data.resources.map(r => ({
        label: `${r.id} ${r.name}`,
        displayLabel: `${r.id}  —  ${r.name}`,
        type: 'variable' as const,
        detail: 'resource',
        boost: -r.id.length,
        apply: r.id,
      })));
      return options;
    }

    // Keywords with enum values from valueMap
    const values = data.valueMap[kw];
    if (values && values.length > 0) {
      options.push(...values
        .filter(v => v.length > 1 && !['{', '}', ',', '@', '*', '-', '+'].includes(v))
        .map(label => ({ label, type: 'enum' as const }))
      );
      return options;
    }

    // No specific after-keyword completions — fall through to block context
  }

  // Block context — look up children from contextMap
  const blockName = context.name;
  const contextMap = data.contextMap;

  // Get children for this block from the dynamic syntax data
  const children = contextMap[blockName];

  if (children && children.length > 0) {
    options.push(...children.map(label => ({ label, type: 'property' as const })));
  } else if (blockName === 'top' || !blockName) {
    // Fallback for top level: use keys that have children in contextMap (= block keywords)
    const topLevel = Object.keys(contextMap).filter(k =>
      ['project', 'task', 'resource', 'account', 'shift', 'scenario',
       'supplement', 'include', 'macro', 'vacation',
       'taskreport', 'resourcereport', 'textreport', 'tracereport',
       'accountreport', 'icalreport', 'nikureport', 'export',
       'navigator', 'tagfile', 'statussheet', 'timesheet',
      ].includes(k)
    );
    options.push(...topLevel.map(label => ({ label, type: 'keyword' as const })));
  }

  // Add PERT calculator in task context
  if (blockName === 'task' && onPertRequest) {
    options.push({
      label: 'effort',
      displayLabel: 'effort (PERT calculator)',
      type: 'keyword',
      detail: 'Ctrl+Shift+E',
      boost: 10,
      apply: (view: any, _c: any, from: number, to: number) => {
        view.dispatch({ changes: { from, to, insert: '' } });
        onPertRequest();
      },
    });
  }

  return options;
}
