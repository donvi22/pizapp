# Arquitectura de Pizapp

## Flujo de datos

Flutter envía peticiones HTTP a la API de Django REST Framework. El servidor autentica al usuario, comprueba su pertenencia al proyecto y los permisos específicos de la operación, valida los datos y accede a SQLite. Los adjuntos se almacenan en disco y se entregan a través de la API.

En local, Flutter Web y Django usan puertos diferentes, con CORS limitado a localhost y 127.0.0.1 en el puerto 5173. La demo publicada sirve el cliente en `/app/` y la API en `/api/` bajo el mismo dominio HTTPS.

## Modelo del dominio

- Un proyecto tiene propietario, miembros, tareas, hitos e ideas.
- Las invitaciones permiten ocupar una plaza del proyecto con una cuenta registrada.
- Una tarea incluye autor, estado, fecha opcional, hito opcional y los datos JSON de su pizarra.
- Los responsables tienen progreso individual. Los editores adicionales son un permiso independiente de esa responsabilidad.
- Tareas e ideas tienen comentarios. Una idea puede convertirse en una tarea conservando la conversación.
- Los archivos adjuntos pertenecen a tareas. El historial registra acciones y las notificaciones pertenecen a sus destinatarios.

## Permisos principales

| Operación | Quién puede realizarla |
| --- | --- |
| Leer un proyecto, sus tareas y adjuntos | Propietario y miembros actuales |
| Crear tareas, ideas e hitos | Propietario y miembros actuales |
| Editar una tarea | Propietario, autor o editor concedido por el propietario |
| Eliminar una tarea | Propietario o autor |
| Gestionar responsables y editores de una tarea | Propietario |
| Actualizar progreso individual | El responsable correspondiente |
| Editar o eliminar un hito | Propietario o autor |
| Eliminar una idea | Propietario o autor |
| Aprobar y convertir una idea en tarea | Propietario |
| Añadir comentarios y adjuntos | Propietario y miembros actuales |
| Eliminar un comentario | Su autor |
| Gestionar miembros o eliminar el proyecto | Propietario |

Al retirar un miembro, pierde el acceso al proyecto y se eliminan sus concesiones de edición. El cliente muestra modo lectura cuando no hay permiso de edición; la API también rechaza las modificaciones no autorizadas.

## Rutas principales

Las rutas siguientes se muestran relativas a `/api/`. No constituyen una especificación completa de todos los métodos y cuerpos de petición.

| Ruta | Uso |
| --- | --- |
| `register/`, `login/` | Registro y obtención del token |
| `health/` | Comprobar que el servicio responde |
| `projects/` | Proyectos del usuario |
| `projects/{proyecto}/tasks/` | Tareas del proyecto |
| `projects/{proyecto}/tasks/{tarea}/` | Detalle y modificación de tarea |
| `projects/{proyecto}/tasks/{tarea}/editors/` | Permisos adicionales de edición |
| `projects/{proyecto}/tasks/{tarea}/assignments/` | Responsables |
| `projects/{proyecto}/tasks/{tarea}/assignments/{usuario}/` | Progreso individual |
| `projects/{proyecto}/tasks/{tarea}/attachments/` | Adjuntos |
| `projects/{proyecto}/tasks/{tarea}/attachments/{archivo}/download/` | Descarga autenticada |
| `projects/{proyecto}/slots/` | Plazas de colaboradores |
| `invitations/{codigo}/join/` | Incorporación al proyecto |
| `projects/{proyecto}/milestones/` | Hitos |
| `projects/{proyecto}/ideas/` | Ideas |
| `projects/{proyecto}/ideas/{idea}/convert/` | Conversión de idea en tarea |
| `projects/{proyecto}/activity/` | Historial de actividad |
| `notifications/`, `notifications/sync/` | Consulta y actualización de avisos internos |

Las peticiones autenticadas incluyen `Authorization: Token <token>`. El token no debe incluirse en ejemplos públicos, capturas o archivos de configuración versionados.

## Persistencia y pruebas

Las migraciones forman parte del código versionado. La base de datos, los adjuntos y la configuración privada de producción quedan fuera del repositorio.

Las pruebas de Django utilizan una base de datos de pruebas independiente. Cubren operaciones de la API y sus restricciones, incluyendo la revocación de permisos y los límites de almacenamiento. El workflow también analiza el cliente y compila su versión web. La ejecución de GitHub Actions se verifica al publicar el repositorio; las pruebas de integración del cliente quedan pendientes.

SQLite permite una instalación sencilla de la demo. La edición concurrente de una misma pizarra puede sobrescribir un guardado anterior; no hay control de versiones de la pizarra ni canal WebSocket.
