package com.dulaauth.totp

import io.flutter.embedding.android.FlutterFragmentActivity

// local_auth's BiometricPrompt requires a FragmentActivity host; a plain
// FlutterActivity makes every biometric call throw, which
// LocalAuthBiometrics.authenticate() silently maps to `false` — the prompt
// never appears and nothing tells the user why (see local_auth_android's
// README "Activity Changes").
class MainActivity : FlutterFragmentActivity()
