import { CompletionContext, CompletionResult, autocompletion } from '@codemirror/autocomplete';
import { Extension } from '@codemirror/state';

/**
 * Creates a CodeMirror autocomplete extension that suggests TJP keywords,
 * attributes, and project-specific task/resource IDs.
 */
export function tjpAutocomplete(getIds: () => { tasks: string[]; resources: string[] }): Extension {
  return autocompletion({
    override: [
      (ctx: CompletionContext): CompletionResult | null => {
        const word = ctx.matchBefore(/[\w.]+/);
        if (!word || (word.from === word.to && !ctx.explicit)) return null;

        const ids = getIds();
        const options = [
          // Keywords
          ...KEYWORDS.map(label => ({ label, type: 'keyword' as const })),
          // Attributes
          ...ATTRIBUTES.map(label => ({ label, type: 'property' as const })),
          // Task IDs
          ...ids.tasks.map(label => ({ label, type: 'variable' as const, detail: 'task' })),
          // Resource IDs
          ...ids.resources.map(label => ({ label, type: 'variable' as const, detail: 'resource' })),
        ];

        return { from: word.from, options, validFor: /^[\w.]*$/ };
      },
    ],
  });
}

const KEYWORDS = [
  'project', 'task', 'resource', 'account', 'shift', 'scenario',
  'supplement', 'include', 'macro', 'leave', 'booking', 'vacation',
  'taskreport', 'resourcereport', 'textreport', 'tracereport',
  'accountreport', 'navigator', 'export', 'tagfile', 'statussheet',
  'timesheet',
];

const ATTRIBUTES = [
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
  'selfcontained', 'auxdir', 'outputdir',
  'stdev', 'stdevincomplete', 'stdevleft',
  'effortdone', 'effortleft',
  'balance', 'chargeset', 'credits', 'endcredit',
  'active', 'alert', 'alertlevels', 'aggregate',
  'alternative', 'booking', 'email', 'fail', 'warn',
  'gapduration', 'gaplength', 'disabled', 'enabled',
  'daily', 'weekly', 'monthly', 'quarterly', 'yearly',
  'isactive', 'isdependencyof', 'isdutyof', 'ischildof',
];
