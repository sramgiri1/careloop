const VALID_FREQUENCIES = new Set(["NONE", "DAILY", "WEEKLY", "MONTHLY", "CUSTOM"]);
const VALID_WEEKDAYS = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
const WEEKDAY_INDEX = Object.fromEntries(VALID_WEEKDAYS.map((day, index) => [day, index]));

function parseDate(value, fieldName) {
  if (!value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new Error(`${fieldName} must be a valid ISO8601 date`);
  }
  return date;
}

export function normalizeRecurrenceInput(raw) {
  if (raw == null) {
    return {
      frequency: "NONE",
      interval: null,
      weekdays: [],
      endsAt: null,
    };
  }

  if (typeof raw !== "object" || Array.isArray(raw)) {
    throw new Error("recurrence must be an object");
  }

  const frequency = String(raw.frequency ?? "NONE").toUpperCase();
  if (!VALID_FREQUENCIES.has(frequency)) {
    throw new Error("recurrence.frequency must be one of NONE, DAILY, WEEKLY, MONTHLY, CUSTOM");
  }

  if (frequency === "NONE") {
    return {
      frequency,
      interval: null,
      weekdays: [],
      endsAt: null,
    };
  }

  const interval = Number.isInteger(raw.interval) ? raw.interval : 1;
  if (interval < 1) {
    throw new Error("recurrence.interval must be a positive integer");
  }

  const weekdays = Array.isArray(raw.weekdays)
    ? [...new Set(raw.weekdays.map((value) => String(value).toUpperCase()))]
    : [];

  for (const weekday of weekdays) {
    if (!WEEKDAY_INDEX.hasOwnProperty(weekday)) {
      throw new Error("recurrence.weekdays must use SUN, MON, TUE, WED, THU, FRI, SAT");
    }
  }

  if (frequency !== "WEEKLY" && weekdays.length > 0) {
    throw new Error("recurrence.weekdays is only valid for WEEKLY recurrence");
  }

  const endsAt = parseDate(raw.endsAt, "recurrence.endsAt");

  return {
    frequency,
    interval,
    weekdays,
    endsAt,
  };
}

export function recurrenceFields(normalized, seriesId = null) {
  if (!normalized || normalized.frequency === "NONE") {
    return {
      recurrenceFrequency: "NONE",
      recurrenceInterval: null,
      recurrenceWeekdays: [],
      recurrenceEndsAt: null,
      seriesId: null,
    };
  }

  return {
    recurrenceFrequency: normalized.frequency,
    recurrenceInterval: normalized.interval,
    recurrenceWeekdays: normalized.weekdays,
    recurrenceEndsAt: normalized.endsAt,
    seriesId,
  };
}

export function isRecurringTask(task) {
  return task.recurrenceFrequency && task.recurrenceFrequency !== "NONE" && Boolean(task.dueAt);
}

export function isTerminalTaskStatus(status) {
  return status === "DONE" || status === "SKIPPED";
}

function addDays(date, count) {
  const next = new Date(date);
  next.setUTCDate(next.getUTCDate() + count);
  return next;
}

function addMonths(date, count) {
  const next = new Date(date);
  next.setUTCMonth(next.getUTCMonth() + count);
  return next;
}

function nextWeeklyWithWeekdays(date, interval, weekdays) {
  const currentWeekday = date.getUTCDay();
  const sorted = weekdays.map((day) => WEEKDAY_INDEX[day]).sort((lhs, rhs) => lhs - rhs);

  for (const weekday of sorted) {
    if (weekday > currentWeekday) {
      return addDays(date, weekday - currentWeekday);
    }
  }

  const firstWeekday = sorted[0];
  const daysUntilNextCycle = (7 * interval) - currentWeekday + firstWeekday;
  return addDays(date, daysUntilNextCycle);
}

export function nextDueAtForTask(task) {
  if (!isRecurringTask(task) || !task.dueAt) return null;

  const interval = Math.max(1, task.recurrenceInterval ?? 1);
  let nextDueAt = null;

  switch (task.recurrenceFrequency) {
  case "DAILY":
    nextDueAt = addDays(task.dueAt, interval);
    break;
  case "WEEKLY":
    nextDueAt = task.recurrenceWeekdays?.length
      ? nextWeeklyWithWeekdays(task.dueAt, interval, task.recurrenceWeekdays)
      : addDays(task.dueAt, 7 * interval);
    break;
  case "MONTHLY":
    nextDueAt = addMonths(task.dueAt, interval);
    break;
  case "CUSTOM":
    nextDueAt = addDays(task.dueAt, interval);
    break;
  default:
    nextDueAt = null;
  }

  if (!nextDueAt) return null;
  if (task.recurrenceEndsAt && nextDueAt > task.recurrenceEndsAt) return null;
  return nextDueAt;
}
