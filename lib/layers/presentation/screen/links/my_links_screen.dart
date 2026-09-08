import 'package:adnetwork/config/theme/styles_manager.dart';
import 'package:adnetwork/layers/presentation/controller/link/link_bloc.dart';
import 'package:adnetwork/layers/presentation/widget/common_text_field.dart';
import 'package:adnetwork/layers/presentation/controller/profile/profile_bloc.dart';
import 'package:adnetwork/layers/presentation/widget/gradient_button.dart';
import 'package:adnetwork/layers/presentation/widget/show_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:toastification/toastification.dart';

class MyLinksScreen extends StatelessWidget {
  const MyLinksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final user = context.watch<ProfileBloc>().state.currentUser;
    final maxLinks = user?.role == 'admin' ? 70 : 20;

    return BlocConsumer<LinkBloc, LinkState>(
      listener: (context, state) {
        if (state.errorMessage.isNotEmpty) {
          showToast(
            context: context,
            message: state.errorMessage,
            toastificationType: ToastificationType.error,
          );
          context.read<LinkBloc>().add(const ClearLinkError());
        }
      },
      builder: (context, state) {
        return SafeArea(
          child: Stack(
            children: [
              RefreshIndicator(
                color: cs.primary,
                onRefresh: () async {
                  context.read<LinkBloc>().add(const LoadMyLinks());
                  await Future.delayed(const Duration(milliseconds: 600));
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  slivers: [
                    SliverAppBar(
                      floating: true,
                      snap: true,
                      backgroundColor: cs.surface,
                      surfaceTintColor: Colors.transparent,
                      leading: IconButton(
                        icon: Icon(Icons.menu_rounded, color: cs.onSurface),
                        onPressed: () => Scaffold.of(context).openDrawer(),
                      ),
                      title: Text(
                        'My Links',
                        style: getBoldStyle(fontSize: 20, color: cs.onSurface),
                      ),
                      centerTitle: false,
                      actions: [
                        Container(
                          margin: const EdgeInsets.only(right: 16),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${state.links.length} / $maxLinks',
                            style: getMediumStyle(
                              fontSize: 12,
                              color: cs.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (state.status == LinkStatus.loading)
                      const SliverFillRemaining(
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (state.links.isEmpty)
                      SliverFillRemaining(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: .06),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.add_link_rounded,
                                  size: 48,
                                  color: cs.primary.withValues(alpha: .4),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'No links yet',
                                style: getSemiBoldStyle(
                                  fontSize: 18,
                                  color: cs.onSurface.withValues(alpha: .6),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Tap + to add your first link',
                                style: getRegularStyle(
                                  fontSize: 13,
                                  color: cs.onSurface.withValues(alpha: .35),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate((context, index) {
                            final link = state.links[index];
                            return TweenAnimationBuilder<double>(
                              key: ValueKey(link.id),
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: Duration(
                                milliseconds: 350 + (index * 60),
                              ),
                              curve: Curves.easeOutCubic,
                              builder: (ctx, val, child) => Opacity(
                                opacity: val,
                                child: Transform.translate(
                                  offset: Offset(0, 20 * (1 - val)),
                                  child: child,
                                ),
                              ),
                              child: Dismissible(
                                key: ValueKey(link.id),
                                direction: DismissDirection.endToStart,
                                onDismissed: (_) => context.read<LinkBloc>().add(
                                  DeleteLink(link.id ?? ''),
                                ),
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 24),
                                  margin: const EdgeInsets.symmetric(vertical: 6),
                                  decoration: BoxDecoration(
                                    color: cs.error.withValues(alpha: .12),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Icon(
                                    Icons.delete_outline_rounded,
                                    color: cs.error,
                                    size: 26,
                                  ),
                                ),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 6),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? cs.onSurface.withValues(alpha: .05)
                                        : cs.primaryContainer,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: cs.primary.withValues(
                                        alpha: isDark ? .12 : .06,
                                      ),
                                    ),
                                    boxShadow: [
                                      if (!isDark)
                                        BoxShadow(
                                          color: cs.primary.withValues(
                                            alpha: .04,
                                          ),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      // Link icon with accent bg
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              cs.primary.withValues(alpha: .15),
                                              cs.secondary.withValues(alpha: .1),
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          Icons.link_rounded,
                                          size: 22,
                                          color: cs.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      // URL + meta
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              link.url ?? '',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: getMediumStyle(
                                                fontSize: 13,
                                                color: cs.primary,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.favorite_rounded,
                                                  size: 14,
                                                  color: cs.error.withValues(
                                                    alpha: .7,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '${link.likesCount}',
                                                  style: getRegularStyle(
                                                    fontSize: 12,
                                                    color: cs.onSurface
                                                        .withValues(alpha: .5),
                                                  ),
                                                ),
                                                const SizedBox(width: 16),
                                                Icon(
                                                  Icons.access_time_rounded,
                                                  size: 13,
                                                  color: cs.onSurface.withValues(
                                                    alpha: .35,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  DateFormat(
                                                    'dd MMM yyyy',
                                                  ).format(
                                                    link.publishedDate ??
                                                        DateTime.now(),
                                                  ),
                                                  style: getRegularStyle(
                                                    fontSize: 12,
                                                    color: cs.onSurface
                                                        .withValues(alpha: .45),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Edit
                                      IconButton(
                                        onPressed: () => _showAddDialog(
                                          context,
                                          state.links,
                                          existingLink: link,
                                        ),
                                        icon: Icon(
                                          Icons.edit_outlined,
                                          size: 18,
                                          color: cs.onSurface.withValues(
                                            alpha: .35,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }, childCount: state.links.length),
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 90)),
                  ],
                ),
              ),
              // FAB
              if (state.links.length < maxLinks)
                Positioned(
                  right: 20,
                  bottom: 24,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [
                          cs.primary,
                          Color.lerp(cs.primary, cs.secondary, 0.5)!,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: .35),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _showAddDialog(context, state.links),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.add_rounded,
                                color: cs.onPrimary,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Add Link',
                                style: getMediumStyle(
                                  fontSize: 14,
                                  color: cs.onPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showAddDialog(
    BuildContext context,
    List<dynamic> currentLinks, {
    dynamic existingLink,
  }) {
    final urlCtrl = TextEditingController(text: existingLink?.url ?? '');
    final cs = Theme.of(context).colorScheme;
    final isEdit = existingLink != null;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          20,
          24,
          MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isEdit ? 'Edit Link' : 'Add New Link',
              style: getBoldStyle(fontSize: 20, color: cs.onSurface),
            ),
            const SizedBox(height: 6),
            Text(
              isEdit
                  ? 'Update the URL below'
                  : 'Paste a URL to share with the community',
              style: getRegularStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: .5),
              ),
            ),
            const SizedBox(height: 24),
            CommonTextField(
              label: 'Link URL',
              controller: urlCtrl,
              keyboardType: TextInputType.url,
              hintText: 'https://example.com/your-link',
              prefixIcon: Icons.link_rounded,
            ),
            const SizedBox(height: 24),
            GradientButton(
              buttonName: isEdit ? 'Update' : 'Add Link',
              icon: isEdit ? Icons.check_rounded : Icons.add_rounded,
              onPressed: () {
                final newUrl = urlCtrl.text.trim();
                if (newUrl.isEmpty) return;

                // Validate URL format
                final uri = Uri.tryParse(newUrl);
                final isValidUrl = uri != null &&
                    uri.hasScheme &&
                    (uri.scheme == 'http' || uri.scheme == 'https') &&
                    uri.host.isNotEmpty &&
                    uri.host.contains('.');
                if (!isValidUrl) {
                  showToast(
                    context: context,
                    message:
                        'Please enter a valid URL (e.g. https://example.com)',
                    toastificationType: ToastificationType.error,
                  );
                  return;
                }

                if (!isEdit) {
                  final alreadyExists = currentLinks.any(
                    (l) => l.url == newUrl,
                  );
                  if (alreadyExists) {
                    showToast(
                      context: context,
                      message: "This link is already available in your list.",
                      toastificationType: ToastificationType.error,
                    );
                    return;
                  }
                  context.read<LinkBloc>().add(AddLink(url: newUrl));
                } else {
                  context.read<LinkBloc>().add(
                    UpdateLink(linkId: existingLink.id, url: newUrl),
                  );
                }
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }
}
