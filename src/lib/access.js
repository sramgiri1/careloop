import { isCareReceiverActive } from "./receiver-state.js";

export function isActiveRecipientAccess(accessGrant) {
  return Boolean(accessGrant) && !accessGrant.revokedAt;
}

export function isCareOrganizer(member) {
  return member?.role === "ADMIN";
}

export function isCareReceiver(member) {
  return member?.role === "RECIPIENT";
}

export function canViewReceiver({ member, userId, receiver, accessGrant }) {
  if (!member || !receiver) return false;
  if (isCareOrganizer(member)) return member.circleId === receiver.circleId;
  if (isCareReceiver(member)) return receiver.receiverUserId === userId;
  return member.circleId === receiver.circleId && isActiveRecipientAccess(accessGrant);
}

export function canCreateTaskForReceiver({ member, receiver, accessGrant }) {
  if (!member || !receiver || !isCareReceiverActive(receiver)) return false;
  if (isCareOrganizer(member)) return member.circleId === receiver.circleId;
  if (isCareReceiver(member)) return false;
  return member.circleId === receiver.circleId && isActiveRecipientAccess(accessGrant);
}

export function canViewTask({ member, userId, task, receiver, accessGrant }) {
  if (!member || !task || !receiver) return false;
  if (isCareOrganizer(member)) return member.circleId === task.circleId;
  if (isCareReceiver(member)) {
    return receiver.receiverUserId === userId && task.assigneeId === userId;
  }
  if (!isActiveRecipientAccess(accessGrant)) return false;
  if (task.creatorId === userId) return true;
  if (task.assigneeId === userId) return true;
  return task.assigneeId === receiver.receiverUserId;
}

export function canEditTask({ member, userId, task }) {
  if (!member || !task) return false;
  if (isCareOrganizer(member)) return member.circleId === task.circleId;
  if (isCareReceiver(member)) return false;
  return task.creatorId === userId;
}

export function escalationUserIdsForTask({
  task,
  circleMembers,
  activeRecipientAccesses,
}) {
  const userIds = new Set();
  if (task?.assigneeId) {
    userIds.add(task.assigneeId);
  } else if (task?.creatorId) {
    userIds.add(task.creatorId);
  }

  for (const member of circleMembers ?? []) {
    if (member.role === "ADMIN") {
      userIds.add(member.userId);
      continue;
    }
    if (member.role !== "MEMBER") continue;
    const supportsReceiver = (activeRecipientAccesses ?? []).some((grant) =>
      grant.memberId === member.id
      && grant.recipientId === task.recipientId
      && !grant.revokedAt
    );
    if (supportsReceiver) {
      userIds.add(member.userId);
    }
  }

  return [...userIds];
}

const recipientOrder = [{ isPrimary: "desc" }, { sortOrder: "asc" }, { createdAt: "asc" }];

export async function loadReceiverAccessContext(db, { circleId, member, userId }) {
  const recipients = await db.careRecipient.findMany({
    where: { circleId },
    orderBy: recipientOrder,
    include: { entitlement: true },
  });

  if (isCareOrganizer(member)) {
    return {
      recipients,
      recipientIds: new Set(recipients.map((recipient) => recipient.id)),
      accessGrantByRecipientId: new Map(),
    };
  }

  if (isCareReceiver(member)) {
    const visibleRecipients = recipients.filter((recipient) => recipient.receiverUserId === userId);
    return {
      recipients: visibleRecipients,
      recipientIds: new Set(visibleRecipients.map((recipient) => recipient.id)),
      accessGrantByRecipientId: new Map(),
    };
  }

  const accessGrants = await db.careRecipientAccess.findMany({
    where: { memberId: member.id, revokedAt: null },
  });
  const accessGrantByRecipientId = new Map(
    accessGrants.map((grant) => [grant.recipientId, grant]),
  );
  const visibleRecipients = recipients.filter((recipient) => accessGrantByRecipientId.has(recipient.id));

  return {
    recipients: visibleRecipients,
    recipientIds: new Set(visibleRecipients.map((recipient) => recipient.id)),
    accessGrantByRecipientId,
  };
}

