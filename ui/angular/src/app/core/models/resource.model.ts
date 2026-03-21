export interface Resource {
  id: string;
  name: string;
  parentId: string | null;
  children: string[];
  level: number;
  isLeaf: boolean;
  email: string | null;
  efficiency: number | null;
  rate: number | null;
  sourceFile: string | null;
  sourceLine: number | null;
}
