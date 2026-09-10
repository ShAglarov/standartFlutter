import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../base_card.dart';

class IncidentDescriptionCard extends StatelessWidget {
  final String? description;

  const IncidentDescriptionCard({super.key, this.description});

  @override
  Widget build(BuildContext context) {
    final text = description != null && description!.isNotEmpty ? description! : null;

    return BaseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 20,
                color: Colors.purple,
              ),
              const SizedBox(width: 8),
              Text(
                'ОПИСАНИЕ',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              if (text != null) ...[ 
                const Spacer(),
                Icon(Icons.copy, size: 14, color: Theme.of(context).colorScheme.onSurface.withAlpha(80)),
              ],
            ],
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onLongPress: text != null
                ? () {
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Описание скопировано'),
                        duration: Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                : null,
            child: Text(
              text ?? 'Нет описания',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
