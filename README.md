# FinancialMind

FinancialMind is a Flutter-based personal finance management application designed to help users track accounts, transactions, SMS-based bank notifications, debts, tasks, and financial insights from one mobile interface.

The application focuses on the Jordanian financial context and supports manual and automatic account tracking through bank and e-wallet SMS messages.

## Project Overview

FinancialMind provides a unified dashboard for managing personal finances across multiple accounts such as bank accounts, digital wallets, and cash accounts. It also includes task reminders, debt tracking, transaction categorization, analytics, and an AI-powered assistant for financial guidance.

The system is built as a cross-platform mobile application using Flutter, with Supabase used as the backend for authentication, database storage, and synchronization.

## Main Features

### Dashboard

The dashboard gives the user a quick overview of their financial status, including total balance, recent transactions, income and expense summary, account overview, SMS sync status, and quick access to important modules.

### Account Management

Users can create and manage different types of accounts, including bank accounts, e-wallets, cash accounts, manually added accounts, and automatically linked SMS-based accounts.

Automatic accounts are linked to SMS senders such as banks or e-wallet providers.

### SMS Transaction Detection

The application can read bank and e-wallet SMS messages and extract transaction information such as amount, transaction type, sender ID, available balance, transaction date and time, and transfer information.

The SMS processing logic includes duplicate detection using SMS hashes to prevent the same message from being processed more than once.

### Internal Transfer Handling

The system supports internal transfer detection between accounts.

For example, if a transfer occurs from one wallet to another bank account, the application attempts to detect the source and destination accounts and records the transaction as a transfer instead of duplicating it as income and expense.

### Transaction Management

Users can view, search, filter, and manage transactions.

Supported transaction types include income, expense, and transfer.

Transactions can be categorized and displayed in detail for better financial tracking.

### Analytics

The analytics screen separates income and expenses and displays category-based financial summaries.

This helps users understand where their money comes from and where it is being spent.

### Debts Module

The application includes an independent debts module for tracking money owed by the user, money owed to the user, total debtors, and total creditors.

Debts are kept separate from the main account balances.

### To-Do List and Task Reminders

FinancialMind includes a task management module for reminders related to bills, savings goals, payments, and personal financial tasks.

Task features include task title, description, due date, due time, priority, completion status, and local notification reminders.

Task reminders are scheduled using local notifications. When a reminder is triggered, the user receives a notification and can return to the To-Do List screen.

### AI Financial Assistant

The application includes an AI assistant that can help users understand their finances, ask questions, and receive financial suggestions based on available app data.

AI usage should be handled carefully. API keys should not be stored directly inside the mobile application in production builds.

### Arabic Language Support

The application supports switching interface text to Arabic while keeping the layout direction unchanged.

This means text changes to Arabic, but the screen structure does not flip from left-to-right to right-to-left.

## Technology Stack

| Layer | Technology |
|---|---|
| Frontend | Flutter |
| Language | Dart |
| Backend | Supabase |
| Database | PostgreSQL |
| Authentication | Supabase Auth |
| Notifications | flutter_local_notifications |
| SMS Reading | Telephony-based SMS listener |
| AI | Google Generative AI |
| Local Storage | SharedPreferences |
| Platform | Android |

## Database Modules

The project uses several Supabase tables, including:

- `profiles`
- `wallets`
- `transactions`
- `categories`
- `tasks`
- `debts`
- `sms_processing_logs`

### SMS Processing Logs

The `sms_processing_logs` table is used to prevent duplicate SMS processing.

It stores user ID, SMS hash, sender ID, processing status, and timestamps.

The unique constraint on `(user_id, sms_hash)` ensures that the same SMS message is not processed more than once for the same user.

### Task Reminder Fields

The `tasks` table includes reminder-related fields such as:

- `reminder_enabled`
- `reminder_time`
- `due_time`
- `notification_id`

These fields are used to schedule, cancel, and restore local task reminders.

## Android Permissions

The Android application may require the following permissions depending on enabled features:

- `INTERNET`
- `ACCESS_NETWORK_STATE`
- `READ_SMS`
- `RECEIVE_SMS`
- `POST_NOTIFICATIONS`
- `SCHEDULE_EXACT_ALARM`
- `RECEIVE_BOOT_COMPLETED`
- `USE_BIOMETRIC`
- `VIBRATE`
- `WAKE_LOCK`

