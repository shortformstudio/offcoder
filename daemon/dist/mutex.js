export class Mutex {
    tail = Promise.resolve();
    acquire(job) {
        const run = this.tail.then(job);
        this.tail = run.then(() => undefined, () => undefined);
        return run;
    }
    acquireSync(job) {
        return this.acquire(async () => job());
    }
}
