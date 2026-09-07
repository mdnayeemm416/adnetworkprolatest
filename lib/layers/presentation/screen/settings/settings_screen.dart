import 'package:adnetwork/config/asset_manager.dart';
import 'package:adnetwork/config/theme/styles_manager.dart';
import 'package:adnetwork/core/services/token_storage.dart';
import 'package:adnetwork/layers/data/repo/remote/user_repository.dart';
import 'package:adnetwork/layers/presentation/controller/profile/profile_bloc.dart';
import 'package:adnetwork/layers/presentation/controller/theme/theme_cubit.dart';
import 'package:adnetwork/layers/presentation/widget/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<ProfileBloc>().add(const LoadProfileStats());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profileState = context.watch<ProfileBloc>().state;
    final user = profileState.currentUser;
    final stats = profileState.stats;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Settings', style: getBoldStyle(fontSize: 20, color: cs.onSurface)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              // ── Account Card ──
              _SectionCard(
                isDark: isDark,
                cs: cs,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [cs.primary, cs.secondary]),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(shape: BoxShape.circle, color: cs.surface),
                        child: UserAvatar(username: user?.username ?? 'User', radius: 26),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user?.username ?? 'User', style: getSemiBoldStyle(fontSize: 16, color: cs.onSurface)),
                          const SizedBox(height: 2),
                          Text(user?.bio ?? '', style: getRegularStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .5))),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('PRO', style: getBoldStyle(fontSize: 11, color: cs.primary)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Activity & Limits ──
              _SectionTitle(title: 'Activity & Limits', cs: cs),
              const SizedBox(height: 10),
              _SectionCard(
                isDark: isDark,
                cs: cs,
                child: Column(
                  children: [
                    _SettingsValueTile(
                      icon: Icons.thumb_up_alt_rounded,
                      label: 'Max Like Back Limit',
                      subtitle: 'Daily like-back threshold',
                      value: stats != null
                          ? (stats.maxLikeBackLimit > 0 ? '${stats.maxLikeBackLimit}' : '0')
                          : '...',
                      cs: cs,
                      onTap: () => _showMaxLikeBackLimitSheet(context, stats?.maxLikeBackLimit ?? 0),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Appearance ──
              _SectionTitle(title: 'Appearance', cs: cs),
              const SizedBox(height: 10),
              BlocBuilder<ThemeCubit, ThemeMode>(
                builder: (context, themeMode) {
                  return _SectionCard(
                    isDark: isDark,
                    cs: cs,
                    child: Column(
                      children: [
                        _ThemeOption(
                          icon: Icons.light_mode_rounded,
                          label: 'Light Mode',
                          isSelected: themeMode == ThemeMode.light,
                          cs: cs,
                          isDark: isDark,
                          onTap: () => context.read<ThemeCubit>().setTheme(ThemeMode.light),
                        ),
                        _divider(cs),
                        _ThemeOption(
                          icon: Icons.dark_mode_rounded,
                          label: 'Dark Mode',
                          isSelected: themeMode == ThemeMode.dark,
                          cs: cs,
                          isDark: isDark,
                          onTap: () => context.read<ThemeCubit>().setTheme(ThemeMode.dark),
                        ),
                        _divider(cs),
                        _ThemeOption(
                          icon: Icons.settings_brightness_rounded,
                          label: 'System Default',
                          isSelected: themeMode == ThemeMode.system,
                          cs: cs,
                          isDark: isDark,
                          onTap: () => context.read<ThemeCubit>().setTheme(ThemeMode.system),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),

              // ── Account & Security ──
              _SectionTitle(title: 'Account & Security', cs: cs),
              const SizedBox(height: 10),
              _SectionCard(
                isDark: isDark,
                cs: cs,
                child: Column(
                  children: [
                    _SettingsTile(
                      icon: Icons.lock_outline_rounded,
                      label: 'Change Password',
                      cs: cs,
                      onTap: () => Navigator.pushNamed(context, '/change-password'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Support ──
              _SectionTitle(title: 'Support', cs: cs),
              const SizedBox(height: 10),
              _SectionCard(
                isDark: isDark,
                cs: cs,
                child: Column(
                  children: [
                    _SettingsTile(
                      icon: Icons.info_outline_rounded,
                      label: 'About Us',
                      cs: cs,
                      onTap: () => Navigator.pushNamed(context, '/about'),
                    ),
                    _divider(cs),
                    _SettingsTile(
                      icon: Icons.mail_outline_rounded,
                      label: 'Contact Us',
                      cs: cs,
                      onTap: () => Navigator.pushNamed(context, '/contact'),
                    ),
                    _divider(cs),
                    _SettingsTile(
                      icon: Icons.help_outline_rounded,
                      label: 'FAQ & Help',
                      cs: cs,
                      onTap: () => Navigator.pushNamed(context, '/faq'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── App Info ──
              _SectionTitle(title: 'App Info', cs: cs),
              const SizedBox(height: 10),
              _SectionCard(
                isDark: isDark,
                cs: cs,
                child: Column(
                  children: [
                    _SettingsTile(
                      icon: Icons.star_outline_rounded,
                      label: 'Rate App',
                      cs: cs,
                      onTap: () {},
                    ),
                    _divider(cs),
                    _SettingsTile(
                      icon: Icons.share_outlined,
                      label: 'Share App',
                      cs: cs,
                      onTap: () {},
                    ),
                    _divider(cs),
                    _SettingsTile(
                      icon: Icons.privacy_tip_outlined,
                      label: 'Privacy Policy',
                      cs: cs,
                      onTap: () => Navigator.pushNamed(context, '/privacy'),
                    ),
                    _divider(cs),
                    _SettingsTile(
                      icon: Icons.description_outlined,
                      label: 'Terms of Service',
                      cs: cs,
                      onTap: () => Navigator.pushNamed(context, '/terms'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Version + Branding ──
              Center(
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(ImageAssets.adNetworkLogo, width: 44, height: 44, fit: BoxFit.cover),
                    ),
                    const SizedBox(height: 10),
                    Text('Ad Network', style: getSemiBoldStyle(fontSize: 15, color: cs.onSurface.withValues(alpha: .6))),
                    const SizedBox(height: 3),
                    Text('Version 1.0.0', style: getRegularStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .35))),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Logout ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Material(
                  color: cs.error.withValues(alpha: isDark ? .1 : .06),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () async {
                      await TokenStorage.instance.setManualLogout(true);
                      await TokenStorage.instance.clearAll();
                      if (context.mounted) {
                        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.logout_rounded, size: 20, color: cs.error),
                          const SizedBox(width: 10),
                          Text('Log Out', style: getMediumStyle(fontSize: 14, color: cs.error)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  void _showMaxLikeBackLimitSheet(BuildContext context, int currentLimit) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textController = TextEditingController(
      text: currentLimit > 0 ? currentLimit.toString() : '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        bool isSaving = false;
        String? errorMessage;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final viewInsets = MediaQuery.of(ctx).viewInsets;

            Future<void> saveLimit() async {
              final text = textController.text.trim();
              final value = int.tryParse(text);

              if (value == null || value < 1) {
                setSheetState(() {
                  errorMessage = 'Must be a positive integer >= 1';
                });
                return;
              }

              setSheetState(() {
                isSaving = true;
                errorMessage = null;
              });

              try {
                final userRepo = RepositoryProvider.of<UserRepository>(context);
                final response = await userRepo.updateMaxLikeBackLimit(value);

                if (response.isSuccess) {
                  if (context.mounted) {
                    context.read<ProfileBloc>().add(const LoadProfileStats());
                    Navigator.pop(sheetContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                response.message ?? 'Max like back limit updated successfully',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                        backgroundColor: Colors.green.shade700,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    );
                  }
                } else {
                  setSheetState(() {
                    isSaving = false;
                    errorMessage = response.message ?? 'Failed to update limit';
                  });
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                response.message ?? 'Failed to update limit',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                        backgroundColor: cs.error,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    );
                  }
                }
              } catch (e) {
                setSheetState(() {
                  isSaving = false;
                  errorMessage = e.toString();
                });
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              e.toString(),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      backgroundColor: cs.error,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                }
              }
            }

            final presets = [100, 250, 500, 1000, 2000];

            return Container(
              decoration: BoxDecoration(
                color: isDark ? cs.surface : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .2),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.only(bottom: viewInsets.bottom),
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: cs.onSurface.withValues(alpha: .2),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.speed_rounded, color: cs.primary, size: 24),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Max Like Back Limit',
                                    style: getBoldStyle(fontSize: 18, color: cs.onSurface),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Daily limit for automatic like-backs',
                                    style: getRegularStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .5)),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.close_rounded, color: cs.onSurface.withValues(alpha: .5)),
                              onPressed: () => Navigator.pop(sheetContext),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Set Limit (Positive integer >= 1)',
                          style: getSemiBoldStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: .7)),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: textController,
                          keyboardType: TextInputType.number,
                          autofocus: true,
                          enabled: !isSaving,
                          style: getSemiBoldStyle(fontSize: 18, color: cs.onSurface),
                          decoration: InputDecoration(
                            hintText: 'Enter limit (e.g. 500)',
                            hintStyle: getRegularStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: .3)),
                            filled: true,
                            fillColor: isDark ? cs.onSurface.withValues(alpha: .06) : cs.primaryContainer,
                            prefixIcon: Icon(Icons.thumb_up_alt_rounded, color: cs.primary, size: 20),
                            suffixIcon: textController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, size: 18),
                                    onPressed: () {
                                      textController.clear();
                                      setSheetState(() {});
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: cs.primary.withValues(alpha: .2)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: cs.primary.withValues(alpha: .15)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: cs.primary, width: 2),
                            ),
                          ),
                          onChanged: (_) => setSheetState(() {
                            errorMessage = null;
                          }),
                        ),
                        if (errorMessage != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.error_outline_rounded, size: 14, color: cs.error),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  errorMessage!,
                                  style: getRegularStyle(fontSize: 12, color: cs.error),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 14),
                        Text(
                          'Quick presets',
                          style: getMediumStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .4)),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: presets.map((preset) {
                            final isSelected = textController.text == preset.toString();
                            return ActionChip(
                              label: Text(
                                '$preset',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  color: isSelected ? cs.primary : cs.onSurface.withValues(alpha: .7),
                                ),
                              ),
                              backgroundColor: isSelected
                                  ? cs.primary.withValues(alpha: .15)
                                  : (isDark ? cs.onSurface.withValues(alpha: .06) : cs.surfaceContainerHighest),
                              side: BorderSide(
                                color: isSelected ? cs.primary : Colors.transparent,
                              ),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              onPressed: isSaving
                                  ? null
                                  : () {
                                      textController.text = preset.toString();
                                      setSheetState(() {
                                        errorMessage = null;
                                      });
                                    },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 22),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: isSaving ? null : () => Navigator.pop(sheetContext),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  side: BorderSide(color: cs.onSurface.withValues(alpha: .2)),
                                ),
                                child: Text(
                                  'Cancel',
                                  style: getMediumStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: .7)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: isSaving ? null : saveLimit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: cs.primary,
                                  foregroundColor: cs.onPrimary,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 0,
                                ),
                                child: isSaving
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        'Save Limit',
                                        style: getBoldStyle(fontSize: 14, color: cs.onPrimary),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _divider(ColorScheme cs) => Divider(height: 1, color: cs.onSurface.withValues(alpha: .06));
}

// ── Section title ──
class _SectionTitle extends StatelessWidget {
  final String title;
  final ColorScheme cs;
  const _SectionTitle({required this.title, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(title, style: getSemiBoldStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: .45))),
    );
  }
}

// ── Card wrapper ──
class _SectionCard extends StatelessWidget {
  final bool isDark;
  final ColorScheme cs;
  final Widget child;
  const _SectionCard({required this.isDark, required this.cs, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? cs.onSurface.withValues(alpha: .04) : cs.primaryContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withValues(alpha: isDark ? .08 : .04)),
      ),
      child: child,
    );
  }
}

// ── Value settings tile ──
class _SettingsValueTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final String value;
  final ColorScheme cs;
  final VoidCallback onTap;

  const _SettingsValueTile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.value,
    required this.cs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: cs.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: getMediumStyle(fontSize: 14, color: cs.onSurface)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: getRegularStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: .45)),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.primary.withValues(alpha: .2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    style: getBoldStyle(fontSize: 13, color: cs.primary),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.edit_rounded, size: 13, color: cs.primary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Theme option ──
class _ThemeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final ColorScheme cs;
  final bool isDark;
  final VoidCallback onTap;
  const _ThemeOption({required this.icon, required this.label, required this.isSelected, required this.cs, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? cs.primary.withValues(alpha: .12) : cs.onSurface.withValues(alpha: .04),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: isSelected ? cs.primary : cs.onSurface.withValues(alpha: .5)),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: getMediumStyle(fontSize: 14, color: cs.onSurface))),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? cs.primary : Colors.transparent,
                border: Border.all(color: isSelected ? cs.primary : cs.onSurface.withValues(alpha: .25), width: 2),
              ),
              child: isSelected
                  ? Icon(Icons.check_rounded, size: 14, color: cs.onPrimary)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Generic settings tile ──
class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final ColorScheme cs;
  final VoidCallback onTap;
  const _SettingsTile({required this.icon, required this.label, required this.cs, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: .04),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: cs.onSurface.withValues(alpha: .55)),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: getMediumStyle(fontSize: 14, color: cs.onSurface))),
            Icon(Icons.chevron_right_rounded, size: 22, color: cs.onSurface.withValues(alpha: .3)),
          ],
        ),
      ),
    );
  }
}
