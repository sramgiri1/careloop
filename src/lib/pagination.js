const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 100;

function parsePositiveInt(value, fallback) {
  const parsed = Number.parseInt(String(value ?? ""), 10);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}

export function parseCursorPagination(query = {}, options = {}) {
  const enabled = query.limit !== undefined || query.cursor !== undefined;
  const defaultLimit = options.defaultLimit ?? DEFAULT_LIMIT;
  const maxLimit = options.maxLimit ?? MAX_LIMIT;
  const rawLimit = parsePositiveInt(query.limit, defaultLimit);
  const limit = Math.min(maxLimit, Math.max(1, rawLimit));
  const cursor = typeof query.cursor === "string" && query.cursor.trim()
    ? query.cursor.trim()
    : null;

  return {
    enabled,
    limit,
    cursor,
  };
}

export function prismaCursorWindow(pagination, multiplier = 1) {
  if (!pagination.enabled) return {};
  const take = Math.max(1, pagination.limit * multiplier + 1);
  return {
    take,
    ...(pagination.cursor ? { cursor: { id: pagination.cursor }, skip: 1 } : {}),
  };
}

export function pageResponse(items, pagination) {
  if (!pagination.enabled) return items;
  const pageItems = items.slice(0, pagination.limit);
  return {
    items: pageItems,
    nextCursor: items.length > pagination.limit ? pageItems.at(-1)?.id ?? null : null,
    hasMore: items.length > pagination.limit,
    limit: pagination.limit,
  };
}
