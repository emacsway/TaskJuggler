import { hoverTooltip, Tooltip } from '@codemirror/view';
import { Extension } from '@codemirror/state';

/**
 * CodeMirror extension that shows TJP keyword documentation on hover.
 * Includes a "docs" link that triggers the onOpenDocs callback.
 */
export function tjpHover(
  getDocs: () => Record<string, string>,
  onOpenDocs?: (keyword: string) => void
): Extension {
  return hoverTooltip((view, pos) => {
    const { from, text } = view.state.doc.lineAt(pos);
    const lineText = text;

    let start = pos - from;
    let end = pos - from;
    while (start > 0 && /[\w.]/.test(lineText[start - 1])) start--;
    while (end < lineText.length && /[\w.]/.test(lineText[end])) end++;

    const word = lineText.slice(start, end).toLowerCase();
    if (!word || word.length < 2) return null;

    const docs = getDocs();
    const baseWord = word.split('.')[0];
    const doc = docs[word] || docs[baseWord];
    if (!doc) return null;

    const lookupKey = docs[word] ? word : baseWord;

    return {
      pos: from + start,
      end: from + end,
      above: true,
      create() {
        const dom = document.createElement('div');
        dom.style.cssText = `
          max-width: 420px;
          padding: 6px 10px;
          font-size: 12px;
          line-height: 1.4;
          color: #ccc;
          background: #252526;
          border: 1px solid #3c3c3c;
          border-radius: 4px;
          box-shadow: 0 4px 12px rgba(0,0,0,0.4);
        `;

        const keyword = document.createElement('strong');
        keyword.textContent = word;
        keyword.style.color = '#4fc1ff';

        const text = document.createElement('span');
        text.textContent = ' — ' + doc;

        dom.appendChild(keyword);
        dom.appendChild(text);

        if (onOpenDocs) {
          const link = document.createElement('a');
          link.textContent = '[docs]';
          link.style.cssText = 'color: #4fc1ff; cursor: pointer; margin-left: 4px; text-decoration: underline;';
          link.addEventListener('mousedown', (e) => {
            e.preventDefault();
            onOpenDocs(lookupKey);
          });
          dom.appendChild(link);
        }

        return { dom };
      },
    } as Tooltip;
  });
}