Unused permissions should be removed from `AndroidManifest.xml`.

## Project Setup

### 1. Clone the Repository

```bash
git clone <repository-url>
cd final_project
```

### 2. Install Flutter Dependencies

```bash
flutter pub get
```

### 3. Configure Supabase

Update the Supabase configuration in the project with the Supabase project URL and Supabase anon key.

Do not use the Supabase `service_role` key inside the mobile application.

### 4. Run Supabase SQL Migrations

Apply the required SQL scripts for task reminders, SMS processing logs, required tables, and policies.

Make sure Row Level Security policies are enabled and correctly configured.

### 5. Run the App

```bash
flutter run
```

## Build APK

### Debug APK

```bash
flutter build apk --debug
```

### Release APK

```bash
flutter build apk --release
```

The generated APK will be located at:

```text
build/app/outputs/flutter-apk/app-release.apk
```

### Split APK by ABI

To reduce APK size:

```bash
flutter build apk --split-per-abi
```

## Important Release Build Note

If scheduled notifications crash in release mode because of R8 or ProGuard, keep minification disabled or preserve the required generic signatures.

Recommended release configuration:

```kotlin
buildTypes {
    getByName("release") {
        signingConfig = signingConfigs.getByName("debug")
        isMinifyEnabled = false
        isShrinkResources = false
        proguardFiles(
            getDefaultProguardFile("proguard-android-optimize.txt"),
            "proguard-rules.pro"
        )
    }
}
```

Recommended ProGuard rules:

```proguard
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**

-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**

-keep class * extends com.google.gson.reflect.TypeToken { *; }
```

## Testing

Run static analysis:

```bash
flutter analyze
```

Run the app on a connected device:

```bash
flutter run
```

Build a release APK:

```bash
flutter build apk --release
```

## Manual Testing Checklist

### Task Reminder Test

1. Create a task.
2. Set a due date and due time.
3. Enable reminder.
4. Set reminder time two minutes in the future.
5. Save the task.
6. Confirm that no scheduling error appears.
7. Wait for the notification.
8. Tap the notification.
9. Confirm that the app opens the To-Do List screen.
10. Complete or delete the task and confirm that the notification is cancelled.

### SMS Listener Test

1. Install the APK on a real Android device.
2. Grant SMS permissions.
3. Send or receive a supported bank/e-wallet SMS.
4. Confirm the SMS is parsed correctly.
5. Confirm duplicate SMS messages are skipped.
6. Confirm the app does not crash when SMS messages are received.

### Arabic Mode Test

1. Open Settings.
2. Switch language to Arabic.
3. Open the To-Do List.
4. Add or edit a task.
5. Confirm that fixed labels such as Description are translated.

## Debugging with Logcat

Check connected devices:

```bash
adb devices
```

Clear old logs:

```bash
adb logcat -c
```

Monitor notification and crash logs:

```bash
adb logcat | findstr "FinMindNotifications AndroidRuntime flutter System.err"
```

Save logs to a file:

```bash
adb logcat > reminder_crash_log.txt
```

Stop logging with:

```text
Ctrl + C
```

## Security Notes

- Do not store private API keys directly inside the mobile app.
- Do not use Supabase service role keys in Flutter.
- Enable Row Level Security on Supabase tables.
- Keep each user restricted to their own data using `auth.uid()`.
- Avoid logging sensitive SMS content or financial data.

## Known Limitations

- SMS parsing depends on the message format used by each bank or wallet provider.
- SMS permissions may be restricted by Google Play policies.
- Scheduled notifications must be tested on real Android devices.
- Exact alarm behavior may differ between Android versions and device manufacturers.
- AI responses depend on API availability and quota limits.

## Folder Structure

```text
lib/
  models/
  screens/
  services/
  widgets/
android/
  app/
supabase/
  migrations or sql scripts
```

## Project Status

The application includes the main functional modules required for a personal finance management system:

- Authentication
- Dashboard
- Account management
- SMS-based transaction detection
- Transaction tracking
- Debt tracking
- Analytics
- Task reminders
- Arabic text support
- AI assistant

Further production work should focus on security hardening, real-device testing, Play Store permission compliance, and backend-based AI key protection.

## Author

Abdalkareem Alerjan

Software Engineering Student

## License

This project is developed for academic and educational purposes.
