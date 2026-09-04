export class InputError extends Error {}

function checkValue(desc, value, errs, label) {
  const t = desc.type;
  if (t === 'string') {
    if (typeof value !== 'string') {
      errs.push(`${label} must be a string`);
      return;
    }
    if (desc.minLength != null && value.length < desc.minLength) errs.push(`${label} must be at least ${desc.minLength} characters`);
    if (desc.maxLength != null && value.length > desc.maxLength) errs.push(`${label} exceeds maximum length ${desc.maxLength}`);
  } else if (t === 'integer' || t === 'number') {
    if (typeof value !== 'number' || Number.isNaN(value)) {
      errs.push(`${label} must be a number`);
      return;
    }
    if (t === 'integer' && !Number.isInteger(value)) errs.push(`${label} must be an integer`);
    if (desc.minimum != null && value < desc.minimum) errs.push(`${label} must be >= ${desc.minimum}`);
    if (desc.maximum != null && value > desc.maximum) errs.push(`${label} must be <= ${desc.maximum}`);
  } else if (t === 'boolean') {
    if (typeof value !== 'boolean') errs.push(`${label} must be a boolean`);
  } else if (t === 'array') {
    if (!Array.isArray(value)) errs.push(`${label} must be an array`);
  } else if (t === 'object') {
    if (typeof value !== 'object' || value === null || Array.isArray(value)) errs.push(`${label} must be an object`);
  }
  if (desc.enum && !desc.enum.includes(value)) errs.push(`${label} must be one of: ${desc.enum.join(', ')}`);
  if (desc.const !== undefined && value !== desc.const) errs.push(`${label} must equal ${JSON.stringify(desc.const)}`);
}

export function applyDefaults(schema, input = {}) {
  const out = { ...input };
  for (const [key, desc] of Object.entries(schema.properties ?? {})) {
    if (out[key] === undefined && desc.default !== undefined) out[key] = desc.default;
  }
  return out;
}

export function validate(schema, input) {
  const errs = [];
  if (typeof input !== 'object' || input === null || Array.isArray(input)) return ['arguments must be an object'];
  const props = schema.properties ?? {};
  if (schema.additionalProperties === false) {
    for (const key of Object.keys(input)) {
      if (!(key in props)) errs.push(`unknown argument "${key}"`);
    }
  }
  for (const key of schema.required ?? []) {
    if (input[key] === undefined) errs.push(`missing required argument "${key}"`);
  }
  for (const [key, value] of Object.entries(input)) {
    const desc = props[key];
    if (desc && value !== undefined) checkValue(desc, value, errs, `"${key}"`);
  }
  return errs;
}
