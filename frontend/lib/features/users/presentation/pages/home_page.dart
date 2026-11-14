import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/crypto/e2ee_manager.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/network/websocket_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/e2ee_pin_dialog.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_event.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../../../auth/presentation/pages/login_page.dart';
import '../../../call/presentation/pages/video_call_page.dart';
import '../../../call/presentation/pages/voice_call_page.dart';
import 'package:intl/intl.dart';
import '../../../chat/presentation/pages/chat_page.dart';
import '../../../settings/presentation/bloc/settings_bloc.dart';
import '../../../settings/presentation/bloc/settings_event.dart';
import '../../../settings/presentation/pages/network_settings_dialog.dart';
import '../../../settings/presentation/screens/settings_screen.dart';
import 'user_profile_page.dart';

import '../bloc/users_bloc.dart';
import '../bloc/users_event.dart';
import '../bloc/users_state.dart';

class HomePage extends StatefulWidget {
  final UserEntity currentUser;

  const HomePage({super.key, required this.currentUser});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    context.read<UsersBloc>().add(const FetchUsersRequested());

    // Connect WebSocket and listen on private user channel
    sl<WebSocketService>().connect();
    sl<WebSocketService>().subscribeToUserChannel(widget.currentUser.id);

    WidgetsBinding.instance.addPostFrameCallback((_) => _checkE2eeKeyBackupStatus());
  }

  Future<void> _checkE2eeKeyBackupStatus() async {
    final e2ee = sl<E2eeManager>();
    final hasLocal = await e2ee.keyManager.hasKeyPair();

    if (!hasLocal) {
      final cloudInfo = await e2ee.fetchCloudBackup();
      if (!mounted) return;

      if (cloudInfo.hasBackup) {
        await E2eePinDialog.show(
          context,
          mode: E2eePinDialogMode.restore,
          barrierDismissible: false,
        );
      } else {
        await e2ee.keyManager.generateAndSaveKeyPair();
        await e2ee.syncPublicKeyWithBackend();
        if (!mounted) return;
        await E2eePinDialog.show(
          context,
          mode: E2eePinDialogMode.setup,
          barrierDismissible: true,
        );
      }
    } else {
      final cloudInfo = await e2ee.fetchCloudBackup();
      if (!cloudInfo.hasBackup && mounted) {
        await E2eePinDialog.show(
          context,
          mode: E2eePinDialogMode.setup,
          barrierDismissible: true,
        );
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface(context),
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out of ChatAPP?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary(context))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentRose),
            onPressed: () {
              Navigator.of(ctx).pop();
              context.read<AuthBloc>().add(const AuthLogoutRequested());
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  String _formatLastSeen(DateTime dt) {
    final diff = DateTime.now().toUtc().difference(dt.toUtc());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM d, HH:mm').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is Unauthenticated) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
          );
        }
      },
      child: Scaffold(

      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('ChatAPP', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.accent.withOpacity(0.5), width: 1),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shield_outlined, size: 11, color: AppColors.accent),
                      SizedBox(width: 3),
                      Text('E2EE', style: TextStyle(fontSize: 10, color: AppColors.accent, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
            Text(
              widget.currentUser.name,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.settings_outlined, color: AppColors.textSecondary(context)),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BlocProvider(
                    create: (_) => sl<SettingsBloc>()..add(LoadSettingsEvent(widget.currentUser)),
                    child: SettingsScreen(
                      currentUser: widget.currentUser,
                      onLogout: _confirmLogout,
                    ),
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.tune, color: AppColors.textSecondary(context)),
            tooltip: 'Server Settings',
            onPressed: () => NetworkSettingsDialog.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.accentRose),
            tooltip: 'Sign Out',
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search contacts by name or email...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
            ),
          ),

          // Users Directory List
          Expanded(
            child: BlocBuilder<UsersBloc, UsersState>(
              builder: (context, state) {
                if (state is UsersLoading) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  );
                }

                if (state is UsersError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 48, color: AppColors.accentRose),
                          const SizedBox(height: 12),
                          Text(
                            state.message,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () => context.read<UsersBloc>().add(const FetchUsersRequested()),
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Try Again'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (state is UsersLoaded) {
                  final filteredUsers = state.users.where((u) {
                    if (_searchQuery.isEmpty) return true;
                    return u.name.toLowerCase().contains(_searchQuery) ||
                        u.email.toLowerCase().contains(_searchQuery);
                  }).toList();

                  if (filteredUsers.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: () async {
                        context.read<UsersBloc>().add(const RefreshUsersRequested());
                      },
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                          Icon(Icons.people_outline, size: 56, color: AppColors.textSecondary(context)),
                          const SizedBox(height: 16),
                          Center(
                            child: Text(
                              _searchQuery.isEmpty
                                  ? 'No other users registered yet.\nRegister another account from a second device to chat!'
                                  : 'No contacts match "$_searchQuery"',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: () async {
                      context.read<UsersBloc>().add(const RefreshUsersRequested());
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: filteredUsers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final peer = filteredUsers[index];
                        final hasKey = peer.publicIdentityKey != null && peer.publicIdentityKey!.isNotEmpty;

                        return Container(
                          decoration: BoxDecoration(
                            color: AppColors.surface(context),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF334155), width: 1),
                          ),
                            child: ListTile(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatPage(
                                    currentUser: widget.currentUser,
                                    peerUser: peer,
                                  ),
                                ),
                              );
                            },
                            onLongPress: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => UserProfilePage(
                                    currentUser: widget.currentUser,
                                    peerUser: peer,
                                  ),
                                ),
                              );
                            },
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            leading: GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => UserProfilePage(
                                      currentUser: widget.currentUser,
                                      peerUser: peer,
                                    ),
                                  ),
                                );
                              },
                              child: Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: AppColors.primary.withOpacity(0.2),
                                    child: Text(
                                      peer.name.isNotEmpty ? peer.name[0].toUpperCase() : '?',
                                      style: const TextStyle(
                                        color: AppColors.primaryLight,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: peer.isOnline ? AppColors.accent : Colors.amber,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: AppColors.surface(context), width: 2),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    peer.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                      color: AppColors.textPrimaryDark,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                if (hasKey)
                                  const Icon(Icons.lock, size: 13, color: AppColors.accent),
                              ],
                            ),
                            subtitle: Row(
                              children: [
                                if (peer.isOnline) ...[
                                  Container(
                                    width: 7,
                                    height: 7,
                                    margin: const EdgeInsets.only(right: 5),
                                    decoration: const BoxDecoration(
                                      color: AppColors.accent,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const Text(
                                    'Online',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.accent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ] else ...[
                                  Container(
                                    width: 7,
                                    height: 7,
                                    margin: const EdgeInsets.only(right: 5),
                                    decoration: const BoxDecoration(
                                      color: Colors.amber,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      peer.lastSeenAt != null
                                          ? 'Away • Last seen ${_formatLastSeen(peer.lastSeenAt!)}'
                                          : 'Away',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary(context),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.chat_bubble_outline, size: 20, color: AppColors.primaryLight),
                                  tooltip: 'Open Chat',
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ChatPage(
                                          currentUser: widget.currentUser,
                                          peerUser: peer,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                 IconButton(
                                  icon: const Icon(Icons.call_outlined, size: 20, color: AppColors.accent),
                                  tooltip: 'Voice Call',
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => VoiceCallPage(
                                          peerUser: peer,
                                          isOutgoing: true,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.videocam_outlined, size: 20, color: AppColors.primaryLight),
                                  tooltip: 'Video Call',
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => VideoCallPage(
                                          peerUser: peer,
                                          isOutgoing: true,
                                        ),
                                      ),
                                    );
                                  },
                                ),

                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                }

                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    ),
    );
  }
}

