import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main.dart' show toggleTheme;
import 'tasks_page.dart';

class SubjectsPage extends StatefulWidget {
  const SubjectsPage({super.key});

  @override
  State<SubjectsPage> createState() => _SubjectsPageState();
}

class _SubjectsPageState extends State<SubjectsPage> {
  final SupabaseClient client = Supabase.instance.client;
  final TextEditingController subjectController = TextEditingController();
  List<Map<String, dynamic>> subjects = [];
  bool editMode = false;
  Color selectedColor = Colors.indigo;

  final List<Map<String, dynamic>> colorOptions = [
    {'name': 'Indigo', 'color': Colors.indigo},
    {'name': 'Rot', 'color': Colors.red},
    {'name': 'Grün', 'color': Colors.green},
    {'name': 'Orange', 'color': Colors.orange},
    {'name': 'Lila', 'color': Colors.purple},
    {'name': 'Teal', 'color': Colors.teal},
    {'name': 'Braun', 'color': Colors.brown},
  ];

  @override
  void initState() {
    super.initState();
    loadSubjects();
  }

  String colorToHex(Color c) {
    final r = (c.r * 255.0).round().clamp(0, 255);
    final g = (c.g * 255.0).round().clamp(0, 255);
    final b = (c.b * 255.0).round().clamp(0, 255);

    return '#${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}';
  }

  Color hexToColor(String? hex) {
    if (hex == null) return Colors.indigo;
    final cleaned = hex.replaceAll('#', '');
    if (cleaned.length == 6) {
      return Color(int.parse('ff$cleaned', radix: 16));
    }
    try {
      return Color(int.parse(cleaned, radix: 16));
    } catch (_) {
      return Colors.indigo;
    }
  }

  Future<void> loadSubjects() async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final response = await client
          .from('subjects')
          .select()
          .eq('user_id', userId)
          .order('created_at');

      if (!mounted) return;
      setState(() {
        subjects = List<Map<String, dynamic>>.from(response as List);
      });
    } catch (e) {
      debugPrint('Error loading subjects: $e');
    }
  }

  Future<void> addSubject() async {
    final newSubject = subjectController.text.trim();
    final userId = client.auth.currentUser?.id;
    if (newSubject.isEmpty || userId == null) return;

    try {
      await client.from('subjects').insert({
        'name': newSubject,
        'user_id': userId,
        'color': colorToHex(selectedColor),
      }).select();

      if (!mounted) return;
      subjectController.clear();
      setState(() {
        selectedColor = colorOptions.first['color'] as Color;
        editMode = false;
      });
      await loadSubjects();
    } catch (e) {
      debugPrint('Error adding subject: $e');
      if (!mounted) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fehler beim Hinzufügen des Fachs')),
        );
      }
    }
  }

  Future<void> deleteSubject(String id) async {
    try {
      await client.from('subjects').delete().eq('id', id);
      if (!mounted) return;
      await loadSubjects();
    } catch (e) {
      debugPrint('Error deleting subject: $e');
      if (!mounted) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fehler beim Löschen des Fachs')),
        );
      }
    }
  }

  Future<void> editSubjectDialog(Map<String, dynamic> subject) async {
    final TextEditingController editController =
        TextEditingController(text: subject['name']?.toString() ?? '');
    Color editColor = hexToColor(subject['color']?.toString());

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Fach bearbeiten'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: editController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: colorOptions.map((opt) {
                    final c = opt['color'] as Color;
                    final name = opt['name'] as String;
                    final selected = colorToHex(editColor) == colorToHex(c);
                    return ChoiceChip(
                      label: Text(name),
                      selectedColor: c,
                      backgroundColor: c.withAlpha((0.15 * 255).round()),
                      avatar: CircleAvatar(backgroundColor: c, radius: 10),
                      selected: selected,
                      onSelected: (_) {
                        setDialogState(() {
                          editColor = c;
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(); // Abbrechen
                },
                child: const Text('Abbrechen'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final newName = editController.text.trim();
                  if (newName.isEmpty) return;
                  try {
                    await client
                        .from('subjects')
                        .update({
                          'name': newName,
                          'color': colorToHex(editColor),
                        })
                        .eq('id', subject['id'])
                        .select();
                    if (!mounted) return;
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                    await loadSubjects();
                  } catch (e) {
                    debugPrint('Error updating subject: $e');
                    if (!mounted) return;
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('Fehler beim Aktualisieren')),
                      );
                    }
                  }
                },
                child: const Text('Speichern'),
              ),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fächer'),
        actions: [
          IconButton(
            icon: Icon(editMode ? Icons.close : Icons.edit),
            onPressed: () {
              setState(() {
                editMode = !editMode;
              });
            },
            tooltip: 'Bearbeiten',
          ),
          IconButton(
            icon: const Icon(Icons.brightness_6),
            onPressed: () => toggleTheme(),
            tooltip: 'Theme wechseln',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => loadSubjects(),
            tooltip: 'Neu laden',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (editMode)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: subjectController,
                      decoration: const InputDecoration(
                        labelText: 'Neues Fach',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<Map<String, dynamic>>(
                    tooltip: 'Farbe wählen',
                    initialValue: colorOptions.first,
                    itemBuilder: (_) {
                      return colorOptions.map((opt) {
                        return PopupMenuItem<Map<String, dynamic>>(
                          value: opt,
                          child: Row(
                            children: [
                              CircleAvatar(
                                  backgroundColor: opt['color'] as Color,
                                  radius: 10),
                              const SizedBox(width: 8),
                              Text(opt['name'] as String),
                            ],
                          ),
                        );
                      }).toList();
                    },
                    onSelected: (opt) {
                      setState(() {
                        selectedColor = opt['color'] as Color;
                      });
                    },
                    child: CircleAvatar(backgroundColor: selectedColor),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: addSubject,
                    child: const Text('Hinzufügen'),
                  ),
                ],
              ),
            if (editMode) const SizedBox(height: 20),
            Expanded(
              child: subjects.isEmpty
                  ? const Center(child: Text('Keine Fächer'))
                  : ListView.builder(
                      itemCount: subjects.length,
                      itemBuilder: (context, index) {
                        final subject = subjects[index];
                        final name = subject['name']?.toString() ?? '';
                        final id = subject['id']?.toString();
                        final color = hexToColor(subject['color']?.toString());

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(backgroundColor: color),
                            title: Text(name),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_forward),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => TasksPage(
                                          subject: {
                                            'id': id,
                                            'name': name,
                                            'color': subject['color']
                                          },
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                if (editMode && id != null) ...[
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.blue),
                                    onPressed: () => editSubjectDialog(subject),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => deleteSubject(id),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
