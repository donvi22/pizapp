import 'package:flutter/material.dart';

import 'services/api_client.dart';
import 'services/attachment_client.dart';

class TaskAttachments extends StatefulWidget {
  const TaskAttachments({
    super.key,
    required this.api,
    required this.projectId,
    required this.taskId,
  });

  final ApiClient api;
  final int projectId;
  final int taskId;

  @override
  State<TaskAttachments> createState() => _TaskAttachmentsState();
}

class _TaskAttachmentsState extends State<TaskAttachments> {
  late final AttachmentClient _client;

  List<TaskAttachment> _attachments = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _client = AttachmentClient(widget.api);
    _load();
  }

  Future<void> _load() async {
    try {
      final attachments = await _client.list(
        widget.projectId,
        widget.taskId,
      );

      if (!mounted) return;
      setState(() {
        _attachments = attachments;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _upload() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final attachment = await _client.pickAndUpload(
        widget.projectId,
        widget.taskId,
      );

      if (!mounted || attachment == null) return;
      setState(() => _attachments.add(attachment));
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download(TaskAttachment attachment) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      await _client.download(
        widget.projectId,
        widget.taskId,
        attachment,
      );
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error.toString().replaceFirst('Exception: ', '')),
      ),
    );
  }

  String _sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.attach_file),
        title: Text('Archivos adjuntos (${_attachments.length})'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          if (_loading || _busy) const LinearProgressIndicator(),
          if (_error != null)
            TextButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _load();
              },
              child: const Text('No se pudieron cargar. Reintentar'),
            )
          else ...[
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : _upload,
                icon: const Icon(Icons.upload_file),
                label: const Text('Añadir archivo'),
              ),
            ),
            Text('Límite por archivo: ${AttachmentClient.maxUploadMb} MB',
              style: Theme.of(context).textTheme.bodySmall),
            if (_attachments.isEmpty && !_loading)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Esta tarea todavía no tiene archivos.'),
              ),
            if (_attachments.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _attachments.length,
                  itemBuilder: (context, index) {
                    final attachment = _attachments[index];

                    return ListTile(
                      dense: true,
                      title: Text(
                        attachment.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(_sizeLabel(attachment.sizeBytes)),
                      trailing: IconButton(
                        tooltip: 'Descargar ${attachment.name}',
                        onPressed: _busy
                            ? null
                            : () => _download(attachment),
                        icon: const Icon(Icons.download),
                      ),
                    );
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }
}
