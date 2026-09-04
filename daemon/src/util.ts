export function unixNow(): number {
  return Math.floor(Date.now() / 1000);
}

export function unixMs(): number {
  return Date.now();
}
