import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:ani_dash/features/home/view_model/watch_history_notifier.dart';
import 'package:ani_dash/shared/auth/providers/auth_notifier.dart';
import 'package:ani_dash/shared/providers/settings/theme_notifier.dart';
import 'package:ani_dash/shared/ui/sponsor/sponsor_dialog.dart';
import 'package:ani_dash/router/router_wrapper.dart';

class MacDesktopSidebar extends ConsumerStatefulWidget {
  final StatefulNavigationShell shell;
  final List<NavItem> items;
  final void Function(int branchIndex) onTabSelected;
  final bool isCollapsed;
  final VoidCallback onToggleCollapse;

  const MacDesktopSidebar({
    super.key,
    required this.shell,
    required this.items,
    required this.onTabSelected,
    required this.isCollapsed,
    required this.onToggleCollapse,
  });

  @override
  ConsumerState<MacDesktopSidebar> createState() => _MacDesktopSidebarState();
}

class _MacDesktopSidebarState extends ConsumerState<MacDesktopSidebar> {
  String? _hoveredItem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final auth = ref.watch(authProvider);
    final isCollapsed = widget.isCollapsed;
    final user = auth.anilistUser ?? auth.malUser;

    final currentRoute = GoRouterState.of(context).matchedLocation;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: isCollapsed ? 76 : 260,
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.surfaceContainerLowest.withValues(alpha: 0.95)
            : colorScheme.surfaceContainerLow,
        border: Border(
          right: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. macOS Header with Window Controls Inset & Brand
          _buildHeader(context, colorScheme, isCollapsed),

          const SizedBox(height: 6),

          // 2. Quick Action CTA (Antigravity's "New Conversation" / "+ Action")
          _buildHeroActionButton(context, colorScheme, isCollapsed),

          const SizedBox(height: 12),

          // 3. Scrollable Navigation & Sections
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: isCollapsed ? 8 : 12,
                vertical: 4,
              ),
              children: [
                // SECTION: DISCOVER / CORE
                if (!isCollapsed) _buildSectionHeader('DISCOVER', colorScheme),
                ...widget.items.map((item) {
                  final isSelected =
                      widget.shell.currentIndex == item.branchIndex &&
                      (currentRoute == '/' ||
                          currentRoute == '/browse' ||
                          currentRoute == '/manga' ||
                          currentRoute == '/downloads' ||
                          currentRoute == '/watchlist');

                  return _SidebarTile(
                    icon: item.icon,
                    label: item.label,
                    isSelected: isSelected,
                    isCollapsed: isCollapsed,
                    onTap: () => widget.onTabSelected(item.branchIndex),
                  );
                }),

                const SizedBox(height: 14),

                // SECTION: ACTIVITY & LIBRARY (Like AGY Conversation History)
                if (!isCollapsed)
                  _buildSectionHeader('LIBRARY & ACTIVITY', colorScheme),
                _SidebarTile(
                  icon: Iconsax.clock,
                  label: 'Watch History',
                  isSelected: currentRoute == '/watch-history',
                  isCollapsed: isCollapsed,
                  badgeText: _getRecentHistoryCountBadge(),
                  onTap: () => context.push('/watch-history'),
                ),
                _SidebarTile(
                  icon: Iconsax.messages_3,
                  label: 'AniAI Assistant',
                  isSelected: currentRoute == '/ai',
                  isCollapsed: isCollapsed,
                  isAiSparkle: true,
                  onTap: () => context.push('/ai'),
                ),
                _SidebarTile(
                  icon: Iconsax.document_text,
                  label: 'Anime News',
                  isSelected: currentRoute == '/news',
                  isCollapsed: isCollapsed,
                  onTap: () => context.push('/news'),
                ),
                _SidebarTile(
                  icon: Iconsax.notification,
                  label: 'Notifications',
                  isSelected: currentRoute == '/notifications',
                  isCollapsed: isCollapsed,
                  onTap: () => context.push('/notifications'),
                ),

                const SizedBox(height: 14),

                // SECTION: EXTENSIONS (Like AGY Projects)
                if (!isCollapsed)
                  _buildSectionHeader('EXTENSIONS & SOURCES', colorScheme),
                _SidebarTile(
                  icon: Icons.extension_outlined,
                  label: 'Extensions',
                  isSelected: currentRoute == '/extensions',
                  isCollapsed: isCollapsed,
                  onTap: () => context.push('/extensions'),
                ),

                const SizedBox(height: 14),

                // SECTION: PREFERENCES (Full direct Android settings access)
                if (!isCollapsed)
                  _buildSectionHeader('PREFERENCES', colorScheme),
                _SidebarTile(
                  icon: Iconsax.setting_2,
                  label: 'All Settings',
                  isSelected: currentRoute == '/settings',
                  isCollapsed: isCollapsed,
                  onTap: () => context.push('/settings'),
                ),
                _SidebarTile(
                  icon: Iconsax.colorfilter,
                  label: 'Appearance & Themes',
                  isSelected: currentRoute == '/settings/theme',
                  isCollapsed: isCollapsed,
                  onTap: () => context.push('/settings/theme'),
                ),
                _SidebarTile(
                  icon: Iconsax.video_play,
                  label: 'Player Settings',
                  isSelected: currentRoute == '/settings/player',
                  isCollapsed: isCollapsed,
                  onTap: () => context.push('/settings/player'),
                ),
                _SidebarTile(
                  icon: Iconsax.user_tag,
                  label: 'Account & Tracking',
                  isSelected: currentRoute == '/settings/account',
                  isCollapsed: isCollapsed,
                  onTap: () => context.push('/settings/account'),
                ),
              ],
            ),
          ),

          // 4. Bottom Footer: User Profile & Quick Actions
          _buildFooter(context, colorScheme, user, isCollapsed),
        ],
      ),
    );
  }

  String? _getRecentHistoryCountBadge() {
    try {
      final historyState = ref.watch(watchHistoryNotifierProvider);
      if (historyState.history.isNotEmpty) {
        return historyState.history.length > 99
            ? '99+'
            : '${historyState.history.length}';
      }
    } catch (_) {}
    return null;
  }

  Widget _buildHeader(
    BuildContext context,
    ColorScheme colorScheme,
    bool isCollapsed,
  ) {
    // macOS traffic lights sit on top left: provide clean breathing room
    final topInset = Platform.isMacOS ? 38.0 : 16.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(isCollapsed ? 10 : 16, topInset, 12, 10),
      child: Row(
        mainAxisAlignment:
            isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween,
        children: [
          if (!isCollapsed) ...[
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      'assets/icons/anidash_logo.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'AniDash',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'macOS Desktop',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                'assets/icons/anidash_logo.png',
                fit: BoxFit.cover,
              ),
            ),
          ],
          IconButton(
            tooltip: isCollapsed ? 'Expand Sidebar' : 'Collapse Sidebar',
            iconSize: 18,
            style: IconButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(6),
            ),
            icon: Icon(
              isCollapsed ? Iconsax.sidebar_right : Iconsax.sidebar_left,
              color: colorScheme.onSurfaceVariant,
            ),
            onPressed: widget.onToggleCollapse,
          ),
        ],
      ),
    );
  }

  Widget _buildHeroActionButton(
    BuildContext context,
    ColorScheme colorScheme,
    bool isCollapsed,
  ) {
    if (isCollapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Tooltip(
          message: 'Ask AniAI Assistant',
          child: InkWell(
            onTap: () => context.push('/ai'),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primary,
                    colorScheme.tertiary,
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Iconsax.magicpen,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: InkWell(
        onTap: () => context.push('/ai'),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colorScheme.primary.withValues(alpha: 0.16),
                colorScheme.tertiary.withValues(alpha: 0.12),
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Iconsax.magicpen,
                  color: Colors.white,
                  size: 15,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ask AniAI',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'Recommend & Explore',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  'AI',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(left: 10, top: 10, bottom: 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  Widget _buildFooter(
    BuildContext context,
    ColorScheme colorScheme,
    dynamic user,
    bool isCollapsed,
  ) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCollapsed ? 8 : 12,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          if (!isCollapsed)
            InkWell(
              onTap: () => context.push('/settings/account'),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: colorScheme.primary.withValues(alpha: 0.15),
                      backgroundImage: user?.avatar != null
                          ? CachedNetworkImageProvider(user.avatar!)
                          : null,
                      child: user?.avatar == null
                          ? Icon(Iconsax.user, size: 16, color: colorScheme.primary)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.name ?? 'Guest User',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: user != null
                                      ? Colors.greenAccent
                                      : Colors.grey,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                user != null ? 'Synced' : 'Not logged in',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      iconSize: 16,
                      tooltip: 'Sponsor AniDash 💖',
                      icon: const Icon(
                        Icons.favorite_rounded,
                        color: Colors.pinkAccent,
                      ),
                      onPressed: () => SponsorDialog.show(context),
                    ),
                  ],
                ),
              ),
            )
          else
            IconButton(
              iconSize: 18,
              tooltip: user?.name ?? 'Account',
              icon: Icon(Iconsax.user, color: colorScheme.primary),
              onPressed: () => context.push('/settings/account'),
            ),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isCollapsed;
  final String? badgeText;
  final bool isAiSparkle;
  final VoidCallback onTap;

  const _SidebarTile({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.isCollapsed,
    this.badgeText,
    this.isAiSparkle = false,
    required this.onTap,
  });

  @override
  State<_SidebarTile> createState() => _SidebarTileState();
}

class _SidebarTileState extends State<_SidebarTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSelected = widget.isSelected;
    final isCollapsed = widget.isCollapsed;

    final content = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: EdgeInsets.symmetric(
            horizontal: isCollapsed ? 0 : 10,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primary.withValues(alpha: 0.16)
                : (_isHovered
                    ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary.withValues(alpha: 0.3)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment:
                isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Icon(
                widget.icon,
                size: 19,
                color: isSelected
                    ? colorScheme.primary
                    : (_isHovered
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant),
              ),
              if (!isCollapsed) ...[
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected
                          ? colorScheme.primary
                          : (_isHovered
                              ? colorScheme.onSurface
                              : colorScheme.onSurfaceVariant),
                    ),
                  ),
                ),
                if (widget.badgeText != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      widget.badgeText!,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? colorScheme.onPrimary
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );

    if (isCollapsed) {
      return Tooltip(
        message: widget.label,
        waitDuration: const Duration(milliseconds: 300),
        child: content,
      );
    }

    return content;
  }
}
