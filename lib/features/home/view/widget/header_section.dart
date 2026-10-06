import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:ani_dash/core/services/auth_provider_enum.dart';
import 'package:ani_dash/core/models/auth/user.dart';
import 'package:ani_dash/shared/auth/providers/auth_notifier.dart';
import 'package:ani_dash/features/home/view/widget/search_model.dart';
import 'package:ani_dash/shared/providers/settings/experimental_notifier.dart';
import 'package:ani_dash/core/utils/greeting_methods.dart';
import 'package:ani_dash/core/services/notification_inbox_service.dart';
import 'package:ani_dash/features/ai/view/widgets/ask_nia_button.dart';
import 'package:ani_dash/shared/ui/sponsor/sponsor_dialog.dart';

class HeaderSection extends ConsumerWidget {
  final bool isDesktop;
  const HeaderSection({super.key, required this.isDesktop});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activePlatform = ref.watch(
      authProvider.select((s) => s.activePlatform),
    );
    final user = ref.watch(
      authProvider.select(
        (s) =>
            activePlatform == AuthPlatform.anilist ? s.anilistUser : s.malUser,
      ),
    );
    final useNewUI = ref.watch(experimentalProvider.select((s) => s.newUI));
    final colorScheme = Theme.of(context);
    return Column(
      children: [
        SizedBox(height: MediaQuery.viewPaddingOf(context).top),

        if (!useNewUI) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: UserProfileCard(user: user)),
              const SizedBox(width: 10),
              ActionPanel(isDesktop: isDesktop),
            ],
          ),
          const SizedBox(height: 10),
          const _DiscoverCard(),
        ]
        // NEW UI
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap:
                      () => context.push(
                        user != null
                            ? '/settings/account/profile'
                            : '/settings/account',
                      ),
                  child: _UserAvatar(user: user, size: 48),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        getGreeting(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: colorScheme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            user?.name ?? "Guest",
                            maxLines: 1,
                            style: colorScheme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const AskNiaButton(compact: true),
                const SizedBox(width: 8),
                const _NewsActionBadge(),
                const SizedBox(width: 8),
                const _NotificationInboxButton(),
                const SizedBox(width: 8),
                _ActionButton(
                  icon: Icons.favorite_rounded,
                  onTap: () => SponsorDialog.show(context),
                ),
                const SizedBox(width: 8),
                _ActionButton(
                  icon: Icons.settings_outlined,
                  onTap: () => context.push('/settings'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
      ],
    );
  }
}

class _DiscoverCard extends StatelessWidget {
  const _DiscoverCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _HeaderBaseCard(
      onTap: () => context.go('/browse'),
      gradient: LinearGradient(
        colors: [
          theme.colorScheme.primary.withValues(alpha: 0.15),
          theme.colorScheme.primary.withValues(alpha: 0.02),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Row(
        children: [
          _buildLeadingIcon(theme),
          const SizedBox(width: 16),
          const Expanded(child: _DiscoverTextContent()),
          Icon(
            Iconsax.arrow_right_3,
            color: theme.colorScheme.primary,
            size: 18,
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildLeadingIcon(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        Iconsax.discover_1,
        color: theme.colorScheme.onPrimary,
        size: 22,
      ),
    );
  }
}

class _DiscoverTextContent extends StatelessWidget {
  const _DiscoverTextContent();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Discover Anime',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'Find your next favorite series',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

class _NewsActionBadge extends ConsumerWidget {
  const _NewsActionBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ActionButton(
      icon: Iconsax.document_text,
      onTap: () => context.push('/news'),
    );
  }
}

class UserProfileCard extends StatelessWidget {
  final AuthUser? user;
  const UserProfileCard({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _HeaderBaseCard(
      color: theme.colorScheme.surface,
      onTap:
          () => context.push(
            user != null ? '/settings/account/profile' : '/settings/account',
          ),
      child: Row(
        children: [
          _UserAvatar(user: user),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user != null ? getGreeting() : 'Welcome!',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                Text(
                  user?.name ?? 'Guest',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  final AuthUser? user;
  final double size;

  const _UserAvatar({this.user, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decoration = BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    );

    if (user == null) {
      return Container(
        width: size,
        height: size,
        decoration: decoration,
        child: Icon(Iconsax.user, color: theme.colorScheme.primary),
      );
    }

    return Hero(
      tag: 'user-avatar',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: user!.avatarUrl ?? '',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorWidget:
              (_, _, _) => Container(
                color: decoration.color,
                child: const Icon(Icons.person),
              ),
          placeholder: (_, _) => Container(color: decoration.color),
        ),
      ),
    );
  }
}

class ActionPanel extends StatelessWidget {
  final bool isDesktop;
  const ActionPanel({super.key, required this.isDesktop});

  @override
  Widget build(BuildContext context) {
    final shortcuts = <ShortcutActivator, Intent>{
      for (var key in LogicalKeyboardKey.knownLogicalKeys)
        if (key.keyLabel.length == 1 &&
            RegExp(r'[a-zA-Z0-9]').hasMatch(key.keyLabel))
          SingleActivator(key): const OpenSearchIntent(),
    };

    return FocusableActionDetector(
      autofocus: true,
      shortcuts: shortcuts,
      actions: {
        OpenSearchIntent: CallbackAction<OpenSearchIntent>(
          onInvoke: (_) => showSearchModal(context, 'search_fab'),
        ),
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isDesktop) ...[
            const _NewsActionBadge(),
            const SizedBox(width: 8),
            const _NotificationInboxButton(),
            const SizedBox(width: 8),
          ],
          _ActionButton(
            icon: Icons.favorite_rounded,
            onTap: () => SponsorDialog.show(context),
          ),
          const SizedBox(width: 8),
          const _ActionButton(icon: Iconsax.setting_2, route: '/settings'),
        ],
      ),
    );
  }
}

class _NotificationInboxButton extends ConsumerWidget {
  const _NotificationInboxButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadNotificationCountProvider);
    return Badge(
      isLabelVisible: count > 0,
      label: Text(count > 99 ? '99+' : '$count'),
      child: _ActionButton(
        icon: Icons.notifications_none_rounded,
        onTap: () async {
          await context.push('/notifications');
          ref.read(unreadNotificationCountProvider.notifier).refresh();
        },
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String? route;
  final VoidCallback? onTap;

  const _ActionButton({required this.icon, this.route, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap ?? (route != null ? () => context.push(route!) : null),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(
            icon,
            color: theme.colorScheme.onSecondaryContainer,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _HeaderBaseCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  final Gradient? gradient;

  const _HeaderBaseCard({
    required this.child,
    this.onTap,
    this.gradient,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(20);

    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          color: color ?? Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Ink(
              decoration: BoxDecoration(gradient: gradient),
              child: Padding(padding: const EdgeInsets.all(12), child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class OpenSearchIntent extends Intent {
  const OpenSearchIntent();
}
