import { EventEmitter } from 'node:events';

export interface TaskEvent {
  taskId: string;
  status: string;
  targetWorker: string;
  operationMode: string;
  targetFile: string;
  at: number;
}

export const taskEvents = new EventEmitter();
taskEvents.setMaxListeners(16);
