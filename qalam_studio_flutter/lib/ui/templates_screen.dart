import 'package:flutter/material.dart';

const _amber = Color(0xFFF59E0B);

class _Template {
  const _Template({
    required this.id,
    required this.name,
    required this.size,
    required this.category,
    required this.base,
    required this.accent,
  });

  final String id;
  final String name;
  final String size;
  final String category;
  final Color base;
  final Color accent;
}

const _categories = <String>[
  'All',
  'Social',
  'Eid & Ramadan',
  'Shaadi',
  'Business',
  'Quotes',
  'Birthday',
  'CV',
];

const _templates = <_Template>[
  _Template(
    id: 'eid-post',
    name: 'Eid Post',
    size: '9:16 · Story',
    category: 'Eid & Ramadan',
    base: Color(0xFFB45309),
    accent: Color(0xFFF59E0B),
  ),
  _Template(
    id: 'ramadan-kareem',
    name: 'Ramadan Kareem',
    size: '1:1 · Post',
    category: 'Eid & Ramadan',
    base: Color(0xFF065F46),
    accent: Color(0xFF10B981),
  ),
  _Template(
    id: 'shaadi-card',
    name: 'Shaadi Card',
    size: 'A4 · Print',
    category: 'Shaadi',
    base: Color(0xFF7C2D12),
    accent: Color(0xFFEA580C),
  ),
  _Template(
    id: 'mehndi-night',
    name: 'Mehndi Night',
    size: '9:16 · Story',
    category: 'Shaadi',
    base: Color(0xFF9D174D),
    accent: Color(0xFFF472B6),
  ),
  _Template(
    id: 'sale-poster',
    name: 'Sale Poster',
    size: '1:1 · Post',
    category: 'Social',
    base: Color(0xFF1E3A5F),
    accent: Color(0xFF38BDF8),
  ),
  _Template(
    id: 'business-card',
    name: 'Business Card',
    size: '3.5 × 2 in · Print',
    category: 'Business',
    base: Color(0xFF44403C),
    accent: Color(0xFFF59E0B),
  ),
  _Template(
    id: 'urdu-quote',
    name: 'Urdu Quote',
    size: '1:1 · Post',
    category: 'Quotes',
    base: Color(0xFF78350F),
    accent: Color(0xFFFBBF24),
  ),
  _Template(
    id: 'motivational-quote',
    name: 'Motivational Quote',
    size: '9:16 · Story',
    category: 'Social',
    base: Color(0xFF0F766E),
    accent: Color(0xFF2DD4BF),
  ),
  _Template(
    id: 'birthday-card',
    name: 'Birthday Card',
    size: '9:16 · Story',
    category: 'Birthday',
    base: Color(0xFF9D174D),
    accent: Color(0xFFF9A8D4),
  ),
  _Template(
    id: 'birthday-invite',
    name: 'Birthday Invite',
    size: 'A4 · Print',
    category: 'Birthday',
    base: Color(0xFF92400E),
    accent: Color(0xFFF59E0B),
  ),
  _Template(
    id: 'cv-modern',
    name: 'Modern CV',
    size: 'A4 · Print',
    category: 'CV',
    base: Color(0xFF1E3A5F),
    accent: Color(0xFF60A5FA),
  ),
  _Template(
    id: 'cv-simple',
    name: 'Simple CV',
    size: 'A4 · Print',
    category: 'CV',
    base: Color(0xFF44403C),
    accent: Color(0xFFA8A29E),
  ),
];

/// Templates browser: search + category chips filter a grid of 12
/// placeholder templates. Pure UI — tapping a card calls [onUseTemplate]
/// with the template id.
class QalamixTemplatesScreen extends StatefulWidget {
  const QalamixTemplatesScreen({super.key, required this.onUseTemplate});

  final ValueChanged<String> onUseTemplate;

  @override
  State<QalamixTemplatesScreen> createState() =>
      _QalamixTemplatesScreenState();
}

class _QalamixTemplatesScreenState extends State<QalamixTemplatesScreen> {
  String _selectedCategory = 'All';
  String _query = '';

  List<_Template> get _filtered {
    final query = _query.trim().toLowerCase();
    return _templates.where((template) {
      final matchesCategory = _selectedCategory == 'All' ||
          template.category == _selectedCategory;
      final matchesQuery =
          query.isEmpty || template.name.toLowerCase().contains(query);
      return matchesCategory && matchesQuery;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final filtered = _filtered;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SearchBar(
            hintText: 'Search templates',
            leading: const Icon(Icons.search_rounded),
            elevation: const WidgetStatePropertyAll(0),
            backgroundColor:
                WidgetStatePropertyAll(colorScheme.surface),
            side: WidgetStatePropertyAll(
              BorderSide(color: colorScheme.outline),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final category = _categories[index];
                final selected = category == _selectedCategory;
                return ChoiceChip(
                  label: Text(category),
                  selected: selected,
                  onSelected: (_) =>
                      setState(() => _selectedCategory = category),
                  selectedColor: _amber.withOpacity(0.2),
                  backgroundColor: colorScheme.surface,
                  side: BorderSide(
                    color: selected ? _amber : colorScheme.outline,
                  ),
                  labelStyle: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          if (filtered.isEmpty)
            _buildEmptyState(context)
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 8,
                childAspectRatio: 0.72,
              ),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final template = filtered[index];
                return _TemplateCard(
                  template: template,
                  onTap: () => widget.onUseTemplate(template.id),
                );
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          Icon(
            Icons.search_off_outlined,
            size: 40,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text(
            'No templates in this category yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Try another category',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.onTap});

  final _Template template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: template.base,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
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
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Text(
                      template.name,
                      maxLines: 2,
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
            const SizedBox(height: 8),
            Text(
              template.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outline),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                template.size,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
