export interface GanttData {
  projectStart: string;
  projectEnd: string;
  now: string;
  tasks: GanttTask[];
}

export interface GanttTask {
  taskId: string;
  name: string;
  level: number;
  isMilestone: boolean;
  isContainer: boolean;
  start: string;
  end: string;
  complete: number;
  dependencies: GanttDependency[];
  assignedResources: string[];
  sourceFile: string | null;
  sourceLine: number | null;
}

export interface GanttDependency {
  fromTaskId: string;
  toTaskId: string | null;
  onEnd: boolean;
}