export function canAccessReceiverById(accessContext, recipientId) {
  if (!recipientId) return false;
  return accessContext.recipientIds.has(recipientId);
}

export function filterVisibleTasks(tasks, { member, userId, accessContext }) {
  const recipientById = new Map(accessContext.recipients.map((recipient) => [recipient.id, recipient]));
  return tasks.filter((task) => {
    const receiver = recipientById.get(task.recipientId);
    if (!receiver) return false;
    return canViewTask({
      member,
      userId,
      task,
      receiver,
      accessGrant: accessContext.accessGrantByRecipientId.get(task.recipientId) ?? null,
    });
  });
}

export function canCreateTaskWithAccess({ member, receiver, accessContext }) {
  return canCreateTaskForReceiver({
    member,
    receiver,
    accessGrant: accessContext.accessGrantByRecipientId.get(receiver.id) ?? null,
  });
}

export function eligibleAssigneeUserIdsForReceiver({
  member,
  receiver,
  circleMembers,
  activeRecipientAccesses,
}) {
  if (!member || !receiver) return [];
  const eligibleIds = new Set();
  const receiverUserId = receiver.receiverUserId;

  if (isCareOrganizer(member)) {
    for (const circleMember of circleMembers) {
      if (circleMember.role !== "RECIPIENT") {
        eligibleIds.add(circleMember.userId);
      }
    }
    if (receiverUserId) eligibleIds.add(receiverUserId);
    return [...eligibleIds];
  }

  if (isCareReceiver(member)) {
    if (receiverUserId) eligibleIds.add(receiverUserId);
    return [...eligibleIds];
  }

  eligibleIds.add(member.userId);
  if (receiverUserId) eligibleIds.add(receiverUserId);

  for (const circleMember of circleMembers) {
    if (circleMember.role === "ADMIN") {
      eligibleIds.add(circleMember.userId);
      continue;
    }
    if (circleMember.role !== "MEMBER") continue;
    if (circleMember.id === member.id) {
      eligibleIds.add(circleMember.userId);
      continue;
    }
    const hasReceiverAccess = activeRecipientAccesses.some((grant) =>
      grant.memberId === circleMember.id
      && grant.recipientId === receiver.id
      && !grant.revokedAt
    );
    if (hasReceiverAccess) {
      eligibleIds.add(circleMember.userId);
    }
  }

  return [...eligibleIds];
}

export function taskCapabilities({ member, userId, task, receiver, accessGrant }) {
  const canEdit = canEditTask({ member, userId, task });
  const isAssignedToSelf = task.assigneeId === userId;
  const isAssignedToReceiver = Boolean(receiver?.receiverUserId) && task.assigneeId === receiver.receiverUserId;
  const isUnassigned = !task.assigneeId;
  const isOrganizer = isCareOrganizer(member);
  const isReceiver = isCareReceiver(member);
  const isCaregiver = member?.role === "MEMBER";

  let canChangeStatus = false;
  let canMarkDone = false;
  let canSkip = false;

  if (isOrganizer) {
    canChangeStatus = true;
    canMarkDone = true;
    canSkip = true;
  } else if (isReceiver) {
    canMarkDone = isAssignedToSelf;
  } else if (isCaregiver && isActiveRecipientAccess(accessGrant)) {
    canMarkDone = isAssignedToSelf || isAssignedToReceiver;
    canChangeStatus = canMarkDone || (isUnassigned && task.creatorId === userId);
    canSkip = task.creatorId === userId && (isAssignedToSelf || isAssignedToReceiver || isUnassigned);
  }

  return {
    canEdit,
    canDelete: canEdit,
    canAssign: isOrganizer || (isCaregiver && task.creatorId === userId),
    canChangeRecipient: isOrganizer || (isCaregiver && task.creatorId === userId),
    canChangeStatus,
    canMarkDone,
    canSkip,
    canComment: true,
  };
}
