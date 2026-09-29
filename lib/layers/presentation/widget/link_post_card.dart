import 'package:adnetwork/config/asset_manager.dart';
import 'package:adnetwork/config/theme/styles_manager.dart';
import 'package:adnetwork/layers/data/model/link_model.dart';

import 'package:flutter/material.dart';

/// Redesigned link post card matching the app's feed style.
class LinkPostCard extends StatelessWidget {
  final LinkModel link;
  final VoidCallback onLike;
  final VoidCallback? onUserTap;

  /// Seconds remaining on the like cooldown (0 = ready to like).
  final int likeCooldownSeconds;

  const LinkPostCard({
    super.key,
    required this.link,
    required this.onLike,
    this.onUserTap,
    this.likeCooldownSeconds = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final bool isCoolingDown = !link.isLiked && likeCooldownSeconds > 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: .4)),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: .03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── User Row ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 8, 0),
            child: GestureDetector(
              onTap: onUserTap,
              child: Row(
                children: [
                  // Avatar with online indicator
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: cs.primary.withValues(alpha: .2),
                            ),
                            image: DecorationImage(
                              image: AssetImage(ImageAssets.adNetworkLogo),
                              fit: BoxFit.fill,
                            ),
                          ),
                          // padding: const EdgeInsets.all(5.0),
                          // child: Image.asset(ImageAssets.adNetworkLogo, fit: BoxFit.fill,),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: cs.secondary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: cs.primaryContainer,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "AdNetwork",
                          style: getSemiBoldStyle(
                            fontSize: 15,
                            color: cs.onSurface,
                          ),
                        ),
                        Row(
                          children: [
                            Icon(
                              Icons.public_rounded,
                              size: 13,
                              color: cs.onSurface.withValues(alpha: .4),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Published : ${link.formattedPublishedDate}',
                              style: getRegularStyle(
                                fontSize: 11,
                                color: cs.onSurface.withValues(alpha: .45),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      color: cs.onSurface.withValues(alpha: .4),
                    ),
                    onPressed: () {},
                    splashRadius: 20,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Inner Content Card ──
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [
                        cs.primary.withValues(alpha: 0.1),
                        cs.primary.withValues(alpha: 0.02),
                      ]
                    : [
                        cs.primary.withValues(alpha: 0.05),
                        cs.primary.withValues(alpha: 0.01),
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cs.primary.withValues(alpha: isDark ? 0.15 : 0.08),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withValues(alpha: isDark ? 0.02 : 0.01),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header: Task ID & Status Chip
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.rocket_launch_rounded,
                                size: 18,
                                color: cs.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Task ID',
                                    style: getRegularStyle(
                                      fontSize: 11,
                                      color: cs.onSurface.withValues(alpha: .5),
                                    ),
                                  ),
                                  Text(
                                    '#${link.id?.toUpperCase() ?? ''}',
                                    style: getBoldStyle(
                                      fontSize: 15,
                                      color: cs.onSurface,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Status Chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: cs.secondary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: cs.secondary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.public_rounded,
                              size: 12,
                              color: cs.secondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              link.status ?? 'Unknown',
                              style: getSemiBoldStyle(
                                fontSize: 11,
                                color: cs.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Divider
                  Divider(
                    height: 1,
                    color: cs.onSurface.withValues(alpha: 0.05),
                  ),
                  const SizedBox(height: 12),

                  // Description / Message
                  if (link.description != null &&
                      link.description!.isNotEmpty) ...[
                    RichText(
                      text: TextSpan(
                        style: getRegularStyle(
                          fontSize: 13,
                          color: cs.onSurface.withValues(alpha: .8),
                        ),
                        children: [
                          TextSpan(
                            text: '${link.description!.split('.').first}. ',
                          ),
                          TextSpan(
                            text: 'Opportunities',
                            style: getSemiBoldStyle(
                              fontSize: 13,
                              color: cs.primary,
                            ),
                          ),
                          TextSpan(
                            text:
                                '. Stay proactive & follow the user to keep the tasks coming your way! ✅',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    RichText(
                      text: TextSpan(
                        style: getRegularStyle(
                          fontSize: 13,
                          color: cs.onSurface.withValues(alpha: .8),
                        ),
                        children: [
                          TextSpan(text: 'Stay connected for more '),
                          TextSpan(
                            text: 'Opportunities',
                            style: getSemiBoldStyle(
                              fontSize: 13,
                              color: cs.primary,
                            ),
                          ),
                          TextSpan(text: '! Keep the tasks coming your way. ✅'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Footer metadata
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 14,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Published: ${link.formattedPublishedDate}',
                          style: getMediumStyle(
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Footer ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              children: [
                Text(
                  'Create',
                  style: getRegularStyle(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: .35),
                  ),
                ),
                Text(
                  '*Best Community',
                  style: getMediumStyle(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: .45),
                  ),
                ),
                const Spacer(),
                Text(
                  '(${link.likesCount}) Likes',
                  style: getMediumStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: .5),
                  ),
                ),
                const SizedBox(width: 12),

                // ── Like Button with Cooldown ──
                GestureDetector(
                  onTap: link.isLiked || isCoolingDown ? null : onLike,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: link.isLiked
                          ? cs.error.withValues(alpha: .08)
                          : isCoolingDown
                          ? cs.onSurface.withValues(alpha: .06)
                          : cs.onSurface.withValues(alpha: .04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: link.isLiked
                            ? cs.error.withValues(alpha: .2)
                            : isCoolingDown
                            ? cs.primary.withValues(alpha: .15)
                            : cs.onSurface.withValues(alpha: .1),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          link.isLiked
                              ? Icons.thumb_up_alt_rounded
                              : Icons.thumb_up_off_alt_rounded,
                          size: 16,
                          color: link.isLiked
                              ? cs.error
                              : isCoolingDown
                              ? cs.onSurface.withValues(alpha: .25)
                              : cs.onSurface.withValues(alpha: .45),
                        ),
                        // Show countdown ONLY on cards that have NOT been liked yet
                        if (!link.isLiked && likeCooldownSeconds > 0) ...[
                          const SizedBox(width: 6),
                          Text(
                            '${likeCooldownSeconds}s',
                            style: getBoldStyle(
                              fontSize: 12,
                              color: cs.primary.withValues(alpha: .7),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
