import Ionicons from '@expo/vector-icons/Ionicons';
import { useRef, useState, type ComponentRef } from 'react';
import {
  ActivityIndicator, KeyboardAvoidingView, Platform, Pressable, ScrollView,
  StyleSheet, Text, TextInput, View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { useSession } from '../features/auth/session';
import { ApiError } from '../lib/api-client';
import { colors, radii, spacing } from '../ui/theme';

export default function SignInScreen() {
  const { signIn } = useSession();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [visible, setVisible] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const emailInput = useRef<ComponentRef<typeof TextInput>>(null);
  const passwordInput = useRef<ComponentRef<typeof TextInput>>(null);

  async function submit() {
    if (busy) return;
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) {
      setError('Nhập địa chỉ email hợp lệ để tiếp tục.');
      emailInput.current?.focus();
      return;
    }
    if (!password) {
      setError('Nhập mật khẩu tài khoản của bạn.');
      passwordInput.current?.focus();
      return;
    }
    setBusy(true);
    setError('');
    try {
      await signIn(email, password);
      setPassword('');
    } catch (cause) {
      setError(cause instanceof ApiError ? cause.message : 'Chưa thể đăng nhập. Vui lòng thử lại.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <SafeAreaView style={styles.page}>
      <KeyboardAvoidingView style={styles.flex} behavior={Platform.OS === 'ios' ? 'padding' : 'height'}>
        <ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={styles.content}>
          <View style={styles.brand}>
            <View style={styles.brandMark}><Ionicons accessible={false} name="layers-outline" size={23} color={colors.surface} /></View>
            <Text style={styles.brandName}>AI-PMS</Text>
            <View style={styles.brandRule} />
            <Text style={styles.brandLabel}>DỰ ÁN HỌC PHẦN</Text>
          </View>

          <View style={styles.intro}>
            <Text style={styles.eyebrow}>MỖI BƯỚC, MỘT TIẾN TRIỂN</Text>
            <Text style={styles.title} accessibilityRole="header">Đồ án của bạn.{ '\n' }Luôn trong tầm tay.</Text>
            <Text style={styles.description}>Nắm tiến độ, theo dõi công việc và giữ kết nối với hành trình đồ án.</Text>
          </View>

          <View style={styles.form}>
            <Text style={styles.formTitle} accessibilityRole="header">Đăng nhập</Text>
            <Text style={styles.formHint}>Sử dụng tài khoản được trường cấp.</Text>
            <View style={styles.field}>
              <Text nativeID="email-label" style={styles.label}>Email</Text>
              <TextInput ref={emailInput} accessibilityLabel="Email" aria-labelledby="email-label"
                style={styles.input} value={email} onChangeText={setEmail} placeholder="ban@truong.edu.vn"
                placeholderTextColor={colors.textMuted} keyboardType="email-address" autoCapitalize="none"
                autoCorrect={false} autoComplete="email" textContentType="username" returnKeyType="next"
                editable={!busy} onSubmitEditing={() => passwordInput.current?.focus()} />
            </View>
            <View style={styles.field}>
              <Text nativeID="password-label" style={styles.label}>Mật khẩu</Text>
              <View style={styles.passwordWrap}>
                <TextInput ref={passwordInput} accessibilityLabel="Mật khẩu" aria-labelledby="password-label"
                  style={styles.passwordInput} value={password} onChangeText={setPassword}
                  placeholder="Nhập mật khẩu" placeholderTextColor={colors.textMuted} secureTextEntry={!visible}
                  autoCapitalize="none" autoCorrect={false} autoComplete="current-password"
                  textContentType="password" returnKeyType="go" editable={!busy} onSubmitEditing={submit} />
                <Pressable onPress={() => setVisible(value => !value)} accessibilityRole="button"
                  accessibilityLabel={visible ? 'Ẩn mật khẩu' : 'Hiện mật khẩu'}
                  style={({ pressed }) => [styles.eye, pressed && styles.pressed]}>
                  <Ionicons accessible={false} name={visible ? 'eye-off-outline' : 'eye-outline'} size={22} color={colors.textMuted} />
                </Pressable>
              </View>
            </View>
            {error ? <View style={styles.errorBox} accessibilityRole="alert" accessibilityLiveRegion="polite">
              <Ionicons accessible={false} name="alert-circle-outline" size={20} color={colors.danger} />
              <Text style={styles.errorText}>{error}</Text>
            </View> : null}
            <Pressable onPress={submit} accessibilityRole="button" accessibilityLabel="Đăng nhập"
              accessibilityState={{ disabled: busy, busy }} disabled={busy}
              style={({ pressed }) => [styles.submit, (busy || pressed) && styles.pressed]}>
              {busy ? <ActivityIndicator color={colors.surface} /> : <>
                <Text style={styles.submitText}>Đăng nhập</Text>
                <Ionicons accessible={false} name="arrow-forward" size={21} color={colors.surface} />
              </>}
            </Pressable>
          </View>

          <View style={styles.footer}>
            <Ionicons accessible={false} name="shield-checkmark-outline" size={18} color={colors.success} />
            <Text style={styles.footerText}>Một tài khoản. Kết nối cùng không gian trên web.</Text>
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  page: { flex: 1, backgroundColor: colors.background },
  content: { flexGrow: 1, padding: spacing.lg, paddingBottom: spacing.xl, width: '100%', maxWidth: 520, alignSelf: 'center' },
  brand: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingTop: spacing.md },
  brandMark: { width: 40, height: 40, borderRadius: 12, backgroundColor: colors.navy, alignItems: 'center', justifyContent: 'center' },
  brandName: { fontSize: 22, fontWeight: '800', letterSpacing: -0.7, color: colors.navy },
  brandRule: { width: 1, height: 22, backgroundColor: colors.border, marginHorizontal: 3 },
  brandLabel: { fontSize: 10, letterSpacing: 0.8, color: colors.textMuted, flexShrink: 1 },
  intro: { paddingTop: 48, paddingBottom: spacing.xl, gap: spacing.md },
  eyebrow: { color: colors.primary, fontSize: 11, fontWeight: '700', letterSpacing: 1.5 },
  title: { fontSize: 34, lineHeight: 43, fontWeight: '700', letterSpacing: -1.2, color: colors.navy },
  description: { color: colors.textMuted, fontSize: 16, lineHeight: 25, maxWidth: 350 },
  form: { backgroundColor: colors.surface, padding: spacing.lg, borderRadius: radii.lg, borderColor: colors.border, borderWidth: 1, gap: 18 },
  formTitle: { color: colors.text, fontSize: 23, fontWeight: '700' },
  formHint: { color: colors.textMuted, fontSize: 14, lineHeight: 21, marginTop: -10 },
  field: { gap: spacing.sm },
  label: { color: colors.text, fontSize: 14, fontWeight: '600' },
  input: { minHeight: 52, borderWidth: 1, borderColor: colors.border, borderRadius: radii.sm, paddingHorizontal: 14, paddingVertical: 12, color: colors.text, backgroundColor: colors.background, fontSize: 16 },
  passwordWrap: { flexDirection: 'row', alignItems: 'center', borderWidth: 1, borderColor: colors.border, borderRadius: radii.sm, backgroundColor: colors.background },
  passwordInput: { flex: 1, minWidth: 0, minHeight: 52, paddingHorizontal: 14, paddingVertical: 12, color: colors.text, fontSize: 16 },
  eye: { minWidth: 48, minHeight: 52, alignItems: 'center', justifyContent: 'center' },
  submit: { minHeight: 54, padding: 14, backgroundColor: colors.primary, borderRadius: radii.sm, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 12, marginTop: 4 },
  submitText: { color: colors.surface, fontSize: 16, fontWeight: '700' },
  pressed: { opacity: 0.65 },
  errorBox: { flexDirection: 'row', gap: spacing.sm, alignItems: 'flex-start', padding: 12, borderRadius: radii.sm, backgroundColor: '#FEF2F2' },
  errorText: { color: colors.danger, fontSize: 14, lineHeight: 21, flex: 1 },
  footer: { flexDirection: 'row', justifyContent: 'center', alignItems: 'flex-start', gap: spacing.sm, paddingTop: spacing.lg, paddingHorizontal: spacing.sm },
  footerText: { flexShrink: 1, color: colors.textMuted, fontSize: 12, lineHeight: 19, textAlign: 'center' },
});
