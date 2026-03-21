export interface Task {
  id: string;
  name: string;
  parentId: string | null;
  children: string[];
  level: number;
  isLeaf: boolean;
  isMilestone: boolean;
  isContainer: boolean;
  start: string | null;
  end: string | null;
  effort: number | null;
  duration: number | null;
  complete: number | null;
  priority: number;
  scheduled: boolean;
  responsible: string[];
  assignedResources: string[];
  depends: TaskDependency[];
  precedes: TaskDependency[];
  flags: string[];
  note: string | null;
  sourceFile: string | null;
  sourceLine: number | null;
}

export interface TaskDependency {
  taskId: string | null;
  onEnd: boolean;
  gapDuration: number;
  gapLength: number;
}
