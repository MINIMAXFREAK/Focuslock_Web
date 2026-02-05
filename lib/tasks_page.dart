import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logger/logger.dart';

var logger = Logger();

enum TaskFilter { all, pending, completed, overdue }
enum TaskSort { dueAsc, dueDesc, createdAsc, createdDesc }

class TasksPage extends StatefulWidget {
  // subject is Map with keys id,name,color
  final Map<String, dynamic> subject;
  const TasksPage({super.key, required this.subject});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  final TextEditingController taskController = TextEditingController();
  final SupabaseClient client = Supabase.instance.client;

  List<Map<String, dynamic>> tasks = [];
  bool editMode = false;
  DateTime? selectedDate;

  TaskFilter filter = TaskFilter.all;
  TaskSort sort = TaskSort.dueAsc;

  @override
  void initState() {
    super.initState();
    loadTasks();
  }

  String formatDate(DateTime d) {
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    return '$day.$month.${d.year}';
  }

  Future<void> loadTasks() async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final response = await client
          .from('tasks')
          .select()
          .eq('user_id', userId)
          .eq('subject', widget.subject['name'])
          .order('created_at', ascending: true);

      if (!mounted) return;
      setState(() {
        tasks = List<Map<String, dynamic>>.from(response as List);
      });
    } catch (e) {
      logger.e('Error loading tasks: $e');
    }
  }

  List<Map<String, dynamic>> getFilteredSortedTasks() {
    final now = DateTime.now();
    List<Map<String, dynamic>> list = List.from(tasks);

    list = list.where((task) {
      final done = task['done'] == true;
      DateTime? dueDate;
      try {
        if (task['due_date'] != null) dueDate = DateTime.parse(task['due_date'].toString());
      } catch (_) {
        dueDate = null;
      }

      switch (filter) {
        case TaskFilter.pending:
          return !done;
        case TaskFilter.completed:
          return done;
        case TaskFilter.overdue:
          return (dueDate != null && !done && dueDate.isBefore(now));
        case TaskFilter.all:
          return true;
      }
    }).toList();

    list.sort((a, b) {
      DateTime? da, db;
      try {
        if (a['due_date'] != null) da = DateTime.parse(a['due_date'].toString());
      } catch (_) {
        da = null;
      }
      try {
        if (b['due_date'] != null) db = DateTime.parse(b['due_date'].toString());
      } catch (_) {
        db = null;
      }

      switch (sort) {
        case TaskSort.dueAsc:
          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;
          return da.compareTo(db);
        case TaskSort.dueDesc:
          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;
          return db.compareTo(da);
        case TaskSort.createdAsc:
          return (a['created_at'] ?? '').toString().compareTo((b['created_at'] ?? '').toString());
        case TaskSort.createdDesc:
          return (b['created_at'] ?? '').toString().compareTo((a['created_at'] ?? '').toString());
      }
    });

    return list;
  }

  Future<void> pickDueDate(BuildContext context, {DateTime? initialDate}) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );

    if (date != null) {
      if (!mounted) return;
      setState(() {
        selectedDate = date;
      });
    }
  }

  Future<void> addTask() async {
    final userId = client.auth.currentUser?.id;
    final title = taskController.text.trim();
    if (userId == null || title.isEmpty || selectedDate == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Titel und Fälligkeitsdatum eingeben')),
      );
      return;
    }

    try {
      await client.from('tasks').insert({
        'user_id': userId,
        'subject': widget.subject['name'],
        'title': title,
        'done': false,
        'due_date': selectedDate!.toIso8601String(),
      }).select();

      if (!mounted) return;
      taskController.clear();
      setState(() {
        selectedDate = null;
      });
      await loadTasks();
    } catch (e) {
      logger.e('Error adding task: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Hinzufügen: $e')),
      );
    }
  }

  Future<void> toggleDone(Map<String, dynamic> task) async {
    try {
      await client.from('tasks').update({
        'done': !(task['done'] as bool),
      }).eq('id', task['id']).select();

      if (!mounted) return;
      await loadTasks();
    } catch (e) {
      logger.e('Error updating task: $e');
    }
  }

  Future<void> deleteTask(String id) async {
    try {
      await client.from('tasks').delete().eq('id', id);
      if (!mounted) return;
      await loadTasks();
    } catch (e) {
      logger.e('Error deleting task: $e');
    }
  }

  Future<void> editTaskDialog(Map<String, dynamic> task) async {
    final TextEditingController editController =
        TextEditingController(text: task['title']?.toString() ?? '');
    DateTime? editDate;
    try {
      if (task['due_date'] != null) editDate = DateTime.parse(task['due_date'].toString());
    } catch (_) {
      editDate = null;
    }

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Aufgabe bearbeiten'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: editController,
                  decoration: const InputDecoration(labelText: 'Titel'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(editDate != null ? formatDate(editDate!) : 'Kein Datum'),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: editDate ?? now,
                          firstDate: DateTime(now.year - 1),
                          lastDate: DateTime(now.year + 5),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            editDate = picked;
                          });
                        }
                      },
                      icon: const Icon(Icons.calendar_today),
                      label: const Text('Datum ändern'),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Abbrechen
                },
                child: const Text('Abbrechen'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final newTitle = editController.text.trim();
                  if (newTitle.isEmpty || editDate == null) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Bitte Titel und Datum angeben')),
                    );
                    return;
                  }
                  try {
                    await client.from('tasks').update({
                      'title': newTitle,
                      'due_date': editDate!.toIso8601String(),
                    }).eq('id', task['id']).select();
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                    if (!mounted) return;
                    await loadTasks();
                  } catch (e) {
                    logger.e('Error updating task: $e');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Fehler beim Speichern: $e')),
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

  Future<void> updateDueDate(Map<String, dynamic> task) async {
    DateTime? currentDate;
    try {
      if (task['due_date'] != null) currentDate = DateTime.parse(task['due_date'].toString());
    } catch (_) {
      currentDate = DateTime.now();
    }

    await pickDueDate(context, initialDate: currentDate ?? DateTime.now());
    if (selectedDate == null) return;

    try {
      await client.from('tasks').update({
        'due_date': selectedDate!.toIso8601String(),
      }).eq('id', task['id']).select();

      if (!mounted) return;
      setState(() {
        selectedDate = null;
      });
      await loadTasks();
    } catch (e) {
      logger.e('Error updating due date: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Aktualisieren: $e')),
      );
    }
  }

  Color subjectColor() {
    final hex = widget.subject['color']?.toString();
    if (hex == null) return Colors.indigo;
    final cleaned = hex.replaceAll('#', '');
    try {
      return Color(int.parse('ff$cleaned', radix: 16));
    } catch (_) {
      return Colors.indigo;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = subjectColor();
    final filteredTasks = getFilteredSortedTasks();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subject['name'] ?? ''),
        backgroundColor: color,
        actions: [
          PopupMenuButton<TaskFilter>(
            onSelected: (f) => setState(() => filter = f),
            icon: const Icon(Icons.filter_list),
            itemBuilder: (_) => [
              const PopupMenuItem(value: TaskFilter.all, child: Text('Alle')),
              const PopupMenuItem(value: TaskFilter.pending, child: Text('Ausstehend')),
              const PopupMenuItem(value: TaskFilter.completed, child: Text('Erledigt')),
              const PopupMenuItem(value: TaskFilter.overdue, child: Text('Überfällig')),
            ],
          ),
          PopupMenuButton<TaskSort>(
            onSelected: (s) => setState(() => sort = s),
            icon: const Icon(Icons.sort),
            itemBuilder: (_) => [
              const PopupMenuItem(value: TaskSort.dueAsc, child: Text('Fällig ↑')),
              const PopupMenuItem(value: TaskSort.dueDesc, child: Text('Fällig ↓')),
              const PopupMenuItem(value: TaskSort.createdAsc, child: Text('Erstellt ↑')),
              const PopupMenuItem(value: TaskSort.createdDesc, child: Text('Erstellt ↓')),
            ],
          ),
          IconButton(
            icon: Icon(editMode ? Icons.close : Icons.edit),
            onPressed: () => setState(() => editMode = !editMode),
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
                      controller: taskController,
                      decoration: const InputDecoration(
                        labelText: 'Neue Aufgabe',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => pickDueDate(context),
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      selectedDate != null ? formatDate(selectedDate!) : 'Datum wählen',
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: addTask,
                    child: const Text('Hinzufügen'),
                  ),
                ],
              ),
            if (editMode) const SizedBox(height: 20),
            Expanded(
              child: filteredTasks.isEmpty
                  ? const Center(child: Text('Keine Aufgaben'))
                  : ListView.builder(
                      itemCount: filteredTasks.length,
                      itemBuilder: (context, index) {
                        final task = filteredTasks[index];
                        DateTime? dueDate;
                        try {
                          if (task['due_date'] != null) dueDate = DateTime.parse(task['due_date'].toString());
                        } catch (_) {
                          dueDate = null;
                        }

                        final bool done = task['done'] == true;
                        final bool isOverdue = dueDate != null && !done && dueDate.isBefore(DateTime.now());

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: Checkbox(
                              value: done,
                              onChanged: (_) => toggleDone(task),
                            ),
                            title: Text(
                              task['title']?.toString() ?? '',
                              style: TextStyle(
                                color: isOverdue ? Colors.red : null,
                                decoration: done ? TextDecoration.lineThrough : null,
                              ),
                            ),
                            subtitle: dueDate != null
                                ? Row(
                                    children: [
                                      Text('Fällig: ${formatDate(dueDate)}',
                                          style: TextStyle(color: isOverdue ? Colors.red : null)),
                                      if (editMode)
                                        IconButton(
                                          icon: const Icon(Icons.edit_calendar, size: 20),
                                          onPressed: () => editTaskDialog(task),
                                        ),
                                    ],
                                  )
                                : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (editMode)
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.blue),
                                    onPressed: () => editTaskDialog(task),
                                  ),
                                if (editMode)
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => deleteTask(task['id']),
                                  ),
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
