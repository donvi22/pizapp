import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';

class TaskAttachment {
  const TaskAttachment({
    required this.id,
    required this.name,
    required this.sizeBytes,
  });

  final int id;
  final String name;
  final int sizeBytes;

  factory TaskAttachment.fromJson(Map<String, dynamic> json) {
    return TaskAttachment(
      id: json['id'] as int,
      name: json['original_name'] as String,
      sizeBytes: json['size_bytes'] as int,
    );
  }
}

class AttachmentClient {
  static const maxUploadMb = int.fromEnvironment('MAX_UPLOAD_MB', defaultValue: 100);
  AttachmentClient(this.api);

  final ApiClient api;

  String get _authorization {
    final token = api.token;
    if (token == null) {
      throw StateError('Inicia sesión antes de acceder a los archivos.');
    }
    return 'Token $token';
  }

  String _path(int projectId, int taskId) =>
      '${ApiClient.baseUrl}/projects/$projectId/tasks/$taskId/attachments/';

  Future<List<TaskAttachment>> list(int projectId, int taskId) async {
    final response = await http.get(
      Uri.parse(_path(projectId, taskId)),
      headers: {'Authorization': _authorization},
    );

    if (response.statusCode != 200) {
      throw Exception('No se pudieron cargar los archivos.');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;

    return data
        .map(
          (item) => TaskAttachment.fromJson(
            item as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<TaskAttachment?> pickAndUpload(
    int projectId,
    int taskId,
  ) async {
    final file = await FilePicker.pickFile(type: FileType.any);
    if (file == null) return null;

    final size = file.lengthSync() ?? await file.length();

    if (size == null) {
      throw Exception('No se pudo leer el tamaño del archivo.');
    }

    if (size > maxUploadMb * 1024 * 1024) {
      throw Exception('El archivo supera el límite de $maxUploadMb MB.');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse(_path(projectId, taskId)),
    );

    request.headers['Authorization'] = _authorization;
    request.files.add(
      http.MultipartFile(
        'file',
        file.readAsByteStream(),
        size,
        filename: file.name,
      ),
    );

    final response = await http.Response.fromStream(
      await request.send(),
    );

    if (response.statusCode != 201) {
      throw Exception(
        'No se pudo subir el archivo (${response.statusCode}): '
        '${response.body}',
      );
    }

    return TaskAttachment.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<bool> download(
    int projectId,
    int taskId,
    TaskAttachment attachment,
  ) async {
    final url =
        '${_path(projectId, taskId)}${attachment.id}/download/';

    final response = await http.get(
      Uri.parse(url),
      headers: {'Authorization': _authorization},
    );

    if (response.statusCode != 200) {
      throw Exception('No se pudo descargar el archivo.');
    }

    final destination = await FilePicker.saveFile(
      fileName: attachment.name,
      bytes: response.bodyBytes,
    );

    return destination != null;
  }
}
