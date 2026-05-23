import crypto from "crypto";
import https from "https";
import { Resend } from "resend";

const APNS_KEY_ID = process.env.APNS_KEY_ID || "";
const APNS_TEAM_ID = process.env.APNS_TEAM_ID || "";
const APNS_KEY = process.env.APNS_KEY || "";
const APNS_TOPIC = process.env.APNS_TOPIC || "com.careloop.ios";
const APNS_HOST = process.env.APNS_HOST || "api.sandbox.push.apple.com";
const RESEND_FROM = process.env.RESEND_FROM || "CareLoop <noreply@careloop.local>";

let cachedApnsToken = null;
let cachedApnsIssuedAt = 0;

function base64url(value) {
  return Buffer.from(value)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function hasApnsConfig() {
  return Boolean(APNS_KEY_ID && APNS_TEAM_ID && APNS_KEY);
}

function createApnsJwt() {
  const now = Math.floor(Date.now() / 1000);
  if (cachedApnsToken && now - cachedApnsIssuedAt < 3000) return cachedApnsToken;

  const header = base64url(JSON.stringify({ alg: "ES256", kid: APNS_KEY_ID }));
  const claims = base64url(JSON.stringify({ iss: APNS_TEAM_ID, iat: now }));
  const unsigned = `${header}.${claims}`;
  const signer = crypto.createSign("sha256");
  signer.update(unsigned);
  signer.end();
  const signature = signer.sign(APNS_KEY);
  cachedApnsIssuedAt = now;
  cachedApnsToken = `${unsigned}.${base64url(signature)}`;
  return cachedApnsToken;
}

function taskNotificationContent(type, taskTitle, extra) {
  switch (type) {
    case "assignment":
      return {
        title: "New CareLoop task",
        body: `You were assigned: ${taskTitle}`,
        emailSubject: `Assigned in CareLoop: ${taskTitle}`,
      };
    case "recipientAssignment":
      return {
        title: "A care reminder was set for you",
        body: taskTitle,
        emailSubject: `Care reminder: ${taskTitle}`,
      };
    case "recipientReminder":
      return {
        title: "Care reminder",
        body: taskTitle,
        emailSubject: `Care reminder: ${taskTitle}`,
      };
    case "escalation":
      return {
        title: "Task still needs attention",
        body: `${taskTitle} is still not done.`,
        emailSubject: `Escalation in CareLoop: ${taskTitle}`,
      };
    case "taskCompletedForRecipient":
      return {
        title: "Care task completed",
        body: `${extra ?? "Your caregiver"} completed: ${taskTitle}`,
        emailSubject: `CareLoop: "${taskTitle}" was completed`,
      };
    case "recipientCompletedTask":
      return {
        title: `${extra ?? "Care receiver"} completed a task`,
        body: taskTitle,
        emailSubject: `${extra ?? "Care receiver"} completed: ${taskTitle}`,
      };
    default:
      return {
        title: "Task reminder",
        body: `${taskTitle} is due soon.`,
        emailSubject: `Reminder from CareLoop: ${taskTitle}`,
      };
  }
}

async function sendApns({ pushToken, payload }) {
  if (!hasApnsConfig()) {
    return { delivered: false, simulated: true, channel: "PUSH", reason: "apns_not_configured", payload };
  }

  const body = JSON.stringify(payload);
  const token = createApnsJwt();

  return new Promise((resolve) => {
    const req = https.request(
      {
        hostname: APNS_HOST,
        path: `/3/device/${pushToken}`,
        method: "POST",
        headers: {
          authorization: `bearer ${token}`,
          "apns-topic": APNS_TOPIC,
          "content-type": "application/json",
          "content-length": Buffer.byteLength(body),
        },
      },
      (res) => {
        const chunks = [];
        res.on("data", (chunk) => chunks.push(chunk));
        res.on("end", () => {
          const responseBody = Buffer.concat(chunks).toString("utf8");
          if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) {
            resolve({ delivered: true, channel: "PUSH", statusCode: res.statusCode, responseBody });
            return;
          }
          resolve({
            delivered: false,
            channel: "PUSH",
            statusCode: res.statusCode ?? 500,
            responseBody,
            reason: "apns_request_failed",
          });
        });
      }
    );

    req.on("error", (error) => {
      resolve({ delivered: false, channel: "PUSH", reason: error.message });
    });
    req.write(body);
    req.end();
  });
}

