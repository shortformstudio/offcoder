import { EventEmitter } from 'node:events';
export const taskEvents = new EventEmitter();
taskEvents.setMaxListeners(16);
