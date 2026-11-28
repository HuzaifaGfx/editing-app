import 'package:flutter/material.dart';

const _amber = Color(0xFFF59E0B);

/// Docs Tools hub: scanner, fill form, sign & seal, and saved documents.
/// Pure UI — every card is a callback.
class QalamixDocsToolsScreen extends StatelessWidget {
  const QalamixDocsToolsScreen({
    super.key,
    required this.onScanner,
    required this.onFill,
    required this.onSignSeal,
    required this.onDocuments,
  });

  final VoidCallback onScanner;
  final VoidCallback onFill;
  final VoidCallback onSignSeal;
  final VoidCallback onDocuments;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Docs Tools',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Fill forms, sign and scan — all in one place',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.95,
            children: [
              _DocsToolCard(
                icon: Icons.document_scanner_outlined,
                title: 'Scanner',
                description: 'Turn paper into PDF',
                onTap: onScanner,
              ),
              _DocsToolCard(
                icon: Icons.edit_note_rounded,
                title: 'Fill Form',
                description: 'Fill out a form',
                onTap: onFill,
              ),
              _DocsToolCard(
                icon: Icons.draw_outlined,
                title: 'Sign & Seal',
                description: 'Signature and stamp',
                onTap: onSignSeal,
              ),
              _DocsToolCard(
                icon: Icons.description_outlined,
                title: 'My Documents',
                description: 'Scanned and filled files',
                onTap: onDocuments,
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _DocsToolCard extends StatelessWidget {
  const _DocsToolCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                description,
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
