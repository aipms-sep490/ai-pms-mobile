export interface StudentDashboard {
  asOfUtc: string;
  context: {
    selectedSemester: { name: string } | null;
    currentTeam: { name: string; isLeader: boolean } | null;
  };
  project: {
    id: number;
    code: string;
    title: string;
    status: string;
    supervisor: { name: string } | null;
    analysis: {
      dataStatus: string;
      riskLevel: string;
      progressSummary: { progressPercentage: number };
    } | null;
  } | null;
  unreadNotifications: number;
  assignedOpenTasks: number;
  assignedOverdueTasks: number;
  taskDeadlines: {
    id: number;
    title: string;
    status: string;
    dueAtUtc: string;
    isOverdue: boolean;
  }[];
  milestoneDeadlines: {
    id: number;
    title: string;
    status: string;
    dueDate: string;
    isOverdue: boolean;
  }[];
}

export interface DeadlineItem {
  key: string;
  kind: 'task' | 'milestone';
  title: string;
  status: string;
  due: string;
  isOverdue: boolean;
}

const statuses: Record<string, string> = {
  DRAFT: 'Bản nháp',
  SUBMITTED: 'Đã nộp đề cương',
  UNDERREVIEW: 'Đang thẩm định',
  REVISIONREQUIRED: 'Cần chỉnh sửa',
  REJECTED: 'Không được chấp thuận',
  APPROVED: 'Đã phê duyệt',
  SUPERVISORPENDING: 'Chờ phân công giảng viên',
  ACTIVE: 'Đang thực hiện',
  FINALSUBMISSION: 'Đang bàn giao',
  COMPLETED: 'Đã hoàn thành',
  ARCHIVED: 'Đã lưu trữ',
  TODO: 'Cần thực hiện',
  INPROGRESS: 'Đang thực hiện',
  BLOCKED: 'Đang bị chặn',
  INREVIEW: 'Chờ xem xét',
  DONE: 'Đã hoàn thành',
  CANCELLED: 'Đã hủy',
  OPEN: 'Đang mở',
  PLANNED: 'Đã lên kế hoạch',
};

export function statusLabel(status: string): string {
  return statuses[status.replaceAll('_', '').toUpperCase()] ?? status;
}

export function getProgressPercentage(dashboard: StudentDashboard): number | null {
  const analysis = dashboard.project?.analysis;
  if (analysis?.dataStatus !== 'SUFFICIENT') return null;
  const value = analysis.progressSummary.progressPercentage;
  return Number.isFinite(value) ? Math.max(0, Math.min(100, value)) : null;
}

export function buildDeadlineItems(dashboard: StudentDashboard): DeadlineItem[] {
  const items: DeadlineItem[] = [
    ...dashboard.taskDeadlines.map((task) => ({
      key: `task-${task.id}`,
      kind: 'task' as const,
      title: task.title,
      status: task.status,
      due: task.dueAtUtc,
      isOverdue: task.isOverdue,
    })),
    ...dashboard.milestoneDeadlines.map((milestone) => ({
      key: `milestone-${milestone.id}`,
      kind: 'milestone' as const,
      title: milestone.title,
      status: milestone.status,
      due: milestone.dueDate,
      isOverdue: milestone.isOverdue,
    })),
  ];
  // The server owns overdue status. A phone's clock must not change it.
  return items.sort((left, right) => {
    if (left.isOverdue !== right.isOverdue) return left.isOverdue ? -1 : 1;
    const time = (item: DeadlineItem) => {
      const parsed = Date.parse(item.kind === 'milestone' ? `${item.due}T23:59:59+07:00` : item.due);
      return Number.isFinite(parsed) ? parsed : Number.POSITIVE_INFINITY;
    };
    return time(left) - time(right);
  });
}

export function formatDeadline(item: DeadlineItem): string {
  if (item.kind === 'milestone') {
    const parts = /^(\d{4})-(\d{2})-(\d{2})$/.exec(item.due);
    return parts ? `${parts[3]}/${parts[2]}/${parts[1]}` : 'Chưa xác định hạn';
  }
  const date = new Date(item.due);
  if (Number.isNaN(date.getTime())) return 'Chưa xác định hạn';
  return new Intl.DateTimeFormat('vi-VN', {
    day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit',
    timeZone: 'Asia/Ho_Chi_Minh',
  }).format(date);
}
