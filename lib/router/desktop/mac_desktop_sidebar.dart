import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:ani_dash/features/home/view_model/watch_history_notifier.dart';
import 'package:ani_dash/shared/auth/providers/auth_notifier.dart';
import 'package:ani_dash/shared/ui/sponsor/sponsor_dialog.dart';
import 'package:ani_dash/shared/ui/brand_logo.dart';
import 'package:ani_dash/router/router_wrapper.dart';
import 'package:ani_dash/main.dart';

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
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final auth = ref.watch(authProvider);
    final isCollapsed = widget.isCollapsed;
    final user = auth.anilistUser ?? auth.malUser;
    final currentRoute = GoRouterState.of(context).matchedLocation;
    final isMac = Platform.isMacOS;
    final mod = isMac ? '⌘' : 'Ctrl+';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      width: isCollapsed ? 76 : 264,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF14161C).withValues(alpha: 0.82)
                  : const Color(0xFFF8F9FB).withValues(alpha: 0.88),
              border: Border(
                right: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.10)
                      : Colors.black.withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Desktop Header with Window Controls Inset & Brand
                _buildHeader(context, colorScheme, isCollapsed, isDark),

                const SizedBox(height: 6),

                // 2. Liquid Glass Hero Action Button ("Ask AniAI" / "New Conversation")
                _buildHeroActionButton(context, colorScheme, isCollapsed, isDark, mod),

                const SizedBox(height: 10),

                // 3. Scrollable Navigation Sections
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.symmetric(
                      horizontal: isCollapsed ? 8 : 12,
                      vertical: 2,
                    ),
                    children: [
                      // SECTION: DISCOVER
                      if (!isCollapsed)
                        _buildSectionHeader('DISCOVER', isDark),
                      ...widget.items.map((item) {
                        final isSelected =
                            widget.shell.currentIndex == item.branchIndex &&
                            (currentRoute == '/' ||
                                currentRoute == '/browse' ||
                                currentRoute == '/manga' ||
                                currentRoute == '/downloads' ||
                                currentRoute == '/watchlist');

                        final shortcutKey = switch (item.branchIndex) {
                          0 => '${mod}1',
                          1 => '${mod}2',
                          2 => '${mod}3',
                          3 => '${mod}4',
                          4 => '${mod}5',
                          _ => null,
                        };

                        return _SidebarTile(
                          icon: item.icon,
                          label: item.label,
                          shortcutHint: shortcutKey,
                          isSelected: isSelected,
                          isCollapsed: isCollapsed,
                          isDark: isDark,
                          onTap: () => widget.onTabSelected(item.branchIndex),
                        );
                      }),

                      const SizedBox(height: 14),

                      // SECTION: LIBRARY & ACTIVITY
                      if (!isCollapsed)
                        _buildSectionHeader('LIBRARY & ACTIVITY', isDark),
                      _SidebarTile(
                        icon: Iconsax.clock,
                        label: 'Watch History',
                        shortcutHint: '${mod}H',
                        isSelected: currentRoute == '/watch-history' ||
                            currentRoute == '/settings/watch-history',
                        isCollapsed: isCollapsed,
                        isDark: isDark,
                        badgeText: _getRecentHistoryCountBadge(),
                        onTap: () {
                          _markHistoryBadgeAsSeen();
                          context.push('/watch-history');
                        },
                      ),
                      _SidebarTile(
                        icon: Iconsax.magicpen,
                        label: 'AniCore',
                        shortcutHint: '${mod}K',
                        isSelected: currentRoute == '/ai',
                        isCollapsed: isCollapsed,
                        isDark: isDark,
                        isAiSparkle: true,
                        onTap: () => context.push('/ai'),
                      ),
                      _SidebarTile(
                        icon: Iconsax.document_text,
                        label: 'Anime News',
                        shortcutHint: '${mod}N',
                        isSelected: currentRoute == '/news',
                        isCollapsed: isCollapsed,
                        isDark: isDark,
                        onTap: () => context.push('/news'),
                      ),

                      const SizedBox(height: 14),

                      // SECTION: SETTINGS
                      if (!isCollapsed)
                        _buildSectionHeader('SETTINGS', isDark),
                      _SidebarTile(
                        icon: Iconsax.setting_2,
                        label: 'Settings',
                        shortcutHint: '$mod,',
                        isSelected: currentRoute == '/settings',
                        isCollapsed: isCollapsed,
                        isDark: isDark,
                        onTap: () => context.push('/settings'),
                      ),
                    ],
                  ),
                ),

                // 4. Bottom Footer: User Profile & Quick Actions
                _buildFooter(context, colorScheme, user, isCollapsed, isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _markHistoryBadgeAsSeen() {
    try {
      final historyState = ref.read(watchHistoryProvider);
      final count = historyState.history.length;
      sharedPrefs.setInt('watch_history_seen_count', count);
      sharedPrefs.setInt(
        'watch_history_last_seen_time',
        DateTime.now().millisecondsSinceEpoch,
      );
      if (mounted) setState(() {});
    } catch (_) {}
  }

  String? _getRecentHistoryCountBadge() {
    try {
      final historyState = ref.watch(watchHistoryProvider);
      final total = historyState.history.length;
      final seenCount = sharedPrefs.getInt('watch_history_seen_count') ?? 0;
      final lastSeenTime =
          sharedPrefs.getInt('watch_history_last_seen_time') ?? 0;

      // If user has already opened Watch History, only show count if new items were watched after
      if (lastSeenTime > 0) {
        final newItems = historyState.history.where((e) {
          final t = e.effectiveLastPlayedTime.millisecondsSinceEpoch;
          return t > lastSeenTime;
        }).length;
        if (newItems == 0) return null;
        return newItems > 99 ? '99+' : '$newItems';
      }

      final unseen = total - seenCount;
      if (unseen > 0) {
        return unseen > 99 ? '99+' : '$unseen';
      }
    } catch (_) {}
    return null;
  }

  Widget _buildHeader(
    BuildContext context,
    ColorScheme colorScheme,
    bool isCollapsed,
    bool isDark,
  ) {
    // macOS traffic lights sit on top left: leave proper top space
    final topInset = Platform.isMacOS ? 38.0 : 16.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(isCollapsed ? 12 : 16, topInset, 12, 10),
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
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.28),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: BrandLogo(
                      size: 32,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'AniDash',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Collapse Sidebar',
              iconSize: 18,
              style: IconButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(6),
              ),
              icon: Icon(
                Iconsax.sidebar_left,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
              onPressed: widget.onToggleCollapse,
            ),
          ] else ...[
            Tooltip(
              message: 'Expand Sidebar',
              child: InkWell(
                onTap: widget.onToggleCollapse,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: BrandLogo(
                    size: 32,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeroActionButton(
    BuildContext context,
    ColorScheme colorScheme,
    bool isCollapsed,
    bool isDark,
    String mod,
  ) {
    if (isCollapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Tooltip(
          message: 'Ask AniCore (${mod}K)',
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
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colorScheme.primary.withValues(alpha: isDark ? 0.22 : 0.16),
                colorScheme.tertiary.withValues(alpha: isDark ? 0.16 : 0.10),
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.18)
                  : colorScheme.primary.withValues(alpha: 0.35),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(7),
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
                      'Ask AniCore',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      'Recommend & Explore',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '${mod}K',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 10, top: 8, bottom: 5),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9,
          color: isDark ? Colors.white38 : Colors.black38,
        ),
      ),
    );
  }

  Widget _buildFooter(
    BuildContext context,
    ColorScheme colorScheme,
    dynamic user,
    bool isCollapsed,
    bool isDark,
  ) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCollapsed ? 8 : 12,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
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
                      backgroundImage: (user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty)
                          ? CachedNetworkImageProvider(user.avatarUrl!)
                          : null,
                      child: (user?.avatarUrl == null || user!.avatarUrl!.isEmpty)
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
                              color: isDark ? Colors.white : Colors.black87,
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
                                  color: isDark ? Colors.white54 : Colors.black54,
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
  final String? shortcutHint;
  final bool isSelected;
  final bool isCollapsed;
  final bool isDark;
  final String? badgeText;
  final bool isAiSparkle;
  final VoidCallback onTap;

  const _SidebarTile({
    required this.icon,
    required this.label,
    this.shortcutHint,
    required this.isSelected,
    required this.isCollapsed,
    required this.isDark,
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
    final isDark = widget.isDark;

    final content = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.symmetric(vertical: 1.5),
          padding: EdgeInsets.symmetric(
            horizontal: isCollapsed ? 0 : 10,
            vertical: 7.5,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primary.withValues(alpha: isDark ? 0.22 : 0.16)
                : (_isHovered
                    ? (isDark
                        ? Colors.white.withValues(alpha: 0.07)
                        : Colors.black.withValues(alpha: 0.05))
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? (isDark
                      ? Colors.white.withValues(alpha: 0.14)
                      : colorScheme.primary.withValues(alpha: 0.3))
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
                size: 18,
                color: isSelected
                    ? colorScheme.primary
                    : (_isHovered
                        ? (isDark ? Colors.white : Colors.black87)
                        : (isDark ? Colors.white70 : Colors.black54)),
              ),
              if (!isCollapsed) ...[
                const SizedBox(width: 10),
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
                              ? (isDark ? Colors.white : Colors.black87)
                              : (isDark ? Colors.white70 : Colors.black54)),
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
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.15)
                              : Colors.black.withValues(alpha: 0.08)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      widget.badgeText!,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? colorScheme.onPrimary
                            : (isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                  ),
                ] else if (widget.shortcutHint != null && _isHovered) ...[
                  Text(
                    widget.shortcutHint!,
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.white38 : Colors.black38,
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
        message: '${widget.label} ${widget.shortcutHint ?? ""}',
        waitDuration: const Duration(milliseconds: 300),
        child: content,
      );
    }

    return content;
  }
}
