export interface LockHandle {
  done: () => void;
}

export class Mutex {
  private tail: Promise<void> = Promise.resolve();

  acquire<T>(job: () => Promise<T>): Promise<T> {
    const run = this.tail.then(job);
    this.tail = run.then(
      () => undefined,
      () => undefined
    );
    return run;
  }

  acquireSync<T>(job: () => T): Promise<T> {
    return this.acquire(async () => job());
  }
}
