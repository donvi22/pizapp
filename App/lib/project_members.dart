import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/project.dart';
import 'services/api_client.dart';

class ProjectMembersPage extends StatefulWidget {
  const ProjectMembersPage({super.key, required this.api, required this.project});
  final ApiClient api;
  final Project project;

  @override
  State<ProjectMembersPage> createState() => _ProjectMembersPageState();
}

class _ProjectMembersPageState extends State<ProjectMembersPage> {
  late Future<List<ProjectSlot>> _slots;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() => setState(() {
    _slots = widget.api.getProjectSlots(widget.project.id!);
  });

  Future<void> _addSlot() async {
    var enteredName = '';
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Preparar una plaza'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre del integrante'),
          onChanged: (value) => enteredName = value,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, enteredName.trim()),
            child: const Text('Añadir'),
          ),
        ],
      ),
    );
    if (!mounted || name == null || name.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.api.createProjectSlot(widget.project.id!, name);
      if (mounted) _refresh();
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(ProjectSlot slot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Retirar plaza'),
        content: Text(slot.username == null
            ? '¿Quitar la plaza de ${slot.displayName}?'
            : '¿Quitar a ${slot.displayName} del proyecto? Perderá el acceso.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Retirar')),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _busy = true);
    try {
      await widget.api.removeProjectSlot(widget.project.id!, slot.id);
      if (mounted) _refresh();
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(Object error) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
  );

  Future<void> _copyInvitation() async {
    final code = widget.project.inviteCode;
    if (code == null) return;
    final link = Uri.base.replace(queryParameters: {'invite': code}).toString();
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enlace copiado. Compártelo con los integrantes.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Equipo')),
    floatingActionButton: widget.project.isOwner
        ? FloatingActionButton.extended(
            onPressed: _busy ? null : _addSlot,
            icon: const Icon(Icons.person_add), label: const Text('Añadir nombre'),
          )
        : null,
    body: FutureBuilder<List<ProjectSlot>>(
      future: _slots,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          if (snapshot.hasError) return Center(child: Text('No se pudo cargar el equipo: ${snapshot.error}'));
          return const Center(child: CircularProgressIndicator());
        }
        final slots = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            ListTile(
              leading: const Icon(Icons.star_outline),
              title: Text(widget.project.ownerName),
              subtitle: const Text('Creador'),
            ),
            for (final slot in slots)
              ListTile(
                leading: Icon(slot.username == null ? Icons.person_outline : Icons.person),
                title: Text(slot.displayName),
                subtitle: Text(slot.username == null ? 'Plaza libre' : '@${slot.username}'),
                trailing: widget.project.isOwner
                    ? IconButton(
                        tooltip: 'Retirar plaza',
                        onPressed: _busy ? null : () => _remove(slot),
                        icon: const Icon(Icons.remove_circle_outline),
                      )
                    : null,
              ),
            if (widget.project.isOwner) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _copyInvitation,
                icon: const Icon(Icons.link),
                label: const Text('Copiar enlace de invitación'),
              ),
              const SizedBox(height: 8),
              const Text('Primero prepara los nombres. Cada persona elegirá su plaza al abrir el enlace e iniciar sesión.'),
            ],
          ],
        );
      },
    ),
  );
}

class JoinProjectPage extends StatefulWidget {
  const JoinProjectPage({super.key, required this.api, required this.code, required this.onDone, required this.onLogout});
  final ApiClient api;
  final String code;
  final VoidCallback onDone;
  final Future<void> Function() onLogout;

  @override
  State<JoinProjectPage> createState() => _JoinProjectPageState();
}

class _JoinProjectPageState extends State<JoinProjectPage> {
  late Future<ProjectInvitation> _invitation;
  int? _selectedSlot;
  bool _joining = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _invitation = widget.api.getInvitation(widget.code);
  }

  Future<void> _join() async {
    final slot = _selectedSlot;
    if (slot == null) return;
    setState(() { _joining = true; _error = null; });
    try {
      await widget.api.joinProject(widget.code, slot);
      if (mounted) widget.onDone();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Unirse a un proyecto'),
      actions: [
        IconButton(
          tooltip: 'Cerrar sesión y cambiar de cuenta',
          onPressed: () async {
            try { await widget.onLogout(); }
            catch (error) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(error.toString())),
                );
              }
            }
          },
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: FutureBuilder<ProjectInvitation>(
      future: _invitation,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          if (snapshot.hasError) {
            return Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [const Text('El enlace no está disponible.'),
                TextButton(onPressed: widget.onDone, child: const Text('Mis proyectos'))],
            ));
          }
          return const Center(child: CircularProgressIndicator());
        }
        final invitation = snapshot.data!;
        return Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(invitation.projectName, style: Theme.of(context).textTheme.headlineSmall),
              Text('Invitación de ${invitation.ownerName}'),
              const SizedBox(height: 20),
              const Text('Selecciona el nombre que te corresponde:'),
              for (final slot in invitation.slots)
                ListTile(
                  leading: Icon(_selectedSlot == slot.id ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                  title: Text(slot.displayName),
                  selected: _selectedSlot == slot.id,
                  onTap: _joining ? null : () => setState(() => _selectedSlot = slot.id),
                ),
              if (invitation.slots.isEmpty) const Text('No quedan plazas libres. Pide al creador que añada una.'),
              if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
              FilledButton(onPressed: _selectedSlot == null || _joining ? null : _join, child: const Text('Unirme')),
              TextButton(onPressed: widget.onDone, child: const Text('Ir a mis proyectos')),
            ],
          ),
        ));
      },
    ),
  );
}
