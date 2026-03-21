export interface Account {
  id: string;
  name: string;
  parentId: string | null;
  children: string[];
  level: number;
  isLeaf: boolean;
  sourceFile: string | null;
  sourceLine: number | null;
}
