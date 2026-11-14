import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/theme_cubit.dart';
import '../../../../core/widgets/e2ee_pin_dialog.dart';
import '../../../../core/widgets/error_diagnostic_dialog.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../bloc/settings_bloc.dart';
import '../bloc/settings_event.dart';
import '../bloc/settings_state.dart';

class SettingsScreen extends StatelessWidget {
  final UserEntity currentUser;
  final VoidCallback onLogout;

  const SettingsScreen({
    super.key,
    required this.currentUser,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocConsumer<SettingsBloc, SettingsState>(
      listener: (context, state) {
        if (state.errorMessage != null) {
          ErrorDiagnosticDialog.show(
            context,
            message: state.errorMessage!,
            referenceCode: state.referenceCode,
          );
        } else if (state.successMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.successMessage!),
              backgroundColor: Colors.green.shade800,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      },
      builder: (context, state) {
        final user = state.user ?? currentUser;
        final breakdown = state.storageBreakdown;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Settings'),
            elevation: 0,
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // 1. User Profile Header Card
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: theme.colorScheme.primary,
                        child: Text(
                          user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user.email,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Edit Profile',
                        onPressed: () => _showEditProfileDialog(context, user),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),



              // 2. Account & Security Section
              _buildSectionHeader(theme, 'Account & Security'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.lock_reset_rounded),
                      title: const Text('Change Password'),
                      subtitle: const Text('Update your login password'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showChangePasswordDialog(context),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 3. Privacy Section
              _buildSectionHeader(theme, 'Privacy'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.visibility_rounded),
                      title: const Text('Show Last Seen Status'),
                      subtitle: Text(
                        user.showLastSeen
                            ? 'Contacts can see when you were last active.'
                            : 'Your last seen timestamp is hidden from all users.',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      value: user.showLastSeen,
                      onChanged: (val) {
                        context.read<SettingsBloc>().add(ToggleLastSeenPrivacyEvent(val));
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 4. Appearance & Theme Section
              _buildSectionHeader(theme, 'Appearance & Theme'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: BlocBuilder<ThemeCubit, ThemeMode>(
                  builder: (context, themeMode) {
                    final cubit = context.read<ThemeCubit>();
                    final icon = themeMode == ThemeMode.dark
                        ? Icons.dark_mode_rounded
                        : themeMode == ThemeMode.light
                            ? Icons.light_mode_rounded
                            : Icons.brightness_auto_rounded;

                    return ListTile(
                      leading: Icon(icon, color: theme.colorScheme.primary),
                      title: const Text('App Theme'),
                      subtitle: Text(
                        cubit.currentThemeName,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showThemeSelectionDialog(context, themeMode),
                    );
                  },
                ),
              ),

              const SizedBox(height: 20),

              // 5. E2EE PIN Backup Section
              _buildSectionHeader(theme, 'End-to-End Encryption Backup'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: const Icon(Icons.shield_outlined, color: Colors.tealAccent),
                  title: const Text('Change 6-Digit Backup PIN'),
                  subtitle: Text(
                    'Update the PIN used to protect and restore your chat messages.',
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final changed = await E2eePinDialog.show(
                      context,
                      mode: E2eePinDialogMode.change,
                      barrierDismissible: true,
                    );
                    if (changed && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('6-Digit PIN backup updated successfully!'),
                          backgroundColor: Colors.teal,
                        ),
                      );
                    }
                  },
                ),
              ),

              const SizedBox(height: 20),

              // 5. Storage & Data Management Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSectionHeader(theme, 'Storage & Data Management'),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: 'Refresh Storage',
                    onPressed: () {
                      context.read<SettingsBloc>().add(const LoadStorageBreakdownEvent());
                    },
                  ),
                ],
              ),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total Storage Used',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            breakdown.totalFormatted,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      const SizedBox(height: 12),

                      _buildStorageRow(theme, Icons.image, 'Photos & Images', breakdown.imagesFormatted, Colors.blue),
                      const SizedBox(height: 8),
                      _buildStorageRow(theme, Icons.videocam, 'Videos', breakdown.videosFormatted, Colors.purple),
                      const SizedBox(height: 8),
                      _buildStorageRow(theme, Icons.mic, 'Voice Notes & Audio', breakdown.audioFormatted, Colors.teal),
                      const SizedBox(height: 8),
                      _buildStorageRow(theme, Icons.description, 'Documents & Files', breakdown.documentsFormatted, Colors.orange),
                      const SizedBox(height: 8),
                      _buildStorageRow(theme, Icons.storage, 'Local Message Database', breakdown.databaseFormatted, Colors.blueGrey),

                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _confirmClearMediaCache(context),
                          icon: const Icon(Icons.cleaning_services_rounded, size: 18),
                          label: const Text('Clear Cached Media'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // 5. Logout Button
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Log Out'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.withOpacity(0.12),
                    foregroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildStorageRow(
    ThemeData theme,
    IconData icon,
    String title,
    String formattedSize,
    Color iconColor,
  ) {
    return Row(
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          formattedSize,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  void _showEditProfileDialog(BuildContext context, UserEntity user) {
    final nameCtrl = TextEditingController(text: user.name);
    final emailCtrl = TextEditingController(text: user.email);
    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Profile'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Display Name'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Name cannot be empty' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'Email Address'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Email cannot be empty';
                  if (!v.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                context.read<SettingsBloc>().add(
                      UpdateProfileEvent(
                        name: nameCtrl.text.trim(),
                        email: emailCtrl.text.trim(),
                      ),
                    );
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Password'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: currentCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Current Password'),
                validator: (v) => v == null || v.isEmpty ? 'Current password is required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: newCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New Password (min 8 chars)'),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'New password is required';
                  if (v.length < 8) return 'Password must be at least 8 characters';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: confirmCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirm New Password'),
                validator: (v) {
                  if (v != newCtrl.text) return 'Passwords do not match';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                context.read<SettingsBloc>().add(
                      UpdatePasswordEvent(
                        currentPassword: currentCtrl.text,
                        newPassword: newCtrl.text,
                        confirmPassword: confirmCtrl.text,
                      ),
                    );
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('Update Password'),
          ),
        ],
      ),
    );
  }

  void _confirmClearMediaCache(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Cached Media?'),
        content: const Text(
          'This will delete downloaded images, videos, audio notes, and files from your device storage to free up space.\n\nYour message history and encrypted text will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.of(ctx).pop();
              context.read<SettingsBloc>().add(const ClearMediaCacheEvent());
            },
            child: const Text('Clear Now'),
          ),
        ],
      ),
    );
  }
  void _showThemeSelectionDialog(BuildContext context, ThemeMode currentMode) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.palette_outlined, size: 22),
              SizedBox(width: 10),
              Text('Choose Theme', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<ThemeMode>(
                value: ThemeMode.dark,
                groupValue: currentMode,
                secondary: const Icon(Icons.dark_mode_rounded, color: Colors.indigoAccent),
                title: const Text('Dark Mode'),
                subtitle: const Text('Easy on the eyes in low light', style: TextStyle(fontSize: 12)),
                onChanged: (mode) {
                  if (mode != null) {
                    context.read<ThemeCubit>().setThemeMode(mode);
                    Navigator.pop(ctx);
                  }
                },
              ),
              RadioListTile<ThemeMode>(
                value: ThemeMode.light,
                groupValue: currentMode,
                secondary: const Icon(Icons.light_mode_rounded, color: Colors.amber),
                title: const Text('Light Mode'),
                subtitle: const Text('Bright and clean interface', style: TextStyle(fontSize: 12)),
                onChanged: (mode) {
                  if (mode != null) {
                    context.read<ThemeCubit>().setThemeMode(mode);
                    Navigator.pop(ctx);
                  }
                },
              ),
              RadioListTile<ThemeMode>(
                value: ThemeMode.system,
                groupValue: currentMode,
                secondary: const Icon(Icons.brightness_auto_rounded, color: Colors.teal),
                title: const Text('System Default'),
                subtitle: const Text('Follows your device system settings', style: TextStyle(fontSize: 12)),
                onChanged: (mode) {
                  if (mode != null) {
                    context.read<ThemeCubit>().setThemeMode(mode);
                    Navigator.pop(ctx);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }
}
