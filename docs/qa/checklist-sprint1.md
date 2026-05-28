# CareLoop Sprint 1 QA Checklist

Date: 2026-04-26
Owner: SENTINEL
Scope: Sprint 1 core coordination

## Automated iOS XCTest

Command run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -project ios/CareLoop.xcodeproj \
  -scheme CareLoop \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Result:

- [x] `CareLoopTests` executed 22 tests with 0 failures
- [x] `CareTaskTests` passed
- [x] `TaskStatusTests` passed
- [x] `TaskPriorityTests` passed
- [x] `MemberRoleTests` passed
- [x] `AppStateRoleTests` passed

xcresult:

```text
/Users/sucheth/Library/Developer/Xcode/DerivedData/CareLoop-bxtprtmzxywmmzbakczvlqkjxgwc/Logs/Test/Test-CareLoop-2026.04.26_13-14-52--0400.xcresult
```

## Repeatable Seed/Reset Flow

Prerequisites:

- `DATABASE_URL` points at the intended local or disposable QA database
- Prisma migrations have been applied to that database

Commands:

```bash
cd /path/to/careloop
npm run qa:reset
npm run qa:seed:sprint1
```

Expected output from `qa:seed:sprint1`:

- Admin user ID
- Member user IDs
- Circle ID
- Seeded task IDs for admin-created, member-created, and overdue-task scenarios

## Manual App Flows

- [ ] Create circle: onboarding creates user + circle and lands in task list
- [ ] Join circle: valid circle ID adds user as `MEMBER`
- [ ] Join circle: invalid circle ID shows error and no crash
- [ ] Duplicate email returns `409`
- [ ] Kill and relaunch app restores session and active circle
- [ ] Sign out returns to onboarding

## Task CRUD

- [ ] Create task with title only -> `PENDING` and `NORMAL`
- [ ] Create task with notes -> notes visible in detail view
- [ ] Create task with due date -> due date renders correctly
- [ ] Admin can assign and reassign tasks
- [ ] Member task creation shows no assignee picker
- [ ] Tap task opens detail view
- [ ] Edit own task or any task as admin
- [ ] Delete own task or any task as admin
- [ ] Member cannot edit or delete another member's task
- [ ] Skip own task updates status to `SKIPPED`

## API Role Boundary Cases

All requests must include:

```bash
-H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json"
```

- [ ] Missing/invalid bearer token -> `401`

```bash
curl -i http://localhost:3000/users/any-user-id
```

- [ ] Non-member on protected task route -> `403`

```bash
curl -i -X POST http://localhost:3000/circles/CIRCLE_ID/tasks \
  -H "Authorization: Bearer $NON_MEMBER_TOKEN" -H "Content-Type: application/json" \
  -d '{"title":"Blocked task","assigneeId":"ASSIGNEE_USER_ID"}'
```

- [ ] Member cannot reassign task -> `403`

```bash
curl -i -X PATCH http://localhost:3000/circles/CIRCLE_ID/tasks/TASK_ID \
  -H "Authorization: Bearer $MEMBER_TOKEN" -H "Content-Type: application/json" \
  -d '{"assigneeId":"OTHER_MEMBER_USER_ID"}'
```

- [ ] Member cannot edit another member's task fields -> `403`

```bash
curl -i -X PATCH http://localhost:3000/circles/CIRCLE_ID/tasks/TASK_ID \
  -H "Authorization: Bearer $MEMBER_TOKEN" -H "Content-Type: application/json" \
  -d '{"title":"Unauthorized edit"}'
```

- [ ] Member cannot skip another member's task -> `403`

```bash
curl -i -X PATCH http://localhost:3000/circles/CIRCLE_ID/tasks/TASK_ID \
  -H "Authorization: Bearer $MEMBER_TOKEN" -H "Content-Type: application/json" \
  -d '{"status":"SKIPPED"}'
```

- [ ] Member cannot delete another member's task -> `403`

```bash
curl -i -X DELETE http://localhost:3000/circles/CIRCLE_ID/tasks/TASK_ID \
  -H "Authorization: Bearer $MEMBER_TOKEN"
```

- [ ] Member cannot update circle settings -> `403`

```bash
curl -i -X PATCH http://localhost:3000/circles/CIRCLE_ID \
  -H "Authorization: Bearer $MEMBER_TOKEN" -H "Content-Type: application/json" \
  -d '{"name":"Unauthorized"}'
```

- [ ] Member cannot remove another member -> `403`

```bash
curl -i -X DELETE http://localhost:3000/circles/CIRCLE_ID/members/MEMBER_ROW_ID \
  -H "Authorization: Bearer $MEMBER_TOKEN"
```

- [ ] Duplicate membership -> `409`

```bash
curl -i -X POST http://localhost:3000/circles/CIRCLE_ID/members \
  -H "Authorization: Bearer $MEMBER_TOKEN" -H "Content-Type: application/json" \
  -d '{}'
```

- [ ] Nonexistent resource -> `404`

```bash
curl -i http://localhost:3000/circles/not-a-real-circle-id \
  -H "Authorization: Bearer $ACCESS_TOKEN"
```

- [ ] Last admin demotion blocked -> `400`

```bash
curl -i -X PATCH http://localhost:3000/circles/CIRCLE_ID/members/ADMIN_MEMBER_ROW_ID/role \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  -d '{"role":"MEMBER"}'
```

## Status

- [x] Automated iOS tests executed locally and passed
- [x] Sprint 1 test cases are written
- [x] Repeatable seed/reset commands exist in repo
- [ ] Backend API manual execution against a live local database
- [ ] Full simulator walkthrough of onboarding/task CRUD/session restore
