import { SafeAreaView } from 'react-native-safe-area-context';

import { StudentDashboardScreen } from '../../features/dashboard/StudentDashboardScreen';
import { colors } from '../../ui/theme';

export default function OverviewScreen() {
  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: colors.background }} edges={['top', 'left', 'right']}>
      <StudentDashboardScreen />
    </SafeAreaView>
  );
}
