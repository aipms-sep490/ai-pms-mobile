import Ionicons from '@expo/vector-icons/Ionicons';
import { Tabs } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { colors } from '../../ui/theme';

export default function WorkspaceLayout() {
  const insets = useSafeAreaInsets();
  return (
    <Tabs screenOptions={{
      headerShown: false,
      tabBarActiveTintColor: colors.primary,
      tabBarInactiveTintColor: colors.textMuted,
      tabBarStyle: {
        backgroundColor: colors.surface, borderTopColor: colors.border,
        height: 72 + insets.bottom, paddingTop: 6, paddingBottom: Math.max(6, insets.bottom),
      },
      tabBarLabelPosition: 'below-icon',
      tabBarLabelStyle: { fontSize: 12, lineHeight: 18, fontWeight: '600' },
      tabBarItemStyle: { minHeight: 48 },
      sceneStyle: { backgroundColor: colors.background },
    }}>
      <Tabs.Screen name="index" options={{
        title: 'Tổng quan',
        tabBarAccessibilityLabel: 'Tổng quan',
        tabBarIcon: ({ focused, size }) => <Ionicons accessible={false} name="grid-outline" size={size} color={focused ? colors.primary : colors.textMuted} />,
      }} />
      <Tabs.Screen name="profile" options={{
        title: 'Tài khoản',
        tabBarAccessibilityLabel: 'Tài khoản',
        tabBarIcon: ({ focused, size }) => <Ionicons accessible={false} name="person-circle-outline" size={size} color={focused ? colors.primary : colors.textMuted} />,
      }} />
    </Tabs>
  );
}
