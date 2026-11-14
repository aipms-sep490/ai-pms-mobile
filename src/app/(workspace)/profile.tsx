import Ionicons from '@expo/vector-icons/Ionicons';
import { useState } from 'react';
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { useSession } from '../../features/auth/session';
import { colors, radii, spacing } from '../../ui/theme';

const roleNames: Record<string, string> = {
  STUDENT: 'Sinh viên', LECTURER: 'Giảng viên', DEPARTMENT_STAFF: 'Cán bộ bộ môn', ADMIN: 'Quản trị viên',
};

export default function ProfileScreen() {
  const { user, signOut } = useSession();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  async function handleSignOut() {
    setBusy(true);
    setError('');
    try { await signOut(); }
    catch { setError('Chưa thể đóng phiên. Vui lòng thử lại.'); }
    finally { setBusy(false); }
  }

  return (
    <SafeAreaView style={styles.page} edges={['top', 'left', 'right']}>
      <ScrollView contentContainerStyle={styles.content}>
        <Text style={styles.eyebrow}>KHÔNG GIAN CÁ NHÂN</Text>
        <Text style={styles.title} accessibilityRole="header">Tài khoản</Text>
        <View style={styles.identity}>
          <View style={styles.avatar}><Ionicons name="person-outline" size={30} color={colors.primary} /></View>
          <Text style={styles.name}>{user?.displayName}</Text>
          <Text style={styles.email}>{user?.email}</Text>
        </View>
        <View style={styles.details}>
          <Text style={styles.label}>Vai trò</Text>
          <Text style={styles.value}>{user?.roles.map(role => roleNames[role] ?? role).join(' · ')}</Text>
        </View>
        {error ? <Text style={styles.error} accessibilityRole="alert">{error}</Text> : null}
        <Pressable accessibilityRole="button" accessibilityState={{ disabled: busy, busy }} disabled={busy}
          onPress={handleSignOut} style={({ pressed }) => [styles.signOut, pressed && styles.pressed]}>
          {busy ? <ActivityIndicator color={colors.danger} /> : <Ionicons name="log-out-outline" size={22} color={colors.danger} />}
          <Text style={styles.signOutText}>Đăng xuất</Text>
        </Pressable>
        <Text style={styles.version}>AI-PMS · Phiên bản 0.1.0</Text>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  page: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.lg, gap: spacing.lg, width: '100%', maxWidth: 640, alignSelf: 'center' },
  eyebrow: { color: colors.primary, fontSize: 12, fontWeight: '700', letterSpacing: 1.5 },
  title: { fontSize: 32, fontWeight: '700', color: colors.navy },
  identity: { alignItems: 'center', paddingVertical: spacing.xl, gap: spacing.sm },
  avatar: { width: 72, height: 72, borderRadius: 24, backgroundColor: colors.primarySoft, alignItems: 'center', justifyContent: 'center', marginBottom: 8 },
  name: { color: colors.text, fontSize: 24, fontWeight: '700', textAlign: 'center' },
  email: { color: colors.textMuted, fontSize: 16, textAlign: 'center' },
  details: { backgroundColor: colors.surface, padding: spacing.lg, borderRadius: radii.md, borderWidth: 1, borderColor: colors.border, gap: spacing.sm },
  label: { color: colors.textMuted, fontSize: 14 },
  value: { color: colors.text, fontSize: 16, lineHeight: 24 },
  signOut: { minHeight: 52, borderWidth: 1, borderColor: colors.border, backgroundColor: colors.surface, borderRadius: radii.sm, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: spacing.sm, padding: spacing.md },
  signOutText: { color: colors.danger, fontSize: 16, fontWeight: '600' },
  pressed: { opacity: 0.65 },
  error: { color: colors.danger, fontSize: 16 },
  version: { color: colors.textMuted, fontSize: 13, textAlign: 'center', paddingBottom: spacing.md },
});
