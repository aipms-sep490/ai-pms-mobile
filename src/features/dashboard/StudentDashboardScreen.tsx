import Ionicons from '@expo/vector-icons/Ionicons';
import { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';

import { colors, radii, spacing } from '../../ui/theme';
import { useSession } from '../auth/session';
import {
  buildDeadlineItems,
  formatDeadline,
  getProgressPercentage,
  statusLabel,
  type StudentDashboard,
} from './dashboard-model';

export function StudentDashboardScreen() {
  const { user } = useSession();
  return <StudentDashboardContent key={user?.id ?? 'anonymous'} />;
}

function StudentDashboardContent() {
  const { user, request } = useSession();
  const isStudent = user?.roles.includes('STUDENT') ?? false;
  const [data, setData] = useState<StudentDashboard | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const activeRequest = useRef<AbortController | null>(null);

  const load = useCallback(() => {
    if (!isStudent) return;
    activeRequest.current?.abort();
    const controller = new AbortController();
    activeRequest.current = controller;
    void request<StudentDashboard>('/api/v1/dashboards/student', {
        signal: controller.signal,
      })
      .then((dashboard) => {
        if (!controller.signal.aborted) {
          setData(dashboard);
          setError(null);
        }
      })
      .catch((reason: unknown) => {
        if (!controller.signal.aborted) {
          setError(reason instanceof Error ? reason.message : 'Không thể tải tổng quan. Vui lòng thử lại.');
        }
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });
  }, [isStudent, request]);

  useEffect(() => {
    void load();
    return () => activeRequest.current?.abort();
  }, [load]);

  const reload = () => {
    setLoading(true);
    setError(null);
    void load();
  };

  if (!isStudent) {
    return (
      <ScrollView contentContainerStyle={styles.content}>
        <Text style={styles.eyebrow}>AI-PMS MOBILE</Text>
        <Text accessibilityRole="header" style={styles.title}>Không gian sinh viên</Text>
        <View style={styles.card}>
          <Ionicons accessible={false} name="school-outline" size={30} color={colors.primary} />
          <Text style={styles.sectionTitle}>Tài khoản đã được kết nối</Text>
          <Text style={styles.body}>
            Tổng quan trên ứng dụng hiện dành cho sinh viên. Với vai trò hiện tại, bạn có thể xem tài khoản tại đây và sử dụng các nghiệp vụ của mình trên web AI-PMS.
          </Text>
        </View>
      </ScrollView>
    );
  }

  const deadlines = data ? buildDeadlineItems(data) : [];
  const progress = data ? getProgressPercentage(data) : null;
  const project = data?.project;
  const updatedAt = data ? new Date(data.asOfUtc) : null;

  return (
    <ScrollView
      contentContainerStyle={styles.content}
      refreshControl={<RefreshControl refreshing={loading && data !== null} onRefresh={reload} tintColor={colors.primary} />}
    >
      <View style={styles.greeting}>
        <View style={styles.wordmark}>
          <View style={styles.brandDot} />
          <Text style={styles.eyebrow}>KHÔNG GIAN SINH VIÊN</Text>
        </View>
        <Text accessibilityRole="header" style={styles.title}>Xin chào,{ '\n' }{user?.displayName}</Text>
        <Text style={styles.body}>Theo dõi công việc và tiến độ đồ án của bạn.</Text>
      </View>

      {loading && !data ? (
        <View style={styles.loading} accessibilityLiveRegion="polite">
          <ActivityIndicator size="large" color={colors.primary} />
          <Text style={styles.body}>Đang tải tổng quan…</Text>
        </View>
      ) : null}

      {error ? (
        <View style={styles.errorCard} accessibilityRole="alert">
          <Text style={styles.errorTitle}>{data ? 'Chưa cập nhật được dữ liệu' : 'Chưa tải được tổng quan'}</Text>
          <Text style={styles.body}>{error}</Text>
          {data ? <Text style={styles.caption}>Bạn đang xem dữ liệu từ lần tải thành công gần nhất.</Text> : null}
          <Pressable
            accessibilityRole="button"
            disabled={loading}
            onPress={reload}
            style={({ pressed }) => [styles.retryButton, pressed && styles.pressed]}
          >
            <Ionicons accessible={false} name="refresh-outline" size={18} color={colors.primary} />
            <Text style={styles.retryText}>Thử lại</Text>
          </Pressable>
        </View>
      ) : null}

      {data ? (
        <>
          {data.context.selectedSemester ? <Text style={styles.semester}>{data.context.selectedSemester.name}</Text> : null}
          <View style={styles.metrics}>
            <Metric value={data.assignedOpenTasks} label="Việc đang mở" icon="checkbox-outline" />
            <Metric value={data.assignedOverdueTasks} label="Việc quá hạn" icon="time-outline" danger={data.assignedOverdueTasks > 0} />
            <Metric value={data.unreadNotifications} label="Thông báo chưa đọc" icon="notifications-outline" />
          </View>

          <View style={styles.card}>
            <Text style={styles.eyebrow}>ĐỒ ÁN CỦA BẠN</Text>
            {project ? (
              <>
                <Text style={styles.projectCode}>{project.code}</Text>
                <Text accessibilityRole="header" style={styles.projectTitle}>{project.title}</Text>
                <View style={styles.statusBadge}><Text style={styles.statusText}>{statusLabel(project.status)}</Text></View>
                {data.context.currentTeam ? <InfoLine icon="people-outline" text={data.context.currentTeam.name} /> : null}
                {project.supervisor ? <InfoLine icon="person-outline" text={`GVHD: ${project.supervisor.name}`} /> : null}
                <View style={styles.progressHeading}>
                  <Text style={styles.body}>Tiến độ công việc</Text>
                  <Text style={styles.progressNumber}>{progress === null ? '—' : `${Math.round(progress)}%`}</Text>
                </View>
                {progress !== null ? (
                  <View
                    style={styles.progressTrack}
                    accessibilityRole="progressbar"
                    accessibilityLabel="Tiến độ công việc của đồ án"
                    accessibilityValue={{ min: 0, max: 100, now: progress }}
                  >
                    <View style={[styles.progressFill, { width: `${progress}%` }]} />
                  </View>
                ) : <Text style={styles.caption}>Chưa đủ dữ liệu để hiển thị tiến độ.</Text>}
              </>
            ) : (
              <>
                <Ionicons accessible={false} name="folder-open-outline" size={32} color={colors.primary} />
                <Text style={styles.sectionTitle}>{data.context.currentTeam ? 'Nhóm chưa có đồ án' : 'Chưa có đồ án để theo dõi'}</Text>
                <Text style={styles.body}>
                  {data.context.currentTeam
                    ? `Bạn đang tham gia ${data.context.currentTeam.name}. Hoàn tất đăng ký đồ án trên web để theo dõi tiến độ tại đây.`
                    : 'Hoàn tất tham gia nhóm và đăng ký đồ án trên web AI-PMS. Thông tin sẽ xuất hiện tại đây sau khi được cập nhật.'}
                </Text>
              </>
            )}
          </View>

          <View style={styles.sectionHeading}>
            <Text accessibilityRole="header" style={styles.sectionTitle}>Hạn cần theo dõi</Text>
            <Text style={styles.caption}>{deadlines.length} mục</Text>
          </View>
          {deadlines.length > 0 ? (
            <View style={styles.deadlineList}>
              {deadlines.map((item, index) => (
                <View key={item.key} style={[styles.deadline, index > 0 && styles.deadlineBorder]}>
                  <View style={[styles.deadlineIcon, item.isOverdue && styles.overdueIcon]}>
                    <Ionicons
                      accessible={false}
                      name={item.kind === 'task' ? 'checkbox-outline' : 'flag-outline'}
                      size={21}
                      color={item.isOverdue ? colors.danger : colors.primary}
                    />
                  </View>
                  <View style={styles.deadlineCopy}>
                    <Text style={styles.caption}>{item.kind === 'task' ? 'Công việc' : 'Mốc tiến độ'}</Text>
                    <Text style={styles.deadlineTitle}>{item.title}</Text>
                    <Text style={styles.caption}>{statusLabel(item.status)}</Text>
                    <Text style={[styles.dueDate, item.isOverdue && styles.overdueText]}>
                      {item.isOverdue ? 'Quá hạn · ' : 'Hạn · '}{formatDeadline(item)}
                    </Text>
                  </View>
                </View>
              ))}
            </View>
          ) : (
            <View style={styles.emptyCard}>
              <Ionicons accessible={false} name="calendar-outline" size={27} color={colors.textMuted} />
              <Text style={styles.body}>Chưa có hạn công việc hoặc mốc tiến độ cần theo dõi.</Text>
            </View>
          )}
          {updatedAt && !Number.isNaN(updatedAt.getTime()) ? (
            <Text style={styles.updatedAt}>
              Cập nhật {new Intl.DateTimeFormat('vi-VN', {
                day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Ho_Chi_Minh',
              }).format(updatedAt)} · Giờ Việt Nam
            </Text>
          ) : null}
        </>
      ) : null}
    </ScrollView>
  );
}

function Metric({ value, label, icon, danger = false }: {
  value: number;
  label: string;
  icon: React.ComponentProps<typeof Ionicons>['name'];
  danger?: boolean;
}) {
  return (
    <View style={styles.metric}>
      <Ionicons accessible={false} name={icon} size={21} color={danger ? colors.danger : colors.textMuted} />
      <Text style={[styles.metricValue, danger && styles.overdueText]}>{value}</Text>
      <Text style={styles.metricLabel}>{label}</Text>
    </View>
  );
}

function InfoLine({ icon, text }: { icon: React.ComponentProps<typeof Ionicons>['name']; text: string }) {
  return (
    <View style={styles.infoLine}>
      <Ionicons accessible={false} name={icon} size={18} color={colors.textMuted} />
      <Text style={styles.infoText}>{text}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  content: { padding: spacing.lg, paddingBottom: spacing.xl, gap: spacing.lg, backgroundColor: colors.background, flexGrow: 1 },
  greeting: { gap: spacing.sm },
  wordmark: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, marginBottom: spacing.sm },
  brandDot: { width: 8, height: 8, borderRadius: 4, backgroundColor: colors.primary },
  eyebrow: { fontSize: 11, fontWeight: '700', letterSpacing: 1.6, color: colors.textMuted },
  title: { fontSize: 30, lineHeight: 38, fontWeight: '700', color: colors.text },
  body: { fontSize: 16, lineHeight: 25, color: colors.textMuted },
  caption: { fontSize: 13, lineHeight: 20, color: colors.textMuted },
  semester: { fontSize: 14, lineHeight: 21, color: colors.textMuted, marginBottom: -spacing.md },
  loading: { minHeight: 230, alignItems: 'center', justifyContent: 'center', gap: spacing.md },
  metrics: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  metric: { flex: 1, minWidth: 86, padding: spacing.md, borderRadius: radii.md, backgroundColor: colors.surface, borderWidth: 1, borderColor: colors.border, gap: spacing.sm },
  metricValue: { fontSize: 29, fontWeight: '700', color: colors.text, fontVariant: ['tabular-nums'] },
  metricLabel: { fontSize: 12, lineHeight: 18, color: colors.textMuted },
  card: { padding: spacing.lg, borderWidth: 1, borderColor: colors.border, borderRadius: radii.lg, backgroundColor: colors.surface, gap: spacing.md },
  projectCode: { fontSize: 13, color: colors.primary, fontWeight: '600', marginBottom: -spacing.sm },
  projectTitle: { fontSize: 22, lineHeight: 30, fontWeight: '700', color: colors.text },
  sectionTitle: { fontSize: 19, lineHeight: 27, fontWeight: '700', color: colors.text },
  statusBadge: { alignSelf: 'flex-start', borderRadius: radii.sm, paddingHorizontal: 10, paddingVertical: 6, backgroundColor: colors.primarySoft },
  statusText: { fontSize: 13, lineHeight: 19, fontWeight: '600', color: colors.primary },
  infoLine: { flexDirection: 'row', alignItems: 'flex-start', gap: spacing.sm },
  infoText: { flex: 1, fontSize: 14, lineHeight: 21, color: colors.textMuted },
  progressHeading: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: spacing.sm, marginTop: spacing.sm },
  progressNumber: { fontSize: 18, fontWeight: '700', color: colors.text, fontVariant: ['tabular-nums'] },
  progressTrack: { height: 7, borderRadius: 4, backgroundColor: colors.surfaceMuted, overflow: 'hidden', marginTop: -spacing.sm },
  progressFill: { height: 7, borderRadius: 4, backgroundColor: colors.primary },
  sectionHeading: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: spacing.sm, marginBottom: -spacing.md },
  deadlineList: { backgroundColor: colors.surface, borderWidth: 1, borderColor: colors.border, borderRadius: radii.md, overflow: 'hidden' },
  deadline: { flexDirection: 'row', alignItems: 'flex-start', gap: spacing.md, padding: spacing.md },
  deadlineBorder: { borderTopWidth: 1, borderTopColor: colors.border },
  deadlineIcon: { backgroundColor: colors.primarySoft, borderRadius: radii.sm, padding: 10 },
  overdueIcon: { backgroundColor: colors.surfaceMuted },
  deadlineCopy: { flex: 1, gap: spacing.xs },
  deadlineTitle: { fontSize: 16, lineHeight: 24, fontWeight: '600', color: colors.text },
  dueDate: { fontSize: 13, lineHeight: 20, fontWeight: '500', color: colors.textMuted },
  overdueText: { color: colors.danger },
  emptyCard: { borderRadius: radii.md, padding: spacing.lg, gap: spacing.md, backgroundColor: colors.surface, borderWidth: 1, borderColor: colors.border },
  errorCard: { backgroundColor: colors.surface, borderWidth: 1, borderColor: colors.danger, borderRadius: radii.md, padding: spacing.md, gap: spacing.sm },
  errorTitle: { fontSize: 16, lineHeight: 24, fontWeight: '700', color: colors.danger },
  retryButton: { flexDirection: 'row', alignItems: 'center', alignSelf: 'flex-start', minHeight: 48, paddingHorizontal: spacing.md, gap: spacing.sm, borderRadius: radii.sm, backgroundColor: colors.primarySoft },
  retryText: { fontSize: 16, fontWeight: '600', color: colors.primary },
  pressed: { opacity: 0.7 },
  updatedAt: { fontSize: 12, lineHeight: 19, color: colors.textMuted, textAlign: 'center' },
});

export default StudentDashboardScreen;
