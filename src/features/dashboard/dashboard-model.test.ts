import assert from 'node:assert/strict';
import { test } from 'node:test';

import { buildDeadlineItems, formatDeadline, getProgressPercentage, type StudentDashboard } from './dashboard-model';

const dashboard: StudentDashboard = {
  asOfUtc: '2026-11-14T07:00:00Z',
  context: { selectedSemester: null, currentTeam: null },
  project: null,
  unreadNotifications: 0,
  assignedOpenTasks: 0,
  assignedOverdueTasks: 0,
  taskDeadlines: [],
  milestoneDeadlines: [],
};

test('deadline attention order follows server overdue flag, not the device clock', () => {
  const items = buildDeadlineItems({
    ...dashboard,
    taskDeadlines: [
      { id: 1, title: 'Old but not flagged', status: 'TODO', dueAtUtc: '2000-01-01T00:00:00Z', isOverdue: false },
      { id: 2, title: 'Flagged by server', status: 'TODO', dueAtUtc: '2099-01-01T00:00:00Z', isOverdue: true },
    ],
    milestoneDeadlines: [{ id: 1, title: 'Milestone', status: 'OPEN', dueDate: '2026-11-14', isOverdue: false }],
  });
  assert.deepEqual(items.map((item) => item.key), ['task-2', 'task-1', 'milestone-1']);
  assert.equal(formatDeadline(items[2]), '14/11/2026');
  assert.match(formatDeadline({ ...items[0], due: '2026-11-13T18:00:00Z' }), /14[/-]11/);
});

test('unavailable analysis does not appear as zero progress', () => {
  assert.equal(getProgressPercentage(dashboard), null);
  const project = {
    id: 1, code: 'P1', title: 'Project', status: 'ACTIVE', supervisor: null,
    analysis: { dataStatus: 'INSUFFICIENT_DATA', riskLevel: 'INSUFFICIENT_DATA', progressSummary: { progressPercentage: 0 } },
  };
  assert.equal(getProgressPercentage({ ...dashboard, project }), null);
  project.analysis.dataStatus = 'SUFFICIENT';
  project.analysis.progressSummary.progressPercentage = 42.5;
  assert.equal(getProgressPercentage({ ...dashboard, project }), 42.5);
});
