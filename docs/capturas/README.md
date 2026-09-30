# Capturas reales para el portfolio

Guarda aquí capturas PNG de la demo, con los siguientes nombres. El script de preparación añadirá al README únicamente las que existan.

| Archivo | Qué mostrar |
| --- | --- |
| `01-proyectos.png` | Lista de proyectos con nombres y contadores coherentes |
| `02-pizarra.png` | Una tarea con un esquema dibujado y bloques de texto |
| `03-reparto.png` | Dos responsables y sus estados individuales |
| `04-resumen.png` | Resumen del proyecto con tareas e hitos |
| `05-historial.png` | Acciones reales de las dos cuentas |

Utiliza un proyecto de ejemplo, por ejemplo «Organización de una jornada», con tareas como «Preparar programa» o «Diseñar cartel». Usa las mismas tareas en las distintas pantallas para que se entienda el flujo.

En Windows puedes capturar una región con Win + Mayús + S. Comprueba que los textos se leen y que no aparecen contraseñas, tokens, datos personales ni enlaces de invitación activos. No añadas imágenes vacías o capturas inventadas.

Después de guardarlas, ejecuta desde la raíz:

```powershell
powershell -ExecutionPolicy Bypass -File .\portfolio\preparar_portfolio.ps1
```
