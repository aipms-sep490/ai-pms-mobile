import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'core/api_client.dart';
import 'core/refresh_token_store.dart';
import 'features/auth/auth_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final auth = AuthController(
    api: ApiClient(origin: const String.fromEnvironment('API_BASE_URL')),
    storage: kIsWeb ? MemoryRefreshTokenStore() : SecureRefreshTokenStore(),
  );
  runApp(AiPmsApp(auth: auth));
  auth.restore();
}
