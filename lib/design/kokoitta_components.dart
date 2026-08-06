import 'package:flutter/material.dart';

import 'kokoitta_design_system.dart';

enum KokoittaActionEmphasis { primary, secondary, destructive }

/// A semantic action wrapper that preserves Flutter's native button behavior.
class KokoittaActionButton extends StatelessWidget {
  const KokoittaActionButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.emphasis = KokoittaActionEmphasis.primary,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final KokoittaActionEmphasis emphasis;

  Widget _content() {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: KokoittaSpacing.xs,
      runSpacing: KokoittaSpacing.xxs,
      children: <Widget>[
        if (icon != null)
          ExcludeSemantics(child: Icon(icon, size: KokoittaSize.icon)),
        Text(label, textAlign: TextAlign.center),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return switch (emphasis) {
      KokoittaActionEmphasis.primary => FilledButton(
        onPressed: onPressed,
        child: _content(),
      ),
      KokoittaActionEmphasis.secondary => OutlinedButton(
        onPressed: onPressed,
        child: _content(),
      ),
      KokoittaActionEmphasis.destructive => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
          side: BorderSide(color: Theme.of(context).colorScheme.error),
        ),
        child: _content(),
      ),
    };
  }
}

/// A responsive section title with an optional secondary trailing action.
class KokoittaSectionHeader extends StatelessWidget {
  const KokoittaSectionHeader({
    required this.title,
    super.key,
    this.supportingText,
    this.trailing,
  });

  final String title;
  final String? supportingText;
  final Widget? trailing;

  Widget _copy(BuildContext context) {
    return Semantics(
      header: true,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          if (supportingText != null) ...<Widget>[
            const SizedBox(height: KokoittaSpacing.xs),
            Text(
              supportingText!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
        final stack = largeText || constraints.maxWidth < 520;
        if (trailing == null) return _copy(context);
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _copy(context),
              const SizedBox(height: KokoittaSpacing.sm),
              Align(alignment: Alignment.centerLeft, child: trailing),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: _copy(context)),
            const SizedBox(width: KokoittaSpacing.md),
            trailing!,
          ],
        );
      },
    );
  }
}

enum KokoittaStateTone { neutral, progress, success, warning, error, quota }

class KokoittaStatePanel extends StatelessWidget {
  const KokoittaStatePanel({
    required this.tone,
    required this.title,
    super.key,
    this.message,
    this.leading,
    this.primaryAction,
    this.secondaryAction,
    this.liveRegion = false,
    this.busy = false,
    this.progress,
  }) : assert(progress == null || (progress >= 0 && progress <= 1));

  final KokoittaStateTone tone;
  final String title;
  final String? message;
  final Widget? leading;
  final Widget? primaryAction;
  final Widget? secondaryAction;
  final bool liveRegion;
  final bool busy;
  final double? progress;