async function sendEmail({ to, subject, html }) {
  const apiKey = process.env.RESEND_API_KEY || "";
  if (!apiKey) {
    return { delivered: true, simulated: true, channel: "EMAIL", messageId: null, reason: "resend_not_configured" };
  }

  const resend = new Resend(apiKey);
  const result = await resend.emails.send({
    from: RESEND_FROM,
    to,
    subject,
    html,
  });
  return {
    delivered: true,
    channel: "EMAIL",
    messageId: result.data?.id ?? result.id ?? null,
  };
}

function taskEmailHtml({ heading, taskTitle, body, circleName }) {
  return `<!DOCTYPE html>
<html lang="en">
<body style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; color: #0f172a;">
  <h2>${heading}</h2>
  <p>${body}</p>
  <p><strong>Task:</strong> ${taskTitle}</p>
  <p><strong>Circle:</strong> ${circleName}</p>
</body>
</html>`;
}

export async function deliverTaskNotification({ db, userId, task, type, extra }) {
  const user = await db.user.findUnique({ where: { id: userId } });
  if (!user) {
    return { delivered: false, channel: "NONE", reason: "user_not_found" };
  }

  // "recipientReminder" is a time-based care reminder sent to the recipient — treated as an
  // assignment-type notification so it respects the recipient's notifAssignments preference.
  const isAssignmentType = type === "assignment" || type === "recipientAssignment" ||
    type === "recipientReminder" || type === "taskCompletedForRecipient" || type === "recipientCompletedTask";
  const isEscalationType = type === "escalation";

  if (isAssignmentType && user.notifAssignments === false)
    return { delivered: false, channel: "NONE", reason: "notifications_disabled_by_user" };
  if (isEscalationType && user.notifEscalations === false)
    return { delivered: false, channel: "NONE", reason: "notifications_disabled_by_user" };

  const content = taskNotificationContent(type, task.title, extra);
  const payload = {
    aps: {
      alert: { title: content.title, body: content.body },
      sound: "default",
    },
    taskId: task.id,
    circleId: task.circleId ?? task.circle?.id ?? null,
    recipientId: task.recipientId ?? task.recipient?.id ?? null,
    type,
  };

  if (user.pushToken) {
    const pushResult = await sendApns({ pushToken: user.pushToken, payload });
    if (pushResult.delivered || pushResult.simulated) return pushResult;
  }

  if (!user.email) {
    return { delivered: false, channel: "NONE", reason: "no_push_token_or_email" };
  }

  try {
    return await sendEmail({
      to: user.email,
      subject: content.emailSubject,
      html: taskEmailHtml({
        heading: content.title,
        taskTitle: task.title,
        body: content.body,
        circleName: task.circle?.name ?? "CareLoop",
      }),
    });
  } catch (error) {
    return { delivered: false, channel: "EMAIL", reason: error.message };
  }
}

export async function sendReminderNotifications({ db, task, type, userIds }) {
  const deliveries = [];
  for (const userId of userIds) {
    deliveries.push(await deliverTaskNotification({ db, userId, task, type }));
  }
  return deliveries;
}

function digestHtml({ userName, digestDate, dueToday, overdue, completedToday }) {
  const section = (title, items) => `
    <h3>${title}</h3>
    ${items.length === 0 ? "<p>None</p>" : `<ul>${items.map((item) => `<li>${item.title}</li>`).join("")}</ul>`}
  `;

  return `<!DOCTYPE html>
<html lang="en">
<body style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; color: #0f172a;">
  <h2>CareLoop daily digest</h2>
  <p>${userName}, here is your update for ${digestDate}.</p>
  ${section("Due today", dueToday)}
  ${section("Overdue", overdue)}
  ${section("Completed today", completedToday)}
</body>
</html>`;
}

export async function sendDailyDigest({ user, dueToday, overdue, completedToday, digestDate }) {
  if (user.notifDigest === false) {
    return { delivered: false, channel: "NONE", reason: "notifications_disabled_by_user" };
  }

  if (!user.email) {
    return { delivered: false, channel: "NONE", reason: "user_has_no_email" };
  }

  try {
    return await sendEmail({
      to: user.email,
      subject: `CareLoop digest for ${digestDate}`,
      html: digestHtml({
        userName: user.name,
        digestDate,
        dueToday,
        overdue,
        completedToday,
      }),
    });
  } catch (error) {
    return { delivered: false, channel: "EMAIL", reason: error.message };
  }
}
