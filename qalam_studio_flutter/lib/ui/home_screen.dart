import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/design_project.dart';

const _amber = Color(0xFFF59E0B);
const _inkOnAmber = Color(0xFF1C1917);

class _HomeTemplate {
  const _HomeTemplate({
    required this.id,
    required this.name,
    required this.size,
    required this.base,
    required this.accent,
  });

  final String id;
  final String name;
  final String size;
  final Color base;
  final Color accent;
}

const _homeTemplates = <_HomeTemplate>[
  _HomeTemplate(
    id: 'eid-post',
    name: 'Eid Post',
    size: '9:16 · Story',
    base: Color(0xFFB45309),
    accent: Color(0xFFF59E0B),
  ),
  _HomeTemplate(
    id: 'shaadi-card',
    name: 'Shaadi Card',
    size: 'A4 · Print',
    base: Color(0xFF7C2D12),
    accent: Color(0xFFEA580C),
  ),
  _HomeTemplate(
    id: 'sale-poster',
    name: 'Sale Poster',
    size: '1:1 · Post',
    base: Color(0xFF065F46),
    accent: Color(0xFF10B981),
  ),
  _HomeTemplate(
    id: 'birthday-card',
    name: 'Birthday Card',
    size: '9:16 · Story',
    base: Color(0xFF9D174D),
    accent: Color(0xFFF472B6),
  ),
  _HomeTemplate(
    id: 'urdu-quote',
    name: 'Urdu Quote',
    size: '1:1 · Post',
    base: Color(0xFF1E3A5F),
    accent: Color(0xFF38BDF8),
  ),
  _HomeTemplate(
    id: 'business-card',
    name: 'Business Card',
    size: '3.5 × 2 in · Print',
    base: Color(0xFF44403C),
    accent: Color(0xFFF59E0B),
  ),
];

String _relativeDate(int ms) {
  if (ms <= 0) return 'Recently';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  if (day == today) return 'Today';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${dt.day} ${months[dt.month - 1]}';
}

/// Grade 1 home screen: create hero, AI tools, templates, recent projects
/// and a Docs Tools entry. Pure UI — every action is a callback.
class QalamixHomeScreen extends StatelessWidget {
  const QalamixHomeScreen({
    super.key,
    required this.projects,
    required this.thumbnailFor,
    required this.onCreate,
    required this.onRemoveBackground,
    required this.onEnhance,
    required this.onOpenTemplates,
    required this.onUseTemplate,
    required this.onOpenProject,
    required this.onSeeAllProjects,
    required this.onOpenDocsTools,
  });

  final List<DesignProject> projects;
  final Uint8List? Function(DesignProject) thumbnailFor;
  final VoidCallback onCreate;
  final VoidCallback onRemoveBackground;
  final VoidCallback onEnhance;
  final VoidCallback onOpenTemplates;
  final ValueChanged<String> onUseTemplate; // template id
  final ValueChanged<DesignProject> onOpenProject;
  final VoidCallback onSeeAllProjects;
  final VoidCallback onOpenDocsTools;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final recent = projects.take(4).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeroCard(context),
          const SizedBox(height: 24),
          _buildSectionHeader(context, 'AI tools'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _AiToolCard(
                  icon: Icons.content_cut,
                  title: 'Remove Background',
                  subtitle: 'Erase the background in one tap',
                  onTap: onRemoveBackground,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AiToolCard(
                  icon: Icons.auto_awesome,
                  title: 'Enhance',
                  subtitle: 'Sharpen and brighten your photo',
                  onTap: onEnhance,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSectionHeader(
            context,
            'Templates',
            onSeeAll: onOpenTemplates,
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.2,
            ),
            itemCount: _homeTemplates.length,
            itemBuilder: (context, index) {
              final template = _homeTemplates[index];
              return _TemplateCard(
                template: template,
                onTap: () => onUseTemplate(template.id),
              );
            },
          ),
          const SizedBox(height: 24),
          _buildSectionHeader(
            context,
            'Recent Projects',
            onSeeAll: onSeeAllProjects,
          ),
          const SizedBox(height: 8),
          if (recent.isEmpty)
            _buildEmptyProjectsCard(context)
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.85,
              ),
              itemCount: recent.length,
              itemBuilder: (context, index) {
                final project = recent[index];
                return _ProjectCard(
                  project: project,
                  thumbnail: thumbnailFor(project),
                  onTap: () => onOpenProject(project),
                );
              },
            ),
          const SizedBox(height: 24),
          Material(
            color: colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: colorScheme.outline),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onOpenDocsTools,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Docs Tools',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Fill, Sign & Seal, Scanner',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildHeroCard(BuildContext context) {
    return Material(
      color: _amber,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onCreate,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Create a design',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: _inkOnAmber,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Photo, poster or document — start from scratch',
                      style: TextStyle(fontSize: 14, color: _inkOnAmber),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _inkOnAmber.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add_rounded,
                  size: 40,
                  color: _inkOnAmber,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title, {
    VoidCallback? onSeeAll,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
        ),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'See all',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _amber,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyProjectsCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Column(
        children: [
          Icon(
            Icons.image_outlined,
            size: 40,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text(
            'Your first design will appear here',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onCreate,
            style: FilledButton.styleFrom(
              backgroundColor: _amber,
              foregroundColor: _inkOnAmber,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Create your first design',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiToolCard extends StatelessWidget {
  const _AiToolCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colorScheme.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _amber.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 24, color: colorScheme.secondary),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.onTap});

  final _HomeTemplate template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: template.base),
            Positioned(
              right: -24,
              top: -24,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: template.accent.withOpacity(0.45),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  template.size,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Text(
                template.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.thumbnail,
    required this.onTap,
  });

  final DesignProject project;
  final Uint8List? thumbnail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bytes = thumbnail;
    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colorScheme.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: bytes != null
                  ? Image.memory(
                      bytes,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: double.infinity,
                      color: colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.image_outlined,
                        size: 32,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _relativeDate(project.updatedAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