  ({Color background, Color foreground, IconData icon}) _appearance(
    BuildContext context,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.kokoittaColors;
    return switch (tone) {
      KokoittaStateTone.neutral => (
        background: scheme.surfaceContainerHighest,
        foreground: scheme.onSurface,
        icon: Icons.info_outline,
      ),
      KokoittaStateTone.progress => (
        background: scheme.primaryContainer,
        foreground: scheme.onPrimaryContainer,
        icon: Icons.sync,
      ),
      KokoittaStateTone.success => (
        background: semantic.successContainer,
        foreground: semantic.onSuccessContainer,
        icon: Icons.check_circle_outline,
      ),
      KokoittaStateTone.warning => (
        background: semantic.warningContainer,
        foreground: semantic.onWarningContainer,
        icon: Icons.warning_amber_rounded,
      ),
      KokoittaStateTone.error => (
        background: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
        icon: Icons.error_outline,
      ),
      KokoittaStateTone.quota => (
        background: scheme.secondaryContainer,
        foreground: scheme.onSecondaryContainer,
        icon: Icons.photo_library_outlined,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final appearance = _appearance(context);
    final actions = <Widget>[?primaryAction, ?secondaryAction];
    return Semantics(
      container: true,
      explicitChildNodes: true,
      liveRegion: liveRegion,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: appearance.background,
          borderRadius: BorderRadius.circular(KokoittaRadius.medium),
          border: Border.all(
            color: appearance.foreground.withValues(alpha: 0.22),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(KokoittaSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  IconTheme(
                    data: IconThemeData(
                      color: appearance.foreground,
                      size: KokoittaSize.icon,
                    ),
                    child: ExcludeSemantics(
                      child: leading ?? Icon(appearance.icon),
                    ),
                  ),
                  const SizedBox(width: KokoittaSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: appearance.foreground),
                        ),
                        if (message != null) ...<Widget>[
                          const SizedBox(height: KokoittaSpacing.xs),
                          Text(
                            message!,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: appearance.foreground),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (busy || progress != null) ...<Widget>[
                const SizedBox(height: KokoittaSpacing.md),
                LinearProgressIndicator(
                  value: progress,
                  semanticsLabel: title,
                  semanticsValue: progress == null
                      ? '処理中'
                      : '${(progress! * 100).round()}%',
                ),
              ],
              if (actions.isNotEmpty) ...<Widget>[
                const SizedBox(height: KokoittaSpacing.md),
                Wrap(
                  spacing: KokoittaSpacing.sm,
                  runSpacing: KokoittaSpacing.sm,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum KokoittaPhotoPlaceholderState { empty, missing, decodeFailed, loading }

class KokoittaPhotoPlaceholder extends StatelessWidget {
  const KokoittaPhotoPlaceholder({
    required this.state,
    super.key,
    this.aspect = KokoittaImageAspect.standard,
  });

  final KokoittaPhotoPlaceholderState state;
  final KokoittaImageAspect aspect;

  ({String label, IconData icon}) get _content => switch (state) {
    KokoittaPhotoPlaceholderState.empty => (
      label: '写真はまだありません',
      icon: Icons.add_photo_alternate_outlined,
    ),
    KokoittaPhotoPlaceholderState.missing => (
      label: '写真を表示できません',
      icon: Icons.broken_image_outlined,
    ),
    KokoittaPhotoPlaceholderState.decodeFailed => (
      label: '写真を表示できません',
      icon: Icons.hide_image_outlined,
    ),
    KokoittaPhotoPlaceholderState.loading => (
      label: '写真を読み込んでいます',
      icon: Icons.image_outlined,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final content = _content;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      image: true,
      label: content.label,
      child: ExcludeSemantics(
        child: AspectRatio(
          aspectRatio: aspect.ratio,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(KokoittaRadius.medium),
            ),
            child: Padding(
              padding: const EdgeInsets.all(KokoittaSpacing.md),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (state == KokoittaPhotoPlaceholderState.loading)
                      const SizedBox.square(
                        dimension: KokoittaSize.iconLarge,
                        child: CircularProgressIndicator(),
                      )
                    else
                      Icon(
                        content.icon,
                        size: KokoittaSize.iconLarge,
                        color: scheme.onSurfaceVariant,
                      ),
                    const SizedBox(height: KokoittaSpacing.xs),
                    Text(
                      content.label,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Presentation-only trip card. Domain formatting remains in the caller.
class KokoittaTripSummaryCard extends StatelessWidget {
  const KokoittaTripSummaryCard({
    required this.title,
    required this.semanticLabel,
    required this.onTap,
    super.key,
    this.image,
    this.metadata = const <Widget>[],
    this.badge,
    this.overflow,
  });

  final String title;
  final String semanticLabel;
  final VoidCallback? onTap;
  final Widget? image;
  final List<Widget> metadata;
  final Widget? badge;
  final Widget? overflow;

  @override
  Widget build(BuildContext context) {
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(KokoittaRadius.large),
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      button: onTap != null,
      enabled: onTap != null,
      label: semanticLabel,
      onTap: onTap,
      child: Card(
        shape: cardShape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          excludeFromSemantics: true,
          customBorder: cardShape,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ExcludeSemantics(
                child:
                    image ??
                    const KokoittaPhotoPlaceholder(
                      state: KokoittaPhotoPlaceholderState.empty,
                      aspect: KokoittaImageAspect.wide,
                    ),
              ),
              Padding(
                padding: const EdgeInsets.all(KokoittaSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: ExcludeSemantics(
                            child: Text(
                              title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ),
                        if (overflow != null) ...<Widget>[
                          const SizedBox(width: KokoittaSpacing.xs),
                          overflow!,
                        ],
                      ],
                    ),
                    if (badge != null) ...<Widget>[
                      const SizedBox(height: KokoittaSpacing.xs),
                      ExcludeSemantics(child: badge!),
                    ],
                    for (final item in metadata) ...<Widget>[
                      const SizedBox(height: KokoittaSpacing.xs),
                      ExcludeSemantics(child: item),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An icon-only action that retains the native [IconButton] semantics action.
class KokoittaSemanticIconButton extends StatelessWidget {
  const KokoittaSemanticIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: KokoittaSize.minimumTapTarget,
      child: IconButton(tooltip: label, onPressed: onPressed, icon: Icon(icon)),
    );
  }
}
